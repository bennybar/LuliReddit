package com.bennybar.luli_for_reddit.feature.feed

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.MutableTransitionState
import androidx.compose.animation.core.animate
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.Velocity
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bennybar.luli_for_reddit.ui.Overlays
import kotlin.math.roundToInt
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

/**
 * A top bar that floats over a feed and follows the finger, in and out (#55):
 * it slides away as you scroll down and back as you scroll up, and the feed
 * stays put under it instead of being pushed around. Home's, and a
 * subreddit's and a custom feed's (#112). Put `nestedScroll(bar)` on the box
 * holding the feed and [HidingTopBar], and give the feed the bar's [height] as
 * its top padding.
 */
@Stable
class HidingBar(private val listState: LazyListState, private val scope: CoroutineScope) : NestedScrollConnection {
    var height by mutableIntStateOf(0)
    var shift by mutableFloatStateOf(0f) // 0 = shown, -height = hidden
    private var settling: Job? = null
    private var scrollingUp = false

    fun slide(to: Float) {
        settling?.cancel()
        settling = scope.launch { animate(shift, to, animationSpec = tween(200)) { v, _ -> shift = v } }
    }

    override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
        if (source == NestedScrollSource.UserInput) settling?.cancel()
        return Offset.Zero
    }

    override fun onPostScroll(consumed: Offset, available: Offset, source: NestedScrollSource): Offset {
        shift = (shift + consumed.y).coerceIn(-height.toFloat(), 0f)
        if (consumed.y != 0f) scrollingUp = consumed.y > 0f
        return Offset.Zero
    }

    override suspend fun onPostFling(consumed: Velocity, available: Velocity): Velocity {
        // Don't rest half way; hide only with the feed scrolled far
        // enough to fill the space the bar leaves.
        val past = listState.firstVisibleItemIndex > 0 || listState.firstVisibleItemScrollOffset >= height
        if (shift != 0f && shift != -height.toFloat()) {
            // It finishes the way you were going: a little scroll up brings it out.
            slide(if (past && !scrollingUp) -height.toFloat() else 0f)
        }
        return Velocity.Zero
    }

    /** The floating chips' place (#73): right under the bar when it's fully out, off the top when it's gone. */
    fun chipsY(chipsHeight: Int): Int =
        if (height == 0) -chipsHeight else (height + shift / height * (height + chipsHeight)).roundToInt()
}

@Composable
fun rememberHidingBar(listState: LazyListState): HidingBar {
    val scope = rememberCoroutineScope()
    val bar = remember(listState) { HidingBar(listState, scope) }
    // Never hidden past the feed's top, however it got there (a re-tap on the
    // tab, Back, new posts): there'd be a blank gap above the first card.
    LaunchedEffect(bar) {
        snapshotFlow { if (listState.firstVisibleItemIndex == 0) listState.firstVisibleItemScrollOffset else null }
            .collect { top -> if (top != null) bar.shift = maxOf(bar.shift, -top.toFloat()) }
    }
    return bar
}

/**
 * [bar]'s top bar, drawn over the feed (call it after the feed in their box).
 * With the bar away the feed runs under the status bar, softly faded so its
 * icons stay readable (#74, #80). The bar covers it when it's out.
 */
@Composable
fun HidingTopBar(bar: HidingBar, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    val cs = MaterialTheme.colorScheme
    val fade = cs.surface
    Box(
        Modifier
            .fillMaxWidth()
            .height(WindowInsets.statusBars.asPaddingValues().calculateTopPadding() + 16.dp)
            .background(Brush.verticalGradient(listOf(fade.copy(alpha = 0.7f), fade.copy(alpha = 0f)))),
    )
    Box(
        Modifier
            .fillMaxWidth()
            .onSizeChanged { bar.height = it.height }
            .offset { IntOffset(0, bar.shift.roundToInt()) }
            .background(cs.surface)
            .then(modifier),
    ) { content() }
}

/**
 * Floats a panel in from the top as a dismissible overlay over the dimmed
 * screen, like the Expandable top bar's menu: it never displaces the feed.
 * [panel] gets `close`, which slides it away and then runs what it's given.
 */
fun showTopPanel(panel: @Composable (close: (then: () -> Unit) -> Unit) -> Unit) {
    Overlays.launch { done ->
        val visible = remember { MutableTransitionState(false).apply { targetState = true } }
        var after by remember { mutableStateOf<(() -> Unit)?>(null) }
        fun close(then: (() -> Unit)? = null) {
            after = then
            visible.targetState = false
        }
        // Finish closing once the exit animation has run.
        LaunchedEffect(visible.currentState, visible.targetState) {
            if (!visible.targetState && !visible.currentState && visible.isIdle) {
                done()
                after?.invoke()
            }
        }
        BackHandler { close() }
        Box(Modifier.fillMaxSize()) {
            AnimatedVisibility(visible, enter = fadeIn(tween(200)), exit = fadeOut(tween(200))) {
                Box(
                    Modifier
                        .fillMaxSize()
                        .background(Color.Black.copy(alpha = 0.30f))
                        .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { close() },
                )
            }
            AnimatedVisibility(
                visible,
                Modifier.statusBarsPadding().padding(start = 12.dp, top = 8.dp, end = 12.dp),
                enter = fadeIn(tween(200)) + slideInVertically(tween(200)) { -it / 6 },
                exit = fadeOut(tween(200)) + slideOutVertically(tween(200)) { -it / 6 },
            ) { panel { then -> close(then) } }
        }
    }
}

/** A button in a [showTopPanel] menu; [half]: a short one, which shares its row with the next short one (#152). */
class MenuAction(val icon: ImageVector, val label: String, val half: Boolean = false, val onClick: () -> Unit)

/**
 * A top bar's ⋯ menu (#112): its [actions] in the Expandable top bar's panel,
 * one a row (two short ones side by side), connected segments 3dp apart.
 */
fun showBarMenu(actions: List<MenuAction>) = showTopPanel { close ->
    val rows = mutableListOf<MutableList<MenuAction>>()
    for (a in actions) {
        val last = rows.lastOrNull()
        if (a.half && last != null && last.size == 1 && last[0].half) last += a else rows += mutableListOf(a)
    }
    Surface(shape = RoundedCornerShape(32.dp), color = MaterialTheme.colorScheme.surfaceContainer, shadowElevation = 8.dp) {
        Column(Modifier.padding(8.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            rows.forEachIndexed { r, row ->
                // The first and last rows round off the panel's outer corners.
                val top = if (r == 0) PanelOuter else PanelInner
                val bottom = if (r == rows.lastIndex) PanelOuter else PanelInner
                Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                    row.forEachIndexed { j, a ->
                        val shape = RoundedCornerShape(
                            topStart = if (j == 0) top else PanelInner,
                            topEnd = if (j == row.lastIndex) top else PanelInner,
                            bottomStart = if (j == 0) bottom else PanelInner,
                            bottomEnd = if (j == row.lastIndex) bottom else PanelInner,
                        )
                        PanelButton(a.icon, a.label, Modifier.weight(1f), { close(a.onClick) }, shape)
                    }
                }
            }
        }
    }
}

val PanelOuter = 26.dp
val PanelInner = 6.dp

@Composable
fun PanelButton(
    icon: ImageVector,
    label: String,
    modifier: Modifier,
    onClick: () -> Unit,
    shape: Shape = RoundedCornerShape(PanelInner),
) {
    val cs = MaterialTheme.colorScheme
    Row(
        modifier
            .height(56.dp)
            .clip(shape)
            .background(cs.surfaceContainerHigh)
            .clickable(onClick = onClick),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, null, Modifier.size(20.dp), tint = cs.onSurface)
        Spacer(Modifier.width(10.dp))
        Text(label, fontSize = 15.sp, fontWeight = FontWeight.Medium)
    }
}
