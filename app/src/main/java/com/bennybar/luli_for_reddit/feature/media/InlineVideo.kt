package com.bennybar.luli_for_reddit.feature.media

import android.content.Context
import android.view.TextureView
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.VolumeOff
import androidx.compose.material.icons.automirrored.rounded.VolumeUp
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.layout
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.exoplayer.ExoPlayer
import coil3.compose.AsyncImage
import com.bennybar.luli_for_reddit.app
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlin.math.roundToInt

/** True under a cover (e.g. an unrevealed NSFW blur): inline videos don't autoplay there. */
val LocalMediaCovered = compositionLocalOf { false }

/** A card counts as on screen (and may play) once this much of it is visible. */
private const val VISIBLE_THRESHOLD = 0.6f

/**
 * One ExoPlayer shared by every inline feed video. Each [InlineVideo] reports
 * how much of it is on screen; the most visible one past the threshold gets
 * the player, every other card shows its poster. One decoder for the whole
 * feed — instead of one per nearby card competing while scrolling, which is
 * what made long feeds stutter. Positions are remembered per URL, so a clip
 * scrolled away and back resumes where it was. Main thread only.
 */
class InlineVideoPool(private val context: Context) {
    private class Candidate(var url: String, var fraction: Float, var muted: Boolean)

    private var player: ExoPlayer? = null
    private val candidates = LinkedHashMap<Any, Candidate>()
    private val positions = object : LinkedHashMap<String, Long>(32, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Long>?) = size > 64
    }
    private var activeUrl: String? = null
    private var foreground = true

    /** A full-screen viewer is open over the feed (it stays composed beneath). */
    private var covered = false

    private val _active = MutableStateFlow<Any?>(null)

    /** The key of the card currently holding the player. */
    val active: StateFlow<Any?> = _active
    private val _firstFrame = MutableStateFlow(false)

    /** The active clip has drawn its first frame (until then the surface is blank). */
    val firstFrame: StateFlow<Boolean> = _firstFrame
    private val _videoSize = MutableStateFlow(VideoSize.UNKNOWN)
    val videoSize: StateFlow<VideoSize> = _videoSize
    private val _ready = MutableStateFlow(false)

    /** The active clip is prepared (the mute toggle shows from here). */
    val ready: StateFlow<Boolean> = _ready

    init {
        // Pause with the app; resume the active clip on return.
        ProcessLifecycleOwner.get().lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onStop(owner: LifecycleOwner) {
                foreground = false
                player?.pause()
            }

            override fun onStart(owner: LifecycleOwner) {
                foreground = true
                if (_active.value != null && !covered) player?.play()
            }
        })
    }

    /** Pauses the feed clip while a media viewer covers it; resumes after. */
    fun setCovered(value: Boolean) {
        if (covered == value) return
        covered = value
        if (value) player?.pause() else if (foreground && _active.value != null) player?.play()
    }

    private fun player(): ExoPlayer = player ?: buildPlayer(context, audioFocus = false).also { p ->
        p.repeatMode = Player.REPEAT_MODE_ONE
        p.volume = 0f
        p.addListener(object : Player.Listener {
            override fun onRenderedFirstFrame() {
                _firstFrame.value = true
            }

            override fun onVideoSizeChanged(videoSize: VideoSize) {
                _videoSize.value = videoSize
            }

            override fun onPlaybackStateChanged(state: Int) {
                if (state == Player.STATE_READY) _ready.value = true
            }
        })
        player = p
    }

    fun report(key: Any, url: String, fraction: Float, muted: Boolean) {
        val c = candidates[key]
        if (c == null) {
            candidates[key] = Candidate(url, fraction, muted)
        } else {
            if (c.url == url && c.fraction == fraction) return
            c.url = url
            c.fraction = fraction
        }
        recompute()
    }

    fun remove(key: Any) {
        if (candidates.remove(key) != null) recompute()
    }

    fun setMuted(key: Any, muted: Boolean) {
        candidates[key]?.muted = muted
        if (_active.value == key) player?.volume = if (muted) 0f else 1f
    }

    fun attach(view: TextureView) = player().setVideoTextureView(view)
    fun detach(view: TextureView) {
        player?.clearVideoTextureView(view)
    }

    private fun recompute() {
        val current = _active.value
        val eligible = candidates.entries.filter { it.value.fraction > VISIBLE_THRESHOLD }
        var best = eligible.maxByOrNull { it.value.fraction }
        // Hysteresis: keep the playing card while it's (about) as visible as the best.
        val cur = eligible.firstOrNull { it.key == current }
        if (cur != null && best != null && cur.value.fraction >= best.value.fraction - 0.05f) best = cur
        val bestKey = best?.key
        if (bestKey == current && best?.value?.url == activeUrl) return

        val p = player
        activeUrl?.let { url -> p?.let { positions[url] = it.currentPosition } }
        if (best == null) {
            _active.value = null
            activeUrl = null
            _ready.value = false
            _firstFrame.value = false
            // Nothing on screen: free the decoder, keep the player for the next card.
            p?.stop()
            p?.clearMediaItems()
            return
        }
        val c = best.value
        val pl = player()
        _ready.value = false
        _firstFrame.value = false
        _videoSize.value = VideoSize.UNKNOWN
        activeUrl = c.url
        _active.value = bestKey
        pl.volume = if (c.muted) 0f else 1f
        pl.setMediaItem(mediaItemFor(c.url), positions[c.url] ?: 0L)
        pl.prepare()
        pl.playWhenReady = foreground && !covered
    }
}

/**
 * Feed video: autoplays muted + looping while visible, pauses off-screen;
 * tap = viewer. The player is attached only once the card is mostly on
 * screen (not when it's built: the list composes cards ahead of the
 * viewport). Respects Settings › autoplay media.
 */
@Composable
internal fun InlineVideoImpl(url: String, height: Dp, onTap: () -> Unit, modifier: Modifier, poster: String?) {
    val settings by remember { app.settings.state }.collectAsStateWithLifecycle()
    val covered = LocalMediaCovered.current
    val canPlay = settings.autoplayMedia && !covered
    val pool = remember { app.media.inlinePlayer }
    val key = remember { Any() }
    var muted by remember { mutableStateOf(true) }
    val currentUrl by rememberUpdatedState(url)
    val active by pool.active.collectAsStateWithLifecycle()
    val isActive = active === key

    DisposableEffect(pool, key) { onDispose { pool.remove(key) } }
    LaunchedEffect(canPlay) { if (!canPlay) pool.remove(key) }

    Box(
        modifier
            .fillMaxWidth()
            .height(height)
            .clipToBounds()
            .clickable(onClick = onTap)
            .then(
                if (canPlay) {
                    Modifier.onGloballyPositioned { coords ->
                        val h = coords.size.height
                        val visible = if (h > 0 && coords.isAttached) coords.boundsInWindow().height / h else 0f
                        // Quantized, so scrolling doesn't recompute on every pixel.
                        pool.report(key, currentUrl, (visible * 20).roundToInt() / 20f, muted)
                    }
                } else Modifier,
            ),
    ) {
        // The poster stays underneath; the video fades in on top once it has a frame.
        if (poster != null) {
            AsyncImage(poster, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
        } else {
            Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.07f)))
        }
        if (!canPlay) {
            Box(
                Modifier.align(Alignment.Center).size(56.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.5f)),
                contentAlignment = Alignment.Center,
            ) { Icon(Icons.Rounded.PlayArrow, "Play", Modifier.size(34.dp), tint = Color.White) }
        }
        if (isActive) {
            val firstFrame by pool.firstFrame.collectAsStateWithLifecycle()
            val ready by pool.ready.collectAsStateWithLifecycle()
            val size by pool.videoSize.collectAsStateWithLifecycle()
            val alpha by animateFloatAsState(if (firstFrame) 1f else 0f, tween(150), label = "inlineFade")
            AndroidView(
                factory = { ctx -> TextureView(ctx).also(pool::attach) },
                onRelease = pool::detach,
                modifier = Modifier
                    .coverLayout(size)
                    .graphicsLayer { this.alpha = alpha },
            )
            if (!firstFrame) {
                CircularProgressIndicator(Modifier.align(Alignment.Center).size(26.dp), strokeWidth = 2.dp)
            }
            // Mute / unmute toggle.
            if (ready) {
                Box(
                    Modifier
                        .align(Alignment.BottomEnd)
                        .padding(8.dp)
                        .clip(CircleShape)
                        .background(Color.Black.copy(alpha = 0.5f))
                        .clickable {
                            muted = !muted
                            pool.setMuted(key, muted)
                        }
                        .padding(7.dp),
                ) {
                    Icon(
                        if (muted) Icons.AutoMirrored.Rounded.VolumeOff else Icons.AutoMirrored.Rounded.VolumeUp,
                        if (muted) "Unmute" else "Mute",
                        Modifier.size(18.dp),
                        tint = Color.White,
                    )
                }
            }
        }
    }
}

/** Sizes the video to cover the slot (like BoxFit.cover), centred and cropped by the parent. */
private fun Modifier.coverLayout(video: VideoSize): Modifier = layout { measurable, constraints ->
    val cw = constraints.maxWidth
    val ch = constraints.maxHeight
    val aspect = if (video.width > 0 && video.height > 0) video.width * video.pixelWidthHeightRatio / video.height else 0f
    val (w, h) = when {
        aspect <= 0f || cw == Constraints.Infinity || ch == Constraints.Infinity -> cw to ch
        cw.toFloat() / ch > aspect -> cw to (cw / aspect).roundToInt()
        else -> (ch * aspect).roundToInt() to ch
    }
    val placeable = measurable.measure(Constraints.fixed(w, h))
    layout(cw, ch) { placeable.place((cw - w) / 2, (ch - h) / 2) }
}
