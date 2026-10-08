package com.bennybar.luli_for_reddit.feature.feed

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Box
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
import androidx.compose.ui.graphics.Color
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
            val active = armed > 0f
            Box(
                Modifier
                    .matchParentSize()
                    .background(spec.color.copy(alpha = if (active) 0.22f else 0.10f), RoundedCornerShape(28.dp))
                    .padding(horizontal = 28.dp),
                contentAlignment = if (dx > 0) AbsoluteAlignment.CenterLeft else AbsoluteAlignment.CenterRight,
            ) {
                Icon(spec.icon, null, tint = spec.color, modifier = Modifier.size(if (active) 30.dp else 24.dp))
            }
        }
        Box(Modifier.absoluteOffset { IntOffset(offset.value.roundToInt(), 0) }) { content() }
    }
}
