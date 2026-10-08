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
import androidx.compose.material.icons.rounded.Close
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
import androidx.compose.ui.draw.alpha
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

/** Hides the system bars while a viewer is open (swipe from an edge shows them briefly). */
@Composable
internal fun ImmersiveMode() {
    val view = LocalView.current
    DisposableEffect(Unit) {
        val window = view.context.findActivity()?.window ?: return@DisposableEffect onDispose {}
        val controller = WindowCompat.getInsetsController(window, view)
        controller.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        controller.hide(WindowInsetsCompat.Type.systemBars())
        onDispose { controller.show(WindowInsetsCompat.Type.systemBars()) }
    }
}

/** Opens [url] in another app (browser / Reddit / player), not a Custom Tab. */
internal fun openExternally(context: Context, url: String) {
    try {
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
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
            RoundBtn(Icons.Rounded.Close, "Close") { nav.closeViewer() }
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
                    scope.launch { saveMediaToGallery(downloadUrl, downloadIsVideo) }
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
        Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = bgOpacity)))
        Box(
            Modifier
                .fillMaxSize()
                .graphicsLayer { translationY = state.drag }
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
        controls(Modifier.alpha(controlsAlpha), controlsAlpha > 0.01f)
        EdgeBack()
    }
}

/** Full-screen image viewer (zoom, swipe-to-dismiss, save/share). */
@Composable
internal fun ImageViewer(url: String, title: String?) {
    val state = remember { DismissState() }
    DismissableViewer(
        state,
        content = {
            ZoomableImage(
                url,
                onTap = { state.showControls = !state.showControls },
                onZoomChanged = { state.zoomed = it },
            )
        },
        controls = { m, enabled -> ViewerControls(title, url, m, downloadUrl = url, enabled = enabled) },
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
