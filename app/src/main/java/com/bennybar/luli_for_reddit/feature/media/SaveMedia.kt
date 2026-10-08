package com.bennybar.luli_for_reddit.feature.media

import android.content.ContentValues
import android.os.Environment
import android.provider.MediaStore
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.core.net.Http
import com.bennybar.luli_for_reddit.ui.Overlays
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.isActive
import kotlinx.coroutines.job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import okhttp3.Request
import java.io.File
import java.io.IOException
import java.util.Locale
import java.util.concurrent.TimeUnit

// Reddit's CDN (v.redd.it) closes the connection mid-stream for requests
// without a real User-Agent, so set one and allow a generous timeout.
private const val DOWNLOAD_UA =
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"

private val downloadClient by lazy { Http.client.newBuilder().readTimeout(90, TimeUnit.SECONDS).build() }

private fun mimeFor(ext: String, isVideo: Boolean): String = when (ext) {
    "png" -> "image/png"
    "gif" -> "image/gif"
    "webp" -> "image/webp"
    "jpg", "jpeg" -> "image/jpeg"
    "mp4" -> "video/mp4"
    else -> if (isVideo) "video/mp4" else "image/jpeg"
}

/**
 * The download behind [saveMediaToGallery]: fetches [url] to a temp file,
 * then copies it into the picked folder (as `ilay_<ts>`), else the gallery's
 * "Ilay" album: Pictures/Ilay for images *and* videos, named `luli_<ts>`, as
 * the Flutter build's gal plugin saved them, so existing users keep one
 * album. Runs on the app scope, so leaving the
 * screen doesn't abort a save; the dialog's Cancel does.
 */
internal suspend fun saveMedia(url: String, isVideo: Boolean) {
    val nav = app.navigatorOrNull ?: return
    val folder = app.media.folder.value
    val progress = MutableStateFlow(0L to 0L) // (received, total)
    val finished = MutableStateFlow(false)

    val job = app.scope.launch(Dispatchers.IO) {
        val clean = url.substringBefore('?')
        var ext = if ('.' in clean.substringAfterLast('/')) clean.substringAfterLast('.').lowercase() else ""
        if (ext.isEmpty() || ext.length > 4) ext = if (isVideo) "mp4" else "jpg"
        val ts = System.currentTimeMillis()
        val tmp = File(app.context.cacheDir, "luli_$ts.$ext")
        try {
            val req = Request.Builder().url(url).header("User-Agent", DOWNLOAD_UA).build()
            val call = downloadClient.newCall(req)
            // Cancel aborts a blocked read at once, not at the next chunk.
            coroutineContext.job.invokeOnCompletion { call.cancel() }
            call.execute().use { res ->
                if (!res.isSuccessful) throw IOException("HTTP ${res.code}")
                val body = res.body
                val total = body.contentLength().coerceAtLeast(0)
                tmp.outputStream().use { out ->
                    body.byteStream().use { input ->
                        val buf = ByteArray(64 * 1024)
                        var got = 0L
                        var lastEmit = 0L
                        while (true) {
                            coroutineContext.ensureActive()
                            val n = input.read(buf)
                            if (n < 0) break
                            out.write(buf, 0, n)
                            got += n
                            if (got - lastEmit > 128 * 1024 || got == total) {
                                lastEmit = got
                                progress.value = got to total
                            }
                        }
                    }
                }
            }
            val mime = mimeFor(ext, isVideo)
            if (folder != null && app.media.saveToFolder(folder, tmp, "ilay_$ts.$ext", mime)) {
                finished.value = true
                nav.showSnackbar("Saved to ${folder.name}")
                return@launch
            }
            insertIntoGallery(tmp, tmp.name, mime, isVideo)
            finished.value = true
            nav.showSnackbar(
                if (folder == null) "Saved to your gallery"
                else "Couldn't open ${folder.name}, so saved to your gallery. Pick the folder again in Settings.",
            )
        } catch (e: CancellationException) {
            finished.value = true
            nav.showSnackbar("Download cancelled")
            throw e
        } catch (e: IOException) {
            finished.value = true
            nav.showSnackbar(if (isActive) "Could not save" else "Download cancelled")
        } catch (e: Exception) {
            finished.value = true
            nav.showSnackbar("Could not save: ${e.message ?: e}")
        } finally {
            tmp.delete()
        }
    }

    // Cancelled before the download even started: the body never ran, so
    // close the dialog (and report) from here.
    job.invokeOnCompletion { cause ->
        if (!finished.value && cause is CancellationException) nav.showSnackbar("Download cancelled")
        finished.value = true
    }
    app.scope.launch {
        Overlays.show<Unit> { done ->
            LaunchedEffect(Unit) {
                finished.first { it }
                done(null)
            }
            SavingDialog(progress, onCancel = { job.cancel() })
        }
    }
    job.join()
}

/** MediaStore insert into Pictures/Ilay — videos too, like gal did (no storage permission needed). */
private fun insertIntoGallery(file: File, name: String, mime: String, isVideo: Boolean) {
    val resolver = app.context.contentResolver
    val collection = if (isVideo) {
        MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
    } else {
        MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
    }
    val values = ContentValues().apply {
        put(MediaStore.MediaColumns.DISPLAY_NAME, name)
        put(MediaStore.MediaColumns.MIME_TYPE, mime)
        put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/Ilay")
        put(MediaStore.MediaColumns.IS_PENDING, 1)
    }
    val uri = resolver.insert(collection, values) ?: throw IOException("The gallery refused the file")
    try {
        resolver.openOutputStream(uri)!!.use { out -> file.inputStream().use { it.copyTo(out) } }
        resolver.update(uri, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null)
    } catch (e: Exception) {
        resolver.delete(uri, null, null)
        throw e
    }
}

private fun mb(bytes: Long) = String.format(Locale.US, "%.1f", bytes / 1048576.0)

@Composable
private fun SavingDialog(progress: StateFlow<Pair<Long, Long>>, onCancel: () -> Unit) {
    val p by progress.collectAsStateWithLifecycle()
    val (received, total) = p
    AlertDialog(
        onDismissRequest = {},
        properties = DialogProperties(dismissOnBackPress = false, dismissOnClickOutside = false),
        text = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (total > 0) {
                    CircularProgressIndicator(
                        progress = { (received.toFloat() / total).coerceIn(0f, 1f) },
                        modifier = Modifier.size(26.dp),
                        strokeWidth = 3.dp,
                    )
                } else {
                    CircularProgressIndicator(Modifier.size(26.dp), strokeWidth = 3.dp)
                }
                Spacer(Modifier.width(18.dp))
                Text(if (total > 0) "Saving… ${mb(received)} / ${mb(total)} MB" else "Saving…")
            }
        },
        confirmButton = {},
        dismissButton = { TextButton(onClick = onCancel) { Text("Cancel") } },
    )
}
