package com.bennybar.luli_for_reddit.feature.feed

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.horizontalDrag
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.absoluteOffset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.shape.CircleShape
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.PointerInputChange
import androidx.compose.ui.input.pointer.PointerInputScope
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.LocalWindowInfo
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
 * Whether a drag of ([dx], [dy]) px, as it leaves the touch slop, is a swipe
 * (#82): only a clearly sideways one, within ~27° of horizontal (ViewPager's
 * 2:1 rule). A thumb's scroll arcs diagonally; claiming the row at the first
 * sideways slop (anything up to 45°) turned those scrolls into swipes, and
 * the list never got them back.
 */
fun isSwipeDrag(dx: Float, dy: Float): Boolean = abs(dx) > 2 * abs(dy)

/**
 * A swipe row's horizontal drag (posts, comments, inbox): like
 * detectHorizontalDragGestures, but past the slop it takes the gesture only
 * when [isSwipeDrag] and [claims] its x distance; otherwise it lets go,
 * unconsumed, and the list scrolls (or the Inbox pages, #113).
 * [onDrag] gets x deltas, the first one what's past the slop.
 */
internal suspend fun PointerInputScope.detectSwipeDrags(
    claims: (dx: Float) -> Boolean = { true },
    onDragStart: () -> Unit = {},
    onDragEnd: () -> Unit,
    onDragCancel: () -> Unit,
    onDrag: (PointerInputChange, Float) -> Unit,
) = awaitEachGesture {
    val down = awaitFirstDown(requireUnconsumed = false)
    val slop = viewConfiguration.touchSlop
    var total = Offset.Zero
    var change: PointerInputChange
    do {
        change = awaitPointerEvent().changes.firstOrNull { it.id == down.id } ?: return@awaitEachGesture
        // Lifted (a tap), or taken by something inside the row.
        if (!change.pressed || change.isConsumed) return@awaitEachGesture
        total += change.positionChange()
    } while (total.getDistance() < slop)
    if (!isSwipeDrag(total.x, total.y) || !claims(total.x)) return@awaitEachGesture
    change.consume()
    onDragStart()
    onDrag(change, total.x * (1 - slop / total.getDistance()))
    val ended = horizontalDrag(change.id) { onDrag(it, it.positionChange().x) }
    if (ended) onDragEnd() else onDragCancel()
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
    val threshold = with(density) { 64.dp.toPx() }
    // Far enough for the pill to take real space, with the row still in view.
    val maxDrag = LocalWindowInfo.current.containerSize.width * 0.45f
    val tracker = remember(threshold, maxDrag) { SwipeTracker(threshold = threshold, maxDrag = maxDrag) }
    // The visible offset: follows the finger, then springs back on release.
    val offset = remember { Animatable(0f) }
    var armed by remember { mutableFloatStateOf(0f) } // 1 = past the threshold
    val startSpec by rememberUpdatedState(start)
    val endSpec by rememberUpdatedState(end)

    Box(
        modifier.pointerInput(rtl, tracker) {
            detectSwipeDrags(
                // A side with no action leaves the drag alone: taking it froze
                // the row and kept the Inbox from paging past it (#113).
                claims = { dx -> if (tracker.sideFor(dx, rtl) == SwipeTracker.Side.START) startSpec != null else endSpec != null },
                onDragEnd = {
                    val side = tracker.release(rtl)
                    armed = 0f
                    scope.launch { offset.animateTo(0f, spring(stiffness = Spring.StiffnessMediumLow)) }
                    when (side) {
                        SwipeTracker.Side.START -> startSpec?.onTrigger?.invoke()
                        SwipeTracker.Side.END -> endSpec?.onTrigger?.invoke()
                        null -> {}
                    }
                },
                onDragCancel = {
                    tracker.release(rtl)
                    armed = 0f
                    scope.launch { offset.animateTo(0f, spring(stiffness = Spring.StiffnessMediumLow)) }
                },
                onDrag = { change, amount ->
                    if (tracker.update(amount, rtl, startSpec != null, endSpec != null)) Haptics.selection(view)
                    armed = if (tracker.armed) 1f else 0f
                    change.consume()
                    // The value now, not when the launch runs: a quick flick's last
                    // move and the lift can arrive together, and release() zeroes
                    // tracker.dx first, which jumped the card home with no spring (#137).
                    val to = tracker.dx
                    scope.launch { offset.snapTo(to) }
                },
            )
        },
    ) {
        val dx = offset.value
        val spec = if (dx == 0f) null else if (tracker.sideFor(dx, rtl) == SwipeTracker.Side.START) start else end
        if (spec != null && abs(dx) > with(density) { 2.dp.toPx() }) {
            SwipeBackground(spec.icon, spec.color, dx, threshold, armed > 0f)
        }
        Box(Modifier.absoluteOffset { IntOffset(offset.value.roundToInt(), 0) }) { content() }
    }
}

/**
 * What a swipe uncovers beside a row, Gmail style (#52): a solid pill of the
 * action's color fills the space the row leaves ([dx], a small gap apart), so
 * it reads as a second card taking the row's place. Its icon grows up to
 * [threshold] and pops once [active] (past it). [inset]: the row's own margin
 * around its card, so the pill lines up with the card.
 */
@Composable
internal fun BoxScope.SwipeBackground(
    icon: ImageVector,
    color: Color,
    dx: Float,
    threshold: Float,
    active: Boolean,
    inset: PaddingValues = PaddingValues(0.dp),
) {
    val pop by animateFloatAsState(
        if (active) 1.2f else 1f,
        spring(Spring.DampingRatioMediumBouncy, Spring.StiffnessMedium),
        label = "swipePop",
    )
    val grow = 0.7f + 0.3f * (abs(dx) / threshold).coerceIn(0f, 1f)
    val width = with(LocalDensity.current) { abs(dx).toDp() } - 6.dp
    Box(Modifier.matchParentSize().padding(inset)) {
        Box(
            Modifier
                .align(if (dx > 0) AbsoluteAlignment.CenterLeft else AbsoluteAlignment.CenterRight)
                .fillMaxHeight()
                .width(width.coerceAtLeast(0.dp))
                .clip(CircleShape)
                .background(color),
            contentAlignment = Alignment.Center,
        ) {
            // Keeps its size in a thin pill, which clips it until there's room.
            Icon(
                icon,
                null,
                tint = if (color.luminance() > 0.5f) Color.Black else Color.White,
                modifier = Modifier.wrapContentSize(unbounded = true).size(26.dp).scale(grow * pop),
            )
        }
    }
}
