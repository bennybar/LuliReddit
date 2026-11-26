package com.bennybar.luli_for_reddit.feature.media

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.net.Uri
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.OpenInNew
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material.icons.rounded.IosShare
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.util.lerp
import coil3.memory.MemoryCache
import kotlin.math.min
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.bennybar.luli_for_reddit.nav.LocalNavigator
import com.bennybar.luli_for_reddit.nav.MediaViewer
import kotlinx.coroutines.launch
import kotlin.math.abs

internal tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}

/**
 * Hides the status bar while a viewer is open (a swipe from the top shows it briefly).
 * Not the navigation bar (#189): hidden, the first edge swipe only brought it back, so
 * leaving took two Back gestures; its handle is slim, and the viewer draws under it.
 */
@Composable
internal fun ImmersiveMode() {
    val view = LocalView.current
    DisposableEffect(Unit) {
        val window = view.context.findActivity()?.window ?: return@DisposableEffect onDispose {}
        val controller = WindowCompat.getInsetsController(window, view)
        controller.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        controller.hide(WindowInsetsCompat.Type.statusBars())
        onDispose { controller.show(WindowInsetsCompat.Type.statusBars()) }
    }
}

/** Opens [url] in another app (browser / Reddit / player), not a Custom Tab. */
internal fun openExternally(context: Context, url: String) {
    try {
        context.startActivity(com.bennybar.luli_for_reddit.core.externalViewIntent(context, Uri.parse(url)))
    } catch (_: ActivityNotFoundException) {
        com.bennybar.luli_for_reddit.app.navigatorOrNull?.showSnackbar("No app can open this link.")
    }
}

/**
 * A left-edge swipe-to-go-back strip (iOS-style), safe to overlay on viewers
 * without stealing zoom pan / gallery paging (only the left 26dp).
 */
@Composable
internal fun BoxScope.EdgeBack() {
    val nav = LocalNavigator.current
    // The fling threshold is 80dp/s (Flutter's velocities are logical pixels).
    val minVelocity = with(LocalDensity.current) { 80.dp.toPx() }
    Box(
        Modifier
            .align(Alignment.CenterStart)
            .width(26.dp)
            .fillMaxHeight()
            .draggable(
                orientation = Orientation.Horizontal,
                state = rememberDraggableState {},
                onDragStopped = { v -> if (v > minVelocity) nav.closeViewer() },
            ),
    )
}

/**
 * A community's or user's round picture that opens full screen on a tap (#279), growing
 * out of where it is (#287).
 */
@Composable
fun Modifier.opensPicture(url: String, name: String): Modifier {
    val nav = LocalNavigator.current
    // Where it is now, without recomposing as it moves (the collapsing header's icon).
    val at = remember { arrayOfNulls<Rect>(1) }
    return onGloballyPositioned { at[0] = it.boundsInRoot() }
        .clip(CircleShape)
        .clickable(onClickLabel = "Open picture") { nav.openPicture(url, name, at[0]) }
}

/** A white glyph with a soft shadow over the top scrim (always legible over media). */
@Composable
internal fun RoundBtn(icon: ImageVector, description: String, onTap: () -> Unit) {
    Box(
        Modifier
            .size(44.dp)
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, onClick = onTap),
        contentAlignment = Alignment.Center,
    ) {
        // Shadow under the glyph: the same icon, offset and darkened.
        Icon(icon, null, Modifier.size(26.dp).graphicsLayer { translationY = 1.5f }, tint = Color.Black.copy(alpha = 0.45f))
        Icon(icon, description, Modifier.size(26.dp), tint = Color.White)
    }
}

/** Floating translucent controls (close + download + share + open) over a scrim. */
@Composable
internal fun ViewerControls(
    title: String?,
    sourceUrl: String?,
    modifier: Modifier = Modifier,
    center: String? = null,
    downloadUrl: String? = null,
    downloadIsVideo: Boolean = false,
    enabled: Boolean = true,
) {
    val nav = LocalNavigator.current
    val scope = rememberCoroutineScope()
    Box(
        modifier
            .fillMaxWidth()
            .height(120.dp)
            .background(Brush.verticalGradient(listOf(Color(0x99000000), Color(0x00000000)))),
    ) {
        Row(
            // Immersive mode hides the status bar, but keep clear of a camera cutout.
            Modifier
                .windowInsetsPadding(
                    WindowInsets.statusBars.union(WindowInsets.displayCutout)
                        .only(WindowInsetsSides.Top + WindowInsetsSides.Horizontal),
                )
                .padding(horizontal = 8.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (!enabled) return@Row
            // Back, not ×: it goes back to where it was opened (#287).
            RoundBtn(Icons.AutoMirrored.Rounded.ArrowBack, "Back") { nav.closeViewer() }
            Spacer(Modifier.width(4.dp))
            Text(
                center ?: title ?: "",
                modifier = Modifier.weight(1f),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                style = TextStyle(
                    color = Color.White,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                    shadow = Shadow(Color.Black.copy(alpha = 0.5f), blurRadius = 6f),
                ),
            )
            if (downloadUrl != null) {
                RoundBtn(Icons.Rounded.Download, "Download") {
                    scope.launch { saveMediaToGallery(downloadUrl, downloadIsVideo, title) }
                }
                Spacer(Modifier.width(4.dp))
            }
            if (sourceUrl != null) {
                RoundBtn(Icons.Rounded.IosShare, "Share") { nav.share(sourceUrl) }
                Spacer(Modifier.width(4.dp))
                RoundBtn(Icons.AutoMirrored.Rounded.OpenInNew, "Open in browser") {
                    openExternally(nav.context, sourceUrl)
                }
            }
        }
    }
}

/** Swipe-down-to-dismiss with a background fade, shared by the image and gallery viewers. */
private class DismissState {
    var drag by mutableFloatStateOf(0f)
    var zoomed by mutableStateOf(false)
    var showControls by mutableStateOf(true)
}

@Composable
private fun DismissableViewer(
    state: DismissState,
    content: @Composable BoxScope.() -> Unit,
    controls: @Composable (Modifier, Boolean) -> Unit,
    // How far in a picture that grows out of its circle is (#287): the black and the
    // controls come with it, and a swipe's drag goes back to the circle on close.
    progress: () -> Float = { 1f },
) {
    val nav = LocalNavigator.current
    val density = LocalDensity.current
    val fadePx = with(density) { 500.dp.toPx() }
    val dismissPx = with(density) { 130.dp.toPx() }
    val flingPx = with(density) { 800.dp.toPx() }
    ImmersiveMode()
    val bgOpacity = (1f - abs(state.drag) / fadePx).coerceIn(0f, 1f)
    val controlsVisible = state.showControls && abs(state.drag) < 8f
    val controlsAlpha by animateFloatAsState(if (controlsVisible) 1f else 0f, tween(150), label = "controls")
    Box(Modifier.fillMaxSize()) {
        Box(Modifier.fillMaxSize().graphicsLayer { alpha = progress() }.background(Color.Black.copy(alpha = bgOpacity)))
        Box(
            Modifier
                .fillMaxSize()
                .graphicsLayer { translationY = state.drag * progress() }
                .draggable(
                    orientation = Orientation.Vertical,
                    enabled = !state.zoomed,
                    state = rememberDraggableState { d -> state.drag += d },
                    onDragStopped = { v ->
                        if (abs(state.drag) > dismissPx || abs(v) > flingPx) nav.closeViewer() else state.drag = 0f
                    },
                ),
            content = content,
        )
        controls(Modifier.graphicsLayer { alpha = controlsAlpha * progress() }, controlsAlpha > 0.01f)
        EdgeBack()
    }
}

/**
 * Full-screen image viewer (zoom, swipe-to-dismiss, save/share). A picture opened from its
 * circle ([MediaViewer.Image.from]) grows out of it as [progress] goes 0 → 1, like
 * WhatsApp's (#287): round and at the circle's place and size at 0, fitted on black at 1.
 */
@Composable
internal fun ImageViewer(v: MediaViewer.Image, progress: () -> Float = { 1f }) {
    val state = remember { DismissState() }
    val from = v.from.takeIf { it.size == 4 }?.let { Rect(it[0], it[1], it[0] + it[2], it[1] + it[3]) }
    var origin by remember { mutableStateOf<Offset?>(null) }
    DismissableViewer(
        state,
        content = {
            ZoomableImage(
                v.url,
                onTap = { state.showControls = !state.showControls },
                onZoomChanged = { state.zoomed = it },
                // The circle's own copy, until the full picture is in.
                placeholderKey = v.thumb?.let { MemoryCache.Key(it, mapOf("still" to "1")) },
                modifier = if (from == null) Modifier else Modifier
                    .onGloballyPositioned { if (origin == null) origin = it.positionInRoot() }
                    .graphicsLayer {
                        val p = progress()
                        val o = origin ?: return@graphicsLayer
                        if (p >= 1f) return@graphicsLayer
                        // The picture is taken as square, fitted: d × d in the middle.
                        val w = size.width
                        val h = size.height
                        val d = min(w, h)
                        val k = lerp(from.width / d, 1f, p)
                        scaleX = k
                        scaleY = k
                        translationX = (from.center.x - o.x - w / 2) * (1 - p)
                        translationY = (from.center.y - o.y - h / 2) * (1 - p)
                        // A circle opening up into the whole picture.
                        val cw = lerp(d, w, p)
                        val ch = lerp(d, h, p)
                        val r = d / 2 * (1 - p)
                        shape = object : Shape {
                            override fun createOutline(size: Size, layoutDirection: LayoutDirection, density: Density) =
                                Outline.Rounded(RoundRect(Rect(Offset((w - cw) / 2, (h - ch) / 2), Size(cw, ch)), CornerRadius(r)))
                        }
                        clip = true
                    },
            )
        },
        controls = { m, enabled -> ViewerControls(v.title, v.url, m, downloadUrl = v.url, enabled = enabled) },
        progress = progress,
    )
}

/** Full-screen gallery viewer: pager + "i / n" counter. */
@Composable
internal fun GalleryViewer(route: MediaViewer.Gallery) {
    val urls = route.urls
    if (urls.isEmpty()) return
    val state = remember { DismissState() }
    val pager = rememberPagerState(initialPage = route.initialIndex.coerceIn(0, urls.size - 1)) { urls.size }
    LaunchedEffect(pager.currentPage) { state.zoomed = false }
    DismissableViewer(
        state,
        content = {
            HorizontalPager(pager, Modifier.fillMaxSize(), beyondViewportPageCount = 1, key = { it }) { i ->
                ZoomableImage(
                    urls[i],
                    onTap = { state.showControls = !state.showControls },
                    onZoomChanged = { if (i == pager.currentPage) state.zoomed = it },
                )
            }
        },
        controls = { m, enabled ->
            val i = pager.currentPage
            ViewerControls(
                route.title,
                urls[i],
                m,
                center = "${i + 1} / ${urls.size}",
                downloadUrl = urls[i],
                enabled = enabled,
            )
        },
    )
}
