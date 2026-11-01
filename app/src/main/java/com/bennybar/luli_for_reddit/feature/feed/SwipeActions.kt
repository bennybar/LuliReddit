package com.bennybar.luli_for_reddit.feature.feed

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.absoluteOffset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.AbsoluteAlignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.roundToInt

/** One side of a swipe: what it shows while dragging, and what it does. */
@Stable
class SwipeSpec(val icon: ImageVector, val color: Color, val onTrigger: () -> Unit)

/**
 * The swipe gesture's state machine, free of UI (unit-tested). A drag of
 * [dx] px: rightward is "start" in left-to-right layouts, "end" in RTL. A
 * side with no action doesn't move; releasing past [threshold] fires.
 */
class SwipeTracker(
    private val threshold: Float,
    private val maxDrag: Float,
) {
    var dx = 0f
        private set
    var armed = false // past the threshold (haptic tick + bigger icon)
        private set

    /** Which side a drag of [dx] belongs to. */
    fun sideFor(dx: Float, rtl: Boolean): Side = if ((dx > 0) != rtl) Side.START else Side.END

    /**
     * Applies a drag delta. Returns true when the drag just crossed the
     * threshold outward (the moment to tick).
     */
    fun update(delta: Float, rtl: Boolean, hasStart: Boolean, hasEnd: Boolean): Boolean {
        val next = (dx + delta).coerceIn(-maxDrag, maxDrag)
        // A side with no action doesn't move.
        val side = sideFor(next, rtl)
        if (next != 0f && !(if (side == Side.START) hasStart else hasEnd)) return false
        dx = next
        if (!armed && abs(dx) >= threshold) {
            armed = true
            return true
        } else if (armed && abs(dx) < threshold) {
            armed = false
        }
        return false
    }

    /** Release: the side to fire (if past the threshold), and resets. */
    fun release(rtl: Boolean): Side? {
        val fire = if (abs(dx) >= threshold) sideFor(dx, rtl) else null
        dx = 0f
        armed = false
        return fire
    }

    enum class Side { START, END }
}

/**
 * Wraps [content] with horizontal swipe actions. [start] fires when swiping
 * from the start edge toward the end (rightward in left-to-right languages,
 * leftward in Hebrew/Arabic), [end] the other way. A null side does nothing.
 * Reveals the action's icon as you drag and fires on release past the
 * threshold. Pass [enabled] = false to disable.
 */
@Composable
fun SwipeActions(
    start: SwipeSpec?,
    end: SwipeSpec?,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    content: @Composable () -> Unit,
) {
    if (!enabled || (start == null && end == null)) {
        Box(modifier) { content() }
        return
    }
    val density = LocalDensity.current
    val rtl = LocalLayoutDirection.current == LayoutDirection.Rtl
    val view = rememberView()
    val scope = rememberCoroutineScope()
    val tracker = remember(density) {
        SwipeTracker(threshold = with(density) { 64.dp.toPx() }, maxDrag = with(density) { 110.dp.toPx() })
    }
    // The visible offset: follows the finger, then springs back on release.
    val offset = remember { Animatable(0f) }
    var armed by remember { mutableFloatStateOf(0f) } // 1 = past the threshold
    val startSpec by rememberUpdatedState(start)
    val endSpec by rememberUpdatedState(end)

    Box(
        modifier.pointerInput(rtl) {
            detectHorizontalDragGestures(
                onDragEnd = {
                    val side = tracker.release(rtl)
                    armed = 0f
                    scope.launch { offset.animateTo(0f, tween(160)) }
                    when (side) {
                        SwipeTracker.Side.START -> startSpec?.onTrigger?.invoke()
                        SwipeTracker.Side.END -> endSpec?.onTrigger?.invoke()
                        null -> {}
                    }
                },
                onDragCancel = {
                    tracker.release(rtl)
                    armed = 0f
                    scope.launch { offset.animateTo(0f, tween(160)) }
                },
                onHorizontalDrag = { change, amount ->
                    if (tracker.update(amount, rtl, startSpec != null, endSpec != null)) Haptics.selection(view)
                    armed = if (tracker.armed) 1f else 0f
                    change.consume()
                    scope.launch { offset.snapTo(tracker.dx) }
                },
            )
        },
    ) {
        val dx = offset.value
        val spec = if (dx == 0f) null else if (tracker.sideFor(dx, rtl) == SwipeTracker.Side.START) start else end
        if (spec != null && abs(dx) > with(density) { 2.dp.toPx() }) {
            SwipeBackground(spec.icon, spec.color, abs(dx) / with(density) { 64.dp.toPx() }, armed > 0f, dx > 0)
        }
        Box(Modifier.absoluteOffset { IntOffset(offset.value.roundToInt(), 0) }) { content() }
    }
}

/**
 * What a swipe uncovers behind a row, Gmail style (#48): the action's icon
 * grows as you drag ([progress] 1 = the threshold), and once [active] (past
 * it) the background fills with the action's color and the icon pops.
 * [fromLeft]: dragged rightward, so the icon sits at the left edge.
 */
@Composable
internal fun BoxScope.SwipeBackground(icon: ImageVector, color: Color, progress: Float, active: Boolean, fromLeft: Boolean) {
    val bg by animateColorAsState(if (active) color else color.copy(alpha = 0.14f), tween(150), label = "swipeBg")
    val onColor = if (color.luminance() > 0.5f) Color.Black else Color.White
    val tint by animateColorAsState(if (active) onColor else color, tween(150), label = "swipeTint")
    val pop by animateFloatAsState(
        if (active) 1.2f else 1f,
        spring(Spring.DampingRatioMediumBouncy, Spring.StiffnessMedium),
        label = "swipePop",
    )
    Box(
        Modifier
            .matchParentSize()
            .background(bg, RoundedCornerShape(28.dp))
            .padding(horizontal = 28.dp),
        contentAlignment = if (fromLeft) AbsoluteAlignment.CenterLeft else AbsoluteAlignment.CenterRight,
    ) {
        Icon(icon, null, tint = tint, modifier = Modifier.size(26.dp).scale((0.7f + 0.3f * progress.coerceIn(0f, 1f)) * pop))
    }
}
