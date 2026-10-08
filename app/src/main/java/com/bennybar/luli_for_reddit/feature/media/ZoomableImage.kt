package com.bennybar.luli_for_reddit.feature.media

import androidx.compose.animation.core.animate
import androidx.compose.animation.core.tween
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.calculateCentroid
import androidx.compose.foundation.gestures.calculatePan
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.BrokenImage
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChanged
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import coil3.compose.AsyncImagePainter
import coil3.request.ImageRequest
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * A full-resolution image with pinch / double-tap zoom and pan (the
 * PhotoView behaviour of the Flutter build): min scale = contained, max =
 * 4 × covered. While not zoomed, single-finger drags are left alone so a
 * parent pager can page and the viewer can swipe-to-dismiss; while zoomed,
 * a pan that hits the left/right edge hands the gesture back to the pager.
 */
@Composable
internal fun ZoomableImage(
    url: String,
    onTap: () -> Unit,
    onZoomChanged: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    var scale by remember { mutableFloatStateOf(1f) }
    var offset by remember { mutableStateOf(Offset.Zero) }
    var container by remember { mutableStateOf(IntSize.Zero) }
    var intrinsic by remember { mutableStateOf<Size?>(null) }
    var state by remember { mutableStateOf<AsyncImagePainter.State>(AsyncImagePainter.State.Empty) }
    val scope = rememberCoroutineScope()

    val zoomed = scale > 1.01f
    val onZoom by rememberUpdatedState(onZoomChanged)
    LaunchedEffect(zoomed) { onZoom(zoomed) }

    // The image's on-screen size at scale 1 (fit inside the container).
    fun fitted(): Size {
        val cw = container.width.toFloat()
        val ch = container.height.toFloat()
        val i = intrinsic
        if (i == null || i.width <= 0f || i.height <= 0f || cw <= 0f || ch <= 0f) return Size(cw, ch)
        val f = min(cw / i.width, ch / i.height)
        return Size(i.width * f, i.height * f)
    }

    fun maxScale(): Float {
        val f = fitted()
        if (f.width <= 0f || f.height <= 0f) return 4f
        val covered = max(container.width / f.width, container.height / f.height)
        return max(covered * 4f, 3f)
    }

    fun clamp(o: Offset, s: Float): Offset {
        val f = fitted()
        val mx = max((f.width * s - container.width) / 2f, 0f)
        val my = max((f.height * s - container.height) / 2f, 0f)
        return Offset(o.x.coerceIn(-mx, mx), o.y.coerceIn(-my, my))
    }

    // Offset that keeps the content point under [p] fixed while scaling to [s].
    fun offsetFor(p: Offset, from: Float, to: Float, current: Offset): Offset {
        val c = Offset(container.width / 2f, container.height / 2f)
        return (p - c) - (p - c - current) * (to / from)
    }

    Box(
        modifier
            .fillMaxSize()
            .onSizeChanged { container = it }
            .pointerInput(url) {
                detectTapGestures(
                    onTap = { onTap() },
                    onDoubleTap = { p ->
                        val fromScale = scale
                        val fromOffset = offset
                        val toScale = if (fromScale > 1.01f) 1f else min(2.5f, maxScale())
                        val toOffset = if (toScale == 1f) Offset.Zero else clamp(offsetFor(p, fromScale, toScale, fromOffset), toScale)
                        scope.launch {
                            animate(0f, 1f, animationSpec = tween(220)) { t, _ ->
                                scale = fromScale + (toScale - fromScale) * t
                                offset = fromOffset + (toOffset - fromOffset) * t
                            }
                        }
                    },
                )
            }
            .pointerInput(url) {
                awaitEachGesture {
                    awaitFirstDown(requireUnconsumed = false)
                    do {
                        val event = awaitPointerEvent()
                        if (event.changes.any { it.isConsumed }) break
                        val pressed = event.changes.count { it.pressed }
                        if (pressed >= 2 || scale > 1.01f) {
                            val zoom = event.calculateZoom()
                            val pan = event.calculatePan()
                            val centroid = event.calculateCentroid(useCurrent = true)
                            val newScale = (scale * zoom).coerceIn(1f, maxScale())
                            val raw = (if (centroid.isFiniteOffset()) offsetFor(centroid, scale, newScale, offset) else offset) + pan
                            val clamped = clamp(raw, newScale)
                            // A one-finger horizontal pan pushing past the edge: let the pager page.
                            val atEdge = pressed == 1 && zoom == 1f && abs(pan.x) > abs(pan.y) &&
                                abs(clamped.x - raw.x) > 0.5f
                            scale = newScale
                            offset = clamped
                            if (!atEdge) event.changes.forEach { if (it.positionChanged()) it.consume() }
                        }
                    } while (event.changes.any { it.pressed })
                    if (scale < 1.02f) {
                        scale = 1f
                        offset = Offset.Zero
                    }
                }
            },
        contentAlignment = Alignment.Center,
    ) {
        AsyncImage(
            model = remember(url) { ImageRequest.Builder(context).data(url).size(coil3.size.Size.ORIGINAL).build() },
            contentDescription = null,
            contentScale = ContentScale.Fit,
            onState = { s ->
                state = s
                if (s is AsyncImagePainter.State.Success) intrinsic = s.painter.intrinsicSize
            },
            modifier = Modifier
                .fillMaxSize()
                .graphicsLayer {
                    scaleX = scale
                    scaleY = scale
                    translationX = offset.x
                    translationY = offset.y
                },
        )
        when (state) {
            is AsyncImagePainter.State.Loading, AsyncImagePainter.State.Empty ->
                CircularProgressIndicator(color = Color.White)
            is AsyncImagePainter.State.Error ->
                Icon(Icons.Rounded.BrokenImage, null, Modifier.size(48.dp), tint = Color.White.copy(alpha = 0.6f))
            else -> {}
        }
    }
}

private fun Offset.isFiniteOffset() = x.isFinite() && y.isFinite()
