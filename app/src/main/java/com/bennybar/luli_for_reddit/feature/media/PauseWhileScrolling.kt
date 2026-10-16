package com.bennybar.luli_for_reddit.feature.media

import android.graphics.drawable.Animatable
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.platform.LocalContext
import coil3.asDrawable
import coil3.compose.AsyncImagePainter

/** Whether the list around this content is scrolling right now (animated images pause meanwhile). */
val LocalListScrolling = staticCompositionLocalOf<() -> Boolean> { { false } }

/**
 * An `onSuccess` for AsyncImage: an animated image (GIF, animated WebP)
 * stops on its current frame while the surrounding list scrolls, and plays
 * again when it stops. Android animates these on the render thread on their
 * own ~15 fps clock, out of step with the scroll, which made the phone drop
 * about one frame in six in a thread with GIFs.
 */
@Composable
fun rememberPauseWhileScrolling(): (AsyncImagePainter.State.Success) -> Unit {
    val scrolling = LocalListScrolling.current
    val resources = LocalContext.current.resources
    var animated by remember { mutableStateOf<Animatable?>(null) }
    LaunchedEffect(animated) {
        val a = animated ?: return@LaunchedEffect
        snapshotFlow { scrolling() }.collect { moving ->
            if (moving) a.stop() else if (!a.isRunning) a.start()
        }
    }
    return remember(resources) { { s -> animated = s.result.image.asDrawable(resources) as? Animatable } }
}
