package com.bennybar.luli_for_reddit.feature.feed

import androidx.compose.animation.core.Spring
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.ui.input.nestedscroll.nestedScroll
import com.bennybar.luli_for_reddit.settings.TopBarMode
import androidx.compose.animation.core.animate
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.Velocity
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.lerp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.settings.HeaderHeight
import kotlinx.coroutines.flow.filter
import kotlin.math.roundToInt

/**
 * The bar's own row, where the title ends up: 48dp, 10dp under the status bar, as the
 * Profile tab's bar (#237: a 64dp row left a deeper margin under the folded title).
 */
private val ROW_TOP = 10.dp
private val ROW = 48.dp
private val BAR = ROW_TOP + ROW
/**
 * The room the big title takes under it, at the top of the list, the title 10dp off its
 * foot (#226), per Settings › Header height (#240). Medium is 2.0.103's (#232); Tall
 * 2.0.96's whole height; Folded none: the title starts, and stays, in the bar.
 */
private fun extraFor(h: HeaderHeight): Dp = when (h) {
    HeaderHeight.FOLDED -> 0.dp
    HeaderHeight.MEDIUM -> 66.dp
    HeaderHeight.TALL -> 94.dp
}
private const val SMALL = 22f / 32f // the title's size in the bar, against its big size

/**
 * Settings › Appearance › Top bar › Expandable (#214, #182): a big title under the bar's
 * buttons at the top of the list, which shrinks and slides into the bar as the list
 * scrolls, and grows back once it's at the top again. Put `nestedScroll(state)` on what
 * holds the list, outside a [HidingBar] if the bar should also slide away once folded
 * (#226), and give the list the bar's height as its top padding. Scrolling up takes the
 * header first; down, only with the list at its top ([atTop]), so it comes back there
 * and not mid-list.
 */
@Stable
class CollapsingTitle(private val atTop: () -> Boolean) : NestedScrollConnection {
    /** 0 at the top, 1 folded into the bar. */
    var progress by mutableFloatStateOf(0f)
        internal set
    internal var rangePx = 1f
    internal var extra by mutableStateOf(extraFor(HeaderHeight.MEDIUM))

    /** How far it's folded as drawn: always folded when there's no room to open into. */
    internal val shown: Float get() = if (extra == 0.dp) 1f else progress

    /** The bar's height now, between [BAR] + [extra] and [BAR]. */
    val height: Dp get() = BAR + extra * (1f - shown)

    override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
        val y = available.y
        if (rangePx <= 0f) return Offset.Zero // Folded: nothing to fold
        // A pull to refresh's indicator goes back first (#235).
        if (y < 0f && com.bennybar.luli_for_reddit.ui.PullToRefreshActivity.pulling) return Offset.Zero
        val now = progress * rangePx
        val next = when {
            y < 0f -> (now - y).coerceAtMost(rangePx)
            y > 0f && now > 0f && atTop() -> (now - y).coerceAtLeast(0f)
            else -> return Offset.Zero
        }
        progress = next / rangePx
        return Offset(0f, now - next)
    }

    /**
     * When a finger last moved the list (or a fling did). The list reaching its top right
     * after one isn't "brought there without a finger": the header then opens as the
     * finger pulls, not all at once (#242).
     */
    internal var scrolledAt = 0L

    override fun onPostScroll(consumed: Offset, available: Offset, source: NestedScrollSource): Offset {
        scrolledAt = System.currentTimeMillis()
        return Offset.Zero
    }

    /**
     * A fling that reaches the top opens the header with what's left of it, at its speed,
     * as Sync's (#249): the list stops at its top, so the header got none of it and
     * waited for a second pull. A finger still opens it only as far as it moves (#242).
     */
    override suspend fun onPostFling(consumed: Velocity, available: Velocity): Velocity {
        // A real fling only: a finger that stopped at the top leaves it where it is.
        if (available.y > 300f && progress > 0f && rangePx > 0f && atTop()) {
            animate(progress, 0f, initialVelocity = -available.y / rangePx, animationSpec = spring(stiffness = Spring.StiffnessMediumLow)) { v, _ ->
                progress = v.coerceIn(0f, 1f)
            }
            return available
        }
        return Velocity.Zero
    }

    internal suspend fun expand() {
        animate(progress, 0f) { v, _ -> progress = v }
    }
}

/**
 * [atTop]: the list is at its very top (any list: a re-tap on the tab brings it there).
 * How far it's folded is saved with the screen: Back from a post rebuilds the tab, and
 * the header opened out again over a feed still scrolled down (#233).
 */
@Composable
fun rememberCollapsingTitle(extra: Dp? = null, atTop: () -> Boolean): CollapsingTitle {
    val latest by rememberUpdatedState(atTop)
    val state = rememberSaveable(
        saver = Saver<CollapsingTitle, Float>(save = { it.progress }, restore = { p -> CollapsingTitle { latest() }.also { it.progress = p } }),
    ) { CollapsingTitle { latest() } }
    // [extra]: a header of its own height (a subreddit's banner, #257), not the setting's.
    val room = extra ?: extraFor(app.settings.state.collectAsStateWithLifecycle().value.headerHeight)
    state.extra = room
    state.rangePx = with(LocalDensity.current) { room.toPx() }
    // Brought to the top without a finger (a re-tap, Back, a reload): open with it.
    LaunchedEffect(state) {
        snapshotFlow { latest() }.filter { it }.collect {
            if (state.progress > 0f && System.currentTimeMillis() - state.scrolledAt > 400) state.expand()
        }
    }
    return state
}

/**
 * A page's big header (#247): Saved, History, Profile and the like get the tabs' big title
 * with Settings › Top bar › Expandable, folding as [listState] scrolls; null with the Full
 * bar. Hand it to [BloomTopBar] and put [collapsingHeader] on what holds the list.
 */
@Composable
fun rememberPageHeader(listState: LazyListState): CollapsingTitle? {
    val expandable = app.settings.state.collectAsStateWithLifecycle().value.topBarMode == TopBarMode.EXPANDABLE
    val header = rememberCollapsingTitle { listState.firstVisibleItemIndex == 0 && listState.firstVisibleItemScrollOffset == 0 }
    return header.takeIf { expandable }
}

/** Lets [header] (if any) fold with the scroll under it: outside the list's [HidingBar]. */
fun Modifier.collapsingHeader(header: CollapsingTitle?): Modifier = if (header == null) this else nestedScroll(header)

/**
 * The bar: [navigation] (the ☰) and [actions] in its row, the [title] (and [subtitle],
 * which fades as it folds) moving from under them into the row, scaled rather than
 * re-laid out each frame. Draws its own background, the status bar's included unless
 * [underStatusBar] is false (a screen already placed below it).
 */
@Composable
fun CollapsingTitleBar(
    state: CollapsingTitle,
    title: String,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    hasNavigation: Boolean,
    underStatusBar: Boolean = true,
    navigation: @Composable () -> Unit = {},
    actions: @Composable RowScope.() -> Unit,
) {
    val cs = MaterialTheme.colorScheme
    val p = state.shown
    Box(modifier.fillMaxWidth().background(cs.surface).then(if (underStatusBar) Modifier.statusBarsPadding() else Modifier).height(state.height)) {
        Row(Modifier.fillMaxWidth().padding(top = ROW_TOP).height(ROW).padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            navigation()
            Spacer(Modifier.weight(1f))
            actions()
        }
        val density = LocalDensity.current
        // Big: at the foot of the header, as Sync's and Android's large bars (#226), its
        // letters lined up with the chips' edge under it (#243: at 20dp it sat 8dp to the
        // right). Small: centred in the row, after the ☰ (#231: it sat 2dp high).
        val x = lerp(12.dp, if (hasNavigation) 60.dp else 20.dp, p)
        val y = lerp(BAR + state.extra - 40.dp - (if (subtitle != null) 20.dp else 0.dp) - 10.dp, ROW_TOP + (ROW - 40.dp * SMALL) / 2, p)
        val scale = 1f + (SMALL - 1f) * p
        Column(
            Modifier
                .offset { with(density) { IntOffset(x.roundToPx(), y.roundToPx()) } }
                .graphicsLayer { scaleX = scale; scaleY = scale; transformOrigin = TransformOrigin(0f, 0f) }
                // Clear of the row's buttons once small (the scale shrinks this too).
                .widthIn(max = lerp(360.dp, 260.dp / SMALL, p)),
        ) {
            Text(
                title,
                style = MaterialTheme.typography.headlineLarge,
                fontSize = 32.sp,
                lineHeight = 40.sp,
                fontWeight = FontWeight.ExtraBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            if (subtitle != null) {
                Text(
                    subtitle,
                    Modifier.graphicsLayer { alpha = (1f - p * 2f).coerceAtLeast(0f) },
                    style = MaterialTheme.typography.bodyMedium,
                    color = cs.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}
