package com.bennybar.luli_for_reddit.feature.post

import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animate
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.absoluteOffset
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import com.bennybar.luli_for_reddit.feature.feed.SwipeBackground
import com.bennybar.luli_for_reddit.feature.feed.detectSwipeDrags
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.roundToInt

/** One side of a swipe: what it shows while dragging, and what it does. */
@Immutable
class SwipeSpec(val icon: ImageVector, val color: Color, val onTrigger: () -> Unit)

/**
 * Wraps [content] with horizontal swipe actions. [start] fires when swiping
 * from the start edge toward the end (rightward in left-to-right languages,
 * leftward in Hebrew/Arabic), [end] the other way. A null side does nothing.
 * Reveals the action's pill as you drag and fires on release past the
 * threshold. A [content] with no background of its own (the Calm rows)
 * passes [slideColor]: it's filled with it while dragged, so it slides like a
 * card. One with a margin around its card passes it as [actionInset].
 */
@Composable
fun SwipeActions(
    enabled: Boolean,
    start: SwipeSpec?,
    end: SwipeSpec?,
    modifier: Modifier = Modifier,
    slideColor: Color? = null,
    actionInset: PaddingValues = PaddingValues(0.dp),
    content: @Composable () -> Unit,
) {
    if (!enabled || (start == null && end == null)) {
        Box(modifier) { content() }
        return
    }
    val density = LocalDensity.current
    val threshold = with(density) { 64.dp.toPx() }
    // Far enough for the pill to take real space, with the row still in view.
    val maxDrag = LocalWindowInfo.current.containerSize.width * 0.45f
    val rtl = LocalLayoutDirection.current == LayoutDirection.Rtl
    val haptic = LocalHapticFeedback.current
    val startSpec by rememberUpdatedState(start)
    val endSpec by rememberUpdatedState(end)
    var dx by remember { mutableFloatStateOf(0f) }
    val scope = rememberCoroutineScope()
    var settling by remember { mutableStateOf<Job?>(null) }

    /** Springs the row back into place, the pill closing behind it. */
    fun settle() {
        settling = scope.launch {
            animate(dx, 0f, animationSpec = spring(stiffness = Spring.StiffnessMediumLow)) { v, _ -> dx = v }
        }
    }

    /** The action for a drag of [d]: rightward is "start" in LTR, "end" in RTL. */
    fun specFor(d: Float) = if ((d > 0) != rtl) startSpec else endSpec

    Box(
        modifier.pointerInput(rtl, maxDrag) {
            var fired = false
            detectSwipeDrags(
                onDragStart = { settling?.cancel() },
                onDragEnd = {
                    if (abs(dx) >= threshold) specFor(dx)?.onTrigger?.invoke()
                    settle()
                    fired = false
                },
                onDragCancel = {
                    settle()
                    fired = false
                },
            ) { change, amount ->
                val next = (dx + amount).coerceIn(-maxDrag, maxDrag)
                // A side with no action doesn't move.
                if (specFor(next) == null && next != 0f) return@detectSwipeDrags
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
            SwipeBackground(spec.icon, spec.color, dx, threshold, abs(dx) >= threshold, actionInset)
        }
        Box(
            Modifier
                .absoluteOffset { IntOffset(dx.roundToInt(), 0) }
                .then(if (slideColor != null && dx != 0f) Modifier.background(slideColor) else Modifier),
        ) { content() }
    }
}
