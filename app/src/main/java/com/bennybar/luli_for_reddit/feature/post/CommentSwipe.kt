package com.bennybar.luli_for_reddit.feature.post

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.AbsoluteAlignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import kotlin.math.abs
import kotlin.math.roundToInt

/** One side of a swipe: what it shows while dragging, and what it does. */
@Immutable
class SwipeSpec(val icon: ImageVector, val color: Color, val onTrigger: () -> Unit)

/**
 * Wraps [content] with horizontal swipe actions. [start] fires when swiping
 * from the start edge toward the end (rightward in left-to-right languages,
 * leftward in Hebrew/Arabic), [end] the other way. A null side does nothing.
 * Reveals the action's icon as you drag and fires on release past the
 * threshold.
 */
@Composable
fun SwipeActions(
    enabled: Boolean,
    start: SwipeSpec?,
    end: SwipeSpec?,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    if (!enabled || (start == null && end == null)) {
        Box(modifier) { content() }
        return
    }
    val density = LocalDensity.current
    val threshold = with(density) { 64.dp.toPx() }
    val maxDrag = with(density) { 110.dp.toPx() }
    val rtl = LocalLayoutDirection.current == LayoutDirection.Rtl
    val haptic = LocalHapticFeedback.current
    val startSpec by rememberUpdatedState(start)
    val endSpec by rememberUpdatedState(end)
    var dx by remember { mutableFloatStateOf(0f) }

    /** The action for a drag of [d]: rightward is "start" in LTR, "end" in RTL. */
    fun specFor(d: Float) = if ((d > 0) != rtl) startSpec else endSpec

    Box(
        modifier.pointerInput(rtl) {
            var fired = false
            detectHorizontalDragGestures(
                onDragEnd = {
                    if (abs(dx) >= threshold) specFor(dx)?.onTrigger?.invoke()
                    dx = 0f
                    fired = false
                },
                onDragCancel = {
                    dx = 0f
                    fired = false
                },
            ) { change, amount ->
                val next = (dx + amount).coerceIn(-maxDrag, maxDrag)
                // A side with no action doesn't move.
                if (specFor(next) == null && next != 0f) return@detectHorizontalDragGestures
                change.consume()
                dx = next
                if (!fired && abs(dx) >= threshold) {
                    fired = true
                    haptic.performHapticFeedback(HapticFeedbackType.SegmentTick)
                } else if (fired && abs(dx) < threshold) {
                    fired = false
                }
            }
        },
    ) {
        val spec = if (dx == 0f) null else specFor(dx)
        if (spec != null && abs(dx) > 2f) {
            val active = abs(dx) >= threshold
            Box(
                Modifier
                    .matchParentSize()
                    .clip(RoundedCornerShape(28.dp))
                    .background(spec.color.copy(alpha = if (active) 0.22f else 0.10f))
                    .padding(horizontal = 28.dp),
                contentAlignment = if (dx > 0) AbsoluteAlignment.CenterLeft else AbsoluteAlignment.CenterRight,
            ) {
                Icon(spec.icon, null, tint = spec.color, modifier = Modifier.size(if (active) 30.dp else 24.dp))
            }
        }
        Box(Modifier.offset { IntOffset(dx.roundToInt(), 0) }) { content() }
    }
}
