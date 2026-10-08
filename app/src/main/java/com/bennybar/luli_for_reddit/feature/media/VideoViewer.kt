package com.bennybar.luli_for_reddit.feature.media

import android.content.Context
import android.view.TextureView
import androidx.annotation.OptIn
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.OpenInNew
import androidx.compose.material.icons.rounded.Forward10
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Replay10
import androidx.compose.material.icons.rounded.VideocamOff
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import com.bennybar.luli_for_reddit.core.RedditConstants
import com.bennybar.luli_for_reddit.core.net.Http
import com.bennybar.luli_for_reddit.nav.MediaViewer
import kotlinx.coroutines.delay

/**
 * An ExoPlayer on the shared OkHttp pool (warm connections to v.redd.it).
 * [audioFocus]: only the full-screen viewer takes audio focus — muted feed
 * autoplay must never pause the user's music.
 */
@OptIn(UnstableApi::class)
internal fun buildPlayer(context: Context, audioFocus: Boolean): ExoPlayer {
    val data = OkHttpDataSource.Factory(Http.client).setUserAgent(RedditConstants.WEB_USER_AGENT)
    return ExoPlayer.Builder(context)
        .setMediaSourceFactory(DefaultMediaSourceFactory(data))
        .setAudioAttributes(
            AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).build(),
            audioFocus,
        )
        .build()
}

/** v.redd.it HLS (HLSPlaylist.m3u8) or a progressive mp4 (DASH_720.mp4, imgur, RedGifs…). */
internal fun mediaItemFor(url: String): MediaItem =
    MediaItem.Builder().setUri(url).apply {
        if (url.substringBefore('?').lowercase().endsWith(".m3u8")) setMimeType(MimeTypes.APPLICATION_M3U8)
    }.build()

private fun fmt(ms: Long): String {
    val total = (ms.coerceAtLeast(0)) / 1000
    val h = total / 3600
    val m = (total / 60) % 60
    val s = total % 60
    return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%02d:%02d".format(m, s)
}

/** Full-screen video player with sound. */
@Composable
internal fun VideoViewer(route: MediaViewer.Video) {
    ImmersiveMode()
    val context = LocalContext.current
    val player = remember {
        buildPlayer(context, audioFocus = true).apply {
            repeatMode = Player.REPEAT_MODE_ONE
            setMediaItem(mediaItemFor(route.url))
            prepare()
            playWhenReady = true
        }
    }
    var error by remember { mutableStateOf<String?>(null) }
    var ready by remember { mutableStateOf(false) }
    var playing by remember { mutableStateOf(false) }
    var aspect by remember { mutableFloatStateOf(0f) }
    var controls by remember { mutableStateOf(true) }
    var hideTick by remember { mutableIntStateOf(0) }
    var position by remember { mutableLongStateOf(0L) }
    var duration by remember { mutableLongStateOf(0L) }
    var buffered by remember { mutableLongStateOf(0L) }

    DisposableEffect(player) {
        val listener = object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                if (state == Player.STATE_READY && !ready) {
                    ready = true
                    hideTick++
                }
            }

            override fun onIsPlayingChanged(isPlaying: Boolean) {
                playing = isPlaying
            }

            override fun onVideoSizeChanged(videoSize: VideoSize) {
                if (videoSize.width > 0 && videoSize.height > 0) {
                    aspect = videoSize.width * videoSize.pixelWidthHeightRatio / videoSize.height
                }
            }

            override fun onPlayerError(e: PlaybackException) {
                error = e.message ?: e.errorCodeName
            }
        }
        player.addListener(listener)
        // Owned from creation so leaving always releases it, even mid-load.
        onDispose {
            player.removeListener(listener)
            player.release()
        }
    }

    // Pause in the background; resume if it was playing.
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(lifecycle) {
        var wasPlaying = false
        val obs = LifecycleEventObserver { _, e ->
            when (e) {
                Lifecycle.Event.ON_PAUSE -> {
                    wasPlaying = player.playWhenReady
                    player.pause()
                }
                Lifecycle.Event.ON_RESUME -> if (wasPlaying) player.play()
                else -> {}
            }
        }
        lifecycle.addObserver(obs)
        onDispose { lifecycle.removeObserver(obs) }
    }

    // Position for the time labels / scrubber, while the controls are up.
    LaunchedEffect(controls, ready) {
        while (controls && ready) {
            position = player.currentPosition
            duration = player.duration.takeIf { it != C.TIME_UNSET } ?: 0L
            buffered = player.bufferedPosition
            delay(200)
        }
    }
    // Only auto-hide while playing; keep controls up when paused.
    LaunchedEffect(controls, playing, hideTick) {
        if (controls && playing) {
            delay(3000)
            controls = false
        }
    }

    fun seekBy(seconds: Int) {
        val max = player.duration.takeIf { it != C.TIME_UNSET } ?: Long.MAX_VALUE
        player.seekTo((player.currentPosition + seconds * 1000L).coerceIn(0L, max))
        position = player.currentPosition
        hideTick++
    }

    val link = route.externalUrl ?: route.url
    val controlsAlpha by animateFloatAsState(if (controls) 1f else 0f, tween(150), label = "videoControls")

    Box(Modifier.fillMaxSize().background(Color.Black)) {
        val err = error
        if (err != null) {
            Column(
                Modifier.align(Alignment.Center).padding(28.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Icon(Icons.Rounded.VideocamOff, null, Modifier.size(48.dp), tint = Color.White.copy(alpha = 0.54f))
                Spacer(Modifier.height(14.dp))
                Text(
                    "This video can't be played in the app — its format isn't supported on this device.",
                    textAlign = TextAlign.Center,
                    color = Color.White.copy(alpha = 0.7f),
                    fontSize = 15.sp,
                )
                Spacer(Modifier.height(20.dp))
                Button(onClick = { openExternally(context, link) }) {
                    Icon(Icons.AutoMirrored.Rounded.OpenInNew, null, Modifier.size(18.dp))
                    Spacer(Modifier.width(8.dp))
                    Text("Open in browser")
                }
            }
        } else {
            // Tapping the video only toggles the overlay — it never changes play state.
            Box(
                Modifier
                    .fillMaxSize()
                    .clickable(remember { MutableInteractionSource() }, null) {
                        controls = !controls
                        if (controls) hideTick++
                    },
                contentAlignment = Alignment.Center,
            ) {
                AndroidView(
                    factory = { ctx -> TextureView(ctx).also { player.setVideoTextureView(it) } },
                    onRelease = { player.clearVideoTextureView(it) },
                    modifier = (if (aspect > 0f) Modifier.aspectRatio(aspect) else Modifier.fillMaxSize())
                        .alpha(if (ready) 1f else 0f),
                )
            }
            if (!ready) CircularProgressIndicator(Modifier.align(Alignment.Center), color = Color.White)
        }

        // Playback controls overlay (tap the video to show/hide).
        if (err == null && ready && controlsAlpha > 0.01f) {
            Box(Modifier.fillMaxSize().alpha(controlsAlpha).background(Color.Black.copy(alpha = 0.26f))) {
                Row(
                    Modifier.align(Alignment.Center),
                    horizontalArrangement = Arrangement.spacedBy(28.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    CircleBtn(Icons.Rounded.Replay10, "Back 10 seconds") { seekBy(-10) }
                    CircleBtn(if (playing) Icons.Rounded.Pause else Icons.Rounded.PlayArrow, "Play/pause", big = true) {
                        if (player.isPlaying) player.pause() else player.play()
                        hideTick++
                    }
                    CircleBtn(Icons.Rounded.Forward10, "Forward 10 seconds") { seekBy(10) }
                }
                // Bottom: time + draggable scrubber.
                Row(
                    Modifier
                        .align(Alignment.BottomCenter)
                        .navigationBarsPadding()
                        .padding(start = 16.dp, end = 16.dp, bottom = 28.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(fmt(position), color = Color.White, fontSize = 12.sp)
                    Scrubber(
                        position = position,
                        duration = duration,
                        buffered = buffered,
                        onSeek = { ms ->
                            player.seekTo(ms)
                            position = ms
                            hideTick++
                        },
                        modifier = Modifier.weight(1f).padding(horizontal = 10.dp),
                    )
                    Text(fmt(duration), color = Color.White, fontSize = 12.sp)
                }
            }
        }

        if (controls || err != null) {
            ViewerControls(
                title = route.title,
                sourceUrl = link,
                // A direct mp4 for saving (an HLS playlist can't be saved).
                downloadUrl = route.downloadUrl?.takeIf { ".m3u8" !in it },
                downloadIsVideo = true,
                modifier = if (err == null) Modifier.alpha(controlsAlpha) else Modifier,
            )
        }
        EdgeBack()
    }
}

@Composable
private fun CircleBtn(icon: ImageVector, description: String, big: Boolean = false, onTap: () -> Unit) {
    Box(
        Modifier
            .size(if (big) 72.dp else 56.dp)
            .clip(CircleShape)
            .background(Color.Black.copy(alpha = 0.45f))
            .clickable(onClick = onTap),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, description, Modifier.size(if (big) 40.dp else 28.dp), tint = Color.White)
    }
}

/** An ~8dp thick progress bar you can tap or drag to seek. */
@Composable
private fun Scrubber(position: Long, duration: Long, buffered: Long, onSeek: (Long) -> Unit, modifier: Modifier) {
    var dragFraction by remember { mutableStateOf<Float?>(null) }
    val played = dragFraction ?: if (duration > 0) (position.toFloat() / duration).coerceIn(0f, 1f) else 0f
    val buf = if (duration > 0) (buffered.toFloat() / duration).coerceIn(0f, 1f) else 0f
    Canvas(
        modifier
            .fillMaxWidth()
            .height(26.dp)
            .pointerInput(duration) {
                detectTapGestures { o ->
                    if (duration > 0) onSeek(((o.x / size.width).coerceIn(0f, 1f) * duration).toLong())
                }
            }
            .pointerInput(duration) {
                fun frac(x: Float) = (x / size.width).coerceIn(0f, 1f)
                detectHorizontalDragGestures(
                    onDragStart = { o -> dragFraction = frac(o.x) },
                    onHorizontalDrag = { change, _ -> dragFraction = frac(change.position.x) },
                    onDragEnd = {
                        val f = dragFraction
                        if (f != null && duration > 0) onSeek((f * duration).toLong())
                        dragFraction = null
                    },
                    onDragCancel = { dragFraction = null },
                )
            },
    ) {
        val h = 8.dp.toPx()
        val top = (size.height - h) / 2
        val r = CornerRadius(h / 2, h / 2)
        drawRoundRect(Color.White.copy(alpha = 0.24f), Offset(0f, top), Size(size.width, h), r)
        drawRoundRect(Color.White.copy(alpha = 0.38f), Offset(0f, top), Size(size.width * buf, h), r)
        drawRoundRect(Color.White, Offset(0f, top), Size(size.width * played, h), r)
    }
}
