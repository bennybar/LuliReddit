package com.bennybar.luli_for_reddit.feature.media

import android.content.Intent
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.net.Uri
import androidx.compose.runtime.LaunchedEffect
import androidx.core.content.FileProvider
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.core.isImageUrl
import com.bennybar.luli_for_reddit.core.net.Redgifs
import com.bennybar.luli_for_reddit.model.Post
import com.bennybar.luli_for_reddit.model.PostType
import com.bennybar.luli_for_reddit.ui.Overlays
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.nio.ByteBuffer

/** Shared files are kept this long (the receiving app reads them after the share sheet closes), then deleted. */
private const val KEEP_MS = 30 * 60_000L

/** Image, GIF, gallery and Reddit / Redgifs video posts: the ones "Share as media" can download. */
fun canShareAsMedia(p: Post): Boolean = when (p.type) {
    PostType.IMAGE, PostType.GIF -> true
    PostType.GALLERY -> p.gallery.isNotEmpty()
    PostType.VIDEO -> !isExternalVideo(p) && (p.fallbackVideoUrl != null || Redgifs.id(p.url) != null)
    else -> false
}

/**
 * "Share as media": downloads the post's image(s) or video and hands the
 * files themselves to the share sheet, rather than a link. They live in the
 * app's cache only until shared: deleted [KEEP_MS] later (or at the next
 * share, if the app was closed meanwhile).
 */
fun shareAsMedia(post: Post) {
    val nav = app.navigatorOrNull ?: return
    val progress = MutableStateFlow(0L to 0L)
    val finished = MutableStateFlow(false)
    val root = File(app.context.cacheDir, "share_media")
    val dir = File(root, System.currentTimeMillis().toString())

    val job = app.scope.launch(Dispatchers.IO) {
        try {
            // Anything left over from shares older than KEEP_MS.
            root.listFiles()?.forEach { if (System.currentTimeMillis() - it.lastModified() > KEEP_MS) it.deleteRecursively() }
            dir.mkdirs()
            val files = download(post, dir) { got, total -> progress.value = got to total }
            if (files.isEmpty()) throw IllegalStateException("No media")
            val ctx = app.context
            val uris = files.map { FileProvider.getUriForFile(ctx, "${ctx.packageName}.files", it) }
            val mimes = files.map { mimeFor(it.extension, it.extension == "mp4") }
            val send = if (uris.size == 1) {
                Intent(Intent.ACTION_SEND).putExtra(Intent.EXTRA_STREAM, uris[0]).setType(mimes[0])
            } else {
                Intent(Intent.ACTION_SEND_MULTIPLE)
                    .putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList(uris))
                    .setType(if (mimes.all { it.startsWith("image/") }) "image/*" else "*/*")
            }
            send.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            finished.value = true
            withContext(Dispatchers.Main) {
                ctx.startActivity(Intent.createChooser(send, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }
            app.scope.launch(Dispatchers.IO) {
                delay(KEEP_MS)
                dir.deleteRecursively()
            }
        } catch (e: CancellationException) {
            dir.deleteRecursively()
            throw e
        } catch (e: Exception) {
            dir.deleteRecursively()
            finished.value = true
            nav.showSnackbar("Couldn't download the media to share")
        }
    }
    job.invokeOnCompletion { cause ->
        if (cause is CancellationException) {
            dir.deleteRecursively()
            nav.showSnackbar("Share cancelled")
        }
        finished.value = true
    }
    app.scope.launch {
        Overlays.show<Unit> { done ->
            LaunchedEffect(Unit) {
                finished.first { it }
                done(null)
            }
            SavingDialog(progress, onCancel = { job.cancel() }, verb = "Downloading")
        }
    }
}

/** Downloads [post]'s media into [dir]: one file, or one per gallery image. */
private suspend fun download(post: Post, dir: File, onProgress: (Long, Long) -> Unit): List<File> {
    fun target(url: String, fallbackExt: String, i: Int = 0): File {
        val name = url.substringBefore('?').substringAfterLast('/')
        val ext = name.substringAfterLast('.', "").lowercase().takeIf { it.length in 3..4 } ?: fallbackExt
        return File(dir, "ilay_${post.id}${if (i > 0) "_$i" else ""}.$ext")
    }
    suspend fun image(url: String, i: Int = 0) = target(url, "jpg", i).also { downloadTo(url, it, onProgress) }

    return when (post.type) {
        PostType.IMAGE -> {
            val url = if (isImageUrl(Uri.parse(post.url))) post.url else post.previewUrl ?: post.url
            listOf(image(url))
        }
        // Reddit's mp4 version of a GIF is a fraction of the size; apps play it like a GIF.
        PostType.GIF -> listOf(post.gifMp4Url?.let { mp4 -> target(mp4, "mp4").also { downloadTo(mp4, it, onProgress) } } ?: image(post.url))
        PostType.GALLERY -> post.gallery.mapIndexed { i, g -> image(g.url, i) }
        PostType.VIDEO -> {
            val redgifs = if (post.fallbackVideoUrl == null && Redgifs.id(post.url) != null) Redgifs.resolve(post.url) else null
            val video = redgifs ?: post.fallbackVideoUrl ?: return emptyList()
            val out = File(dir, "ilay_${post.id}.mp4")
            if (redgifs != null) {
                downloadTo(video, out, onProgress)
                return listOf(out)
            }
            downloadRedditVideo(video, out, onProgress)
            listOf(out)
        }
        else -> emptyList()
    }
}

/**
 * Downloads a Reddit-hosted video (v.redd.it) into [out] *with its sound*: a
 * Reddit video's mp4 has none, the audio (if the video has any) is a separate
 * file named in its DASH playlist (DASH_AUDIO_128.mp4, CMAF_AUDIO_128.mp4…).
 * Both are downloaded next to [out] and put together, without re-encoding.
 */
internal suspend fun downloadRedditVideo(videoUrl: String, out: File, onProgress: (Long, Long) -> Unit) {
    val dir = out.parentFile!!
    val stamp = System.nanoTime()
    val silent = File(dir, "video_$stamp.mp4")
    val audio = File(dir, "audio_$stamp.mp4")
    val mpd = File(dir, "playlist_$stamp.mpd")
    try {
        downloadTo(videoUrl, silent, onProgress)
        val base = videoUrl.substringBefore('?').substringBeforeLast('/')
        val audioName = runCatching {
            downloadTo("$base/DASHPlaylist.mpd", mpd) { _, _ -> }
            audioTrack(mpd.readText())
        }.onFailure { if (it is CancellationException) throw it }.getOrNull()
        val gotAudio = audioName != null && runCatching { downloadTo("$base/$audioName", audio, onProgress) }
            .onFailure { if (it is CancellationException) throw it }.isSuccess
        if (!(gotAudio && runCatching { mux(silent, audio, out) }.isSuccess)) {
            silent.copyTo(out, overwrite = true) // no sound (a silent clip): the video as is
        }
    } finally {
        silent.delete()
        audio.delete()
        mpd.delete()
    }
}

/** The best audio file named in a DASH playlist, or null when the video has no sound. */
internal fun audioTrack(mpd: String): String? =
    Regex("<AdaptationSet\\b[^>]*>.*?</AdaptationSet>", RegexOption.DOT_MATCHES_ALL).findAll(mpd)
        .map { it.value }
        .filter { "contentType=\"audio\"" in it || "mimeType=\"audio/" in it }
        .flatMap { set ->
            Regex("<Representation\\b[^>]*?bandwidth=\"(\\d+)\"[^>]*>.*?<BaseURL>([^<]+)</BaseURL>", RegexOption.DOT_MATCHES_ALL).findAll(set)
                .map { it.groupValues[1].toLong() to it.groupValues[2].trim() }
        }
        .maxByOrNull { it.first }?.second

/** Puts [video]'s picture and [audio]'s sound into one mp4, copying the samples as they are. */
private fun mux(video: File, audio: File, out: File) {
    val muxer = MediaMuxer(out.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
    val sources = ArrayList<Pair<MediaExtractor, Int>>()
    try {
        for ((f, kind) in listOf(video to "video/", audio to "audio/")) {
            val ex = MediaExtractor()
            sources.add(ex to -1)
            ex.setDataSource(f.path)
            val track = (0 until ex.trackCount).first { ex.getTrackFormat(it).getString(MediaFormat.KEY_MIME)!!.startsWith(kind) }
            ex.selectTrack(track)
            sources[sources.lastIndex] = ex to muxer.addTrack(ex.getTrackFormat(track))
        }
        muxer.start()
        val buf = ByteBuffer.allocate(8 shl 20)
        val info = MediaCodec.BufferInfo()
        for ((ex, track) in sources) {
            while (true) {
                val n = ex.readSampleData(buf, 0)
                if (n < 0) break
                val key = ex.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0
                info.set(0, n, ex.sampleTime, if (key) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0)
                muxer.writeSampleData(track, buf, info)
                ex.advance()
            }
        }
        muxer.stop()
    } finally {
        muxer.release()
        sources.forEach { it.first.release() }
    }
}
