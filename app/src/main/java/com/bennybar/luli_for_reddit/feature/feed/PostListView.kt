package com.bennybar.luli_for_reddit.feature.feed

import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.foundation.gestures.scrollBy
import androidx.compose.foundation.BorderStroke
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.derivedStateOf
import androidx.compose.foundation.layout.offset
import androidx.compose.ui.unit.Dp
import com.bennybar.luli_for_reddit.ui.RefreshBox
import com.bennybar.luli_for_reddit.ui.Loading
import com.bennybar.luli_for_reddit.core.timeAgoPhrase
import androidx.compose.material3.TextButton
import androidx.compose.material.icons.rounded.CloudOff
import androidx.compose.material.icons.rounded.History
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.background
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.expandHorizontally
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkHorizontally
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.layout.LazyLayoutCacheWindow
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.Sort
import androidx.compose.material.icons.automirrored.rounded.TrendingUp
import androidx.compose.material.icons.rounded.ArrowUpward
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Leaderboard
import androidx.compose.material.icons.rounded.LocalFireDepartment
import androidx.compose.material.icons.rounded.Schedule
import androidx.compose.material.icons.rounded.Star
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil3.SingletonImageLoader
import coil3.request.ImageRequest
import coil3.size.Dimension
import coil3.size.Size
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.core.net.RedditApiException
import com.bennybar.luli_for_reddit.data.PostSort
import com.bennybar.luli_for_reddit.data.TopTime
import com.bennybar.luli_for_reddit.feature.foryou.DealIn
import com.bennybar.luli_for_reddit.feature.foryou.HomeLoadingDeck
import com.bennybar.luli_for_reddit.feature.foryou.HomeStatus
import com.bennybar.luli_for_reddit.nav.LocalNavigator
import com.bennybar.luli_for_reddit.nav.Route
import com.bennybar.luli_for_reddit.settings.PostDisplay
import com.bennybar.luli_for_reddit.settings.postsTabKey
import com.bennybar.luli_for_reddit.ui.ErrorView
import com.bennybar.luli_for_reddit.ui.Overlays
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filterNotNull
import com.bennybar.luli_for_reddit.model.Post
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.Job
import kotlin.math.roundToInt
import androidx.compose.ui.draw.drawBehind
import androidx.compose.animation.core.animate
import androidx.compose.animation.core.tween
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.unit.Velocity

/** The [FeedController] for [feedKey], re-fetched after an account switch. */
@Composable
fun rememberFeedController(feedKey: String): FeedController {
    val version by app.feed.version.collectAsState()
    // Started right here (not in an effect) so the cached page can paint a frame sooner.
    return remember(feedKey, version) { app.feed.controller(feedKey).also { it.start() } }
}

/**
 * Builds cards about a screen ahead (Flutter's 1200px cache extent; the
 * default is one item), so they're laid out and their images decoding before
 * they appear.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun rememberFeedListState(): LazyListState =
    rememberLazyListState(cacheWindow = remember { LazyLayoutCacheWindow(ahead = 440.dp, behind = 440.dp) })

/**
 * Scrollable list of posts for a feed key ('' = frontpage, subreddit name,
 * or `m::user::name`). [header] is rendered as the first scrolling item
 * (e.g. a big title).
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun PostListView(
    feedKey: String,
    modifier: Modifier = Modifier,
    header: (@Composable () -> Unit)? = null,
    topPadding: Dp = 0.dp, // room for a top bar floating over the list
    listState: LazyListState = rememberFeedListState(),
    /**
     * Past the chips in the list, a second row of them floats here (#73): where
     * it goes, given its height, so it moves with the top bar and leaves with it.
     */
    floatingChipsY: ((Int) -> Int)? = null,
    /** Bumped to go to the top and refresh, with the spinner (the Refresh floating button, #90). */
    refreshRequests: Int = 0,
    /** Hosted by the Posts tab: its re-tap and Back signals, and Home's hidden subreddits, apply. */
    postsTab: Boolean = false,
    /** Bumped to take the posts you've read off the list, with Undo (the Hide read posts floating button, #99). */
    hideReadRequests: Int = 0,
) {
    val controller = rememberFeedController(feedKey)
    val ui by controller.ui.collectAsStateWithLifecycle()
    val settings by app.settings.state.collectAsStateWithLifecycle()
    val nav = LocalNavigator.current
    val view = rememberView()
    val scope = rememberCoroutineScope()
    val listPadding = remember(topPadding) { PaddingValues(start = 7.dp, top = topPadding, end = 7.dp, bottom = 130.dp) }
    var refreshing by remember { mutableStateOf(false) }
    val isFrontpage = feedKey.isEmpty()
    // With the Posts tab on r/all (Settings) the frontpage is a pushed page: plain, no For You / Blend / Home.
    val engines = isFrontpage && !settings.postsTabAll
    val homeMode = engines && settings.redditHomeAllowed && settings.redditHomeFeed
    // Home and For You load behind the shuffling deck.
    val deckMode = engines && (homeMode || settings.forYouFeed)
    // The loading deck was just showing: deal the first cards in.
    var dealHome by remember { mutableStateOf(false) }
    val chipsState = rememberLazyListState()
    val floatingChipsState = rememberLazyListState()
    val chipsIn: @Composable (LazyListState, Float) -> Unit = { state, outline ->
        FeedChips(
            outline = outline,
            sort = controller.sort,
            time = controller.time,
            state = state,
            onPick = { s, t -> controller.changeSort(s, t) },
            isFrontpage = engines,
            forYou = settings.forYouFeed && engines,
            onForYou = controller::selectForYou,
            redditHome = homeMode,
            onRedditHome = if (settings.redditHomeAllowed) controller::selectRedditHome else null,
            blend = settings.forYouFeed && settings.blendHome && settings.redditHomeAllowed && engines,
            onBlend = if (settings.redditHomeAllowed) controller::selectBlend else null,
        )
    }
    // Under a fixed top bar (subreddits, custom feeds, #86) the floating row
    // follows the finger on its own, as Home's does with its bar: out as you
    // scroll down, back in as you scroll up. Home passes its own place for it.
    val ownFloat = floatingChipsY == null && !postsTab && settings.floatingChips
    var rowHeight by remember { mutableIntStateOf(0) }
    var chipsShift by remember { mutableFloatStateOf(0f) } // 0 = shown, -rowHeight = hidden
    var chipsSettling by remember { mutableStateOf<Job?>(null) }
    var chipsUp by remember { mutableStateOf(false) }
    val chipsScroll = remember {
        object : NestedScrollConnection {
            override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
                if (source == NestedScrollSource.UserInput) chipsSettling?.cancel()
                return Offset.Zero
            }

            override fun onPostScroll(consumed: Offset, available: Offset, source: NestedScrollSource): Offset {
                chipsShift = (chipsShift + consumed.y).coerceIn(-rowHeight.toFloat(), 0f)
                if (consumed.y != 0f) chipsUp = consumed.y > 0f
                return Offset.Zero
            }

            override suspend fun onPostFling(consumed: Velocity, available: Velocity): Velocity {
                // Don't rest half way: it finishes the way you were going.
                val to = if (chipsUp) 0f else -rowHeight.toFloat()
                if (chipsShift != to) {
                    chipsSettling?.cancel()
                    chipsSettling = scope.launch { animate(chipsShift, to, animationSpec = tween(200)) { v, _ -> chipsShift = v } }
                }
                return Velocity.Zero
            }
        }
    }
    val chipsAt: ((Int) -> Int)? = floatingChipsY ?: if (ownFloat) ({ _: Int -> chipsShift.roundToInt() }) else null
    // Floating: from the moment the list's row leaves its place until it's back
    // in it, the row on show is the floating one, so it looks like one row (#80).
    val floating = chipsAt != null
    val chipsY by rememberUpdatedState(chipsAt)
    // How far the list's row is past the floating one's spot, measured from where
    // that spot is now: the top bar moves, and a fixed line (the list's top
    // padding) swapped them with the row still below the bar, in Full mode
    // under its title, so the chips jumped up over it (#89). Null: not in view.
    val rowPast by remember(listState) {
        derivedStateOf {
            val info = listState.layoutInfo
            val row = info.visibleItemsInfo.firstOrNull { it.key == "sortbar" } ?: return@derivedStateOf null
            val rowY = row.offset - info.viewportStartOffset
            (chipsY?.invoke(row.size) ?: info.beforeContentPadding) - rowY
        }
    }
    val past by remember(listState) {
        derivedStateOf { rowPast?.let { it > 0 } ?: (listState.layoutInfo.totalItemsCount > 0) }
    }
    // Fades in as it leaves the list's row, so it isn't there the moment they swap.
    val floatingOutline by remember(listState) {
        derivedStateOf {
            val row = listState.layoutInfo.visibleItemsInfo.firstOrNull { it.key == "sortbar" }
            val by = rowPast
            if (row == null || row.size == 0 || by == null) 1f else (by.toFloat() / row.size).coerceIn(0f, 1f)
        }
    }
    val isData = ui is FeedUi.Data
    LaunchedEffect(past, floating) {
        if (!floating) return@LaunchedEffect
        val (from, to) = if (past) chipsState to floatingChipsState else floatingChipsState to chipsState
        to.scrollToItem(from.firstVisibleItemIndex, from.firstVisibleItemScrollOffset)
    }
    val chips: @Composable () -> Unit = {
        Box(
            Modifier
                .onSizeChanged { rowHeight = it.height }
                .graphicsLayer { alpha = if (floating && isData && past) 0f else 1f },
        ) { chipsIn(chipsState, 0f) }
    }

    fun refresh(haptic: Boolean = true) {
        if (refreshing) return
        if (haptic) Haptics.medium(view)
        scope.launch {
            refreshing = true
            try {
                controller.refresh()
            } finally {
                refreshing = false
            }
        }
    }

    LaunchedEffect(refreshRequests) {
        if (refreshRequests == 0 || controller.ui.value !is FeedUi.Data) return@LaunchedEffect
        listState.scrollToItem(0)
        refresh()
    }

    LaunchedEffect(hideReadRequests) {
        if (hideReadRequests == 0) return@LaunchedEffect
        val before = controller.hideRead()
        if (before == null) {
            nav.showSnackbar("No read posts here")
            return@LaunchedEffect
        }
        val hidden = before.count { it.id in app.history.ids.value }
        nav.showSnackbar("Hid $hidden read post${if (hidden == 1) "" else "s"}", actionLabel = "Undo") { controller.unhideRead(before) }
    }

    // Returning to the feed after a pushed route (e.g. a post) is popped, or
    // to the app: the frontpage keeps its posts for 30 minutes, then loads
    // anew; other feeds stage fresh posts behind a "New posts" pill once
    // stale. (The first resume is this screen opening.)
    var resumedOnce by rememberSaveable { mutableStateOf(false) }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) {
        when {
            !resumedOnce -> {
                resumedOnce = true
                if (!isFrontpage) controller.reloadIfOld()
            }
            isFrontpage -> controller.refreshIfExpired()
            else -> controller.refreshIfStale()
        }
    }

    // A sort / feed change replaces the list: start the new one at the top.
    val isLoading = ui is FeedUi.Loading
    LaunchedEffect(isLoading) { if (isLoading) listState.scrollToItem(0) }

    if (postsTab) {
        // Posts tab only: respond to the "tap active tab" signal — scroll to
        // top, or refresh (with a visible spinner) when already there.
        // Keyed on the controller too: an account switch swaps it, and the
        // re-tap refresh must hit the current one.
        LaunchedEffect(listState, controller) {
            app.feed.frontpageScrollSignal.drop(1).collect {
                // No list yet (loading / error): ignore, as Flutter (whose
                // scroll controller is only attached to the loaded list).
                if (controller.ui.value !is FeedUi.Data) return@collect
                if (listState.firstVisibleItemIndex > 0 || listState.firstVisibleItemScrollOffset > 20) {
                    listState.animateScrollToItem(0)
                } else {
                    Haptics.medium(view)
                    refresh(haptic = false)
                }
            }
        }
        // Back on the Posts tab (Settings → Back scrolls Posts to top).
        LaunchedEffect(listState) {
            app.feed.frontpageBackSignal.drop(1).collect { listState.animateScrollToItem(0) }
        }
    }
    // Home (and Blend's Home posts): follow the card on screen in the hidden
    // reddit.com page, so Reddit's own "seen" tracking matches what was
    // actually read and the next load brings new posts. (Cards not on its
    // page are ignored there.)
    val blendMode = engines && settings.forYouFeed && settings.blendHome && settings.redditHomeAllowed
    if (homeMode || blendMode) LaunchedEffect(listState) {
        snapshotFlow {
            listState.layoutInfo.visibleItemsInfo.firstOrNull { (it.contentType as? String)?.startsWith("post_") == true }?.key as? String
        }.distinctUntilChanged().collect { id -> if (id != null) app.forYou.redditHome.viewing(id) }
    }

    Box(modifier.fillMaxSize().then(if (ownFloat) Modifier.nestedScroll(chipsScroll) else Modifier)) {
        RefreshBox(
            isRefreshing = refreshing,
            onRefresh = { refresh() },
            modifier = Modifier.fillMaxSize(),
            indicatorPadding = topPadding,
        ) {
            when (val u = ui) {
                FeedUi.Loading -> {
                    // Home (no saved page to show yet): the shuffling deck with a
                    // live count of posts found; its cards are then dealt in.
                    if (deckMode) SideEffect { dealHome = true }
                    LazyColumn(Modifier.fillMaxSize(), contentPadding = listPadding, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        if (header != null) item(key = "header", contentType = "header") { header() }
                        item(key = "sortbar", contentType = "sortbar") { chips() }
                        if (deckMode) {
                            item(key = "deck") {
                                Column {
                                    Spacer(Modifier.height(58.dp))
                                    HomeLoadingDeck(forYou = !homeMode)
                                }
                            }
                        } else {
                            items(5, key = { "sk$it" }, contentType = { "skeleton" }) {
                                PostSkeleton()
                            }
                        }
                    }
                }
                is FeedUi.Error -> LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(top = topPadding)) {
                    if (header != null) item(key = "header", contentType = "header") { header() }
                    item(key = "error") {
                        // A quarantined or gated subreddit: opt in right here.
                        val reason = (u.error as? RedditApiException)?.reason
                        val canOptIn by produceState(false, reason) { value = app.repository.canOptIn(reason) }
                        if (canOptIn && !feedKey.startsWith("m::")) {
                            ErrorView(u.error, Modifier.height(360.dp), retryLabel = "View anyway", onRetry = {
                                scope.launch {
                                    try {
                                        app.repository.optInSubreddit(feedKey, reason!!)
                                        controller.retry()
                                    } catch (e: Exception) {
                                        nav.showActionError("opt in", e)
                                    }
                                }
                            })
                        } else {
                            ErrorView(u.error, Modifier.height(360.dp), onRetry = controller::retry)
                        }
                    }
                }
                is FeedUi.Data -> FeedList(
                    postsTab = postsTab,
                    feedKey = feedKey,
                    state = u.state,
                    controller = controller,
                    listState = listState,
                    header = header,
                    homeMode = homeMode,
                    deckMode = deckMode,
                    dealHome = dealHome,
                    onDealt = { dealHome = false },
                    chips = chips,
                    chipsHeight = { if (settings.floatingChips) rowHeight else 0 },
                    listPadding = listPadding,
                    onRetry = { refresh() },
                )
            }
        }
        if (chipsAt != null && isData && past) {
            var height by remember { mutableIntStateOf(0) }
            val barColor = MaterialTheme.colorScheme.surface
            Box(
                Modifier
                    .fillMaxWidth()
                    .onSizeChanged { height = it.height }
                    .offset { IntOffset(0, chipsAt(height)) }
                    // The top bar's own surface, so posts don't show between the chips;
                    // it fades in with the outline, so the swap with the list's row doesn't show.
                    // Transparent (#91): just the outlined chips over the posts, as before 2.0.58.
                    .then(if (settings.floatingChipsSolid) Modifier.drawBehind { drawRect(barColor, alpha = floatingOutline) } else Modifier)
                    // The list's own side padding, so it's right over the list's row (#83).
                    .padding(horizontal = 7.dp),
                // On the solid background the chips need no outline to stand out (#132).
            ) { chipsIn(floatingChipsState, if (settings.floatingChipsSolid) 0f else floatingOutline) }
        }
        val pending = (ui as? FeedUi.Data)?.state?.hasPending == true
        if (pending) {
            NewPostsPill(
                Modifier.align(Alignment.TopCenter).padding(top = 8.dp + topPadding),
                onClick = {
                    controller.applyPending()
                    scope.launch { listState.animateScrollToItem(0) }
                },
            )
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun FeedList(
    feedKey: String,
    postsTab: Boolean,
    state: FeedState,
    controller: FeedController,
    listState: LazyListState,
    header: (@Composable () -> Unit)?,
    homeMode: Boolean,
    deckMode: Boolean,
    dealHome: Boolean,
    onDealt: () -> Unit,
    chips: @Composable () -> Unit,
    /** The floating chips' height when they can float over the list (0 otherwise), in px. */
    chipsHeight: () -> Int,
    listPadding: PaddingValues,
    onRetry: () -> Unit,
) {
    val homeStatus = if (homeMode) app.forYou.redditHome.status.collectAsStateWithLifecycle().value else null
    val dismissible = feedKey.isEmpty() && deckMode
    // Home's hidden subreddits apply on the front page, and on the Posts tab when it shows r/all.
    val frontpage = feedKey.isEmpty() || postsTab
    val posts = rememberShownPosts(feedKey, state.posts)
    val hidden = state.posts.size - posts.size

    // Paging is triggered by reaching rows near the end. If the filters hide
    // (almost) everything loaded, there are no rows to reach and the list
    // can't scroll, so the feed stalled blank. Keep fetching instead, up to a
    // bound in case nothing ever matches.
    LaunchedEffect(posts.size, state.hasMore, state.loadingMore, state.posts.size) {
        if (posts.size < 10 && state.hasMore && !state.loadingMore && state.posts.size < 250) controller.loadMore()
    }

    // Page early, 10 cards from the end (a fast flick covers several cards in
    // less time than a page takes to arrive), and warm the image cache for
    // the cards just below the screen — same URL and decode size as the card.
    val context = LocalContext.current
    val decodeWidth = feedDecodeWidth()
    val prefetched = remember { HashSet<String>() }
    val latestPosts by rememberUpdatedState(posts)
    val headerCount = if (header != null) 2 else 1 // header + sort bar
    // Back from Browse media (#103): the post it was on comes to the top.
    val firstPostRow by rememberUpdatedState(headerCount + if (homeStatus is HomeStatus.Saved || homeStatus is HomeStatus.FellBack) 1 else 0)
    LaunchedEffect(controller) {
        controller.browsedTo.filterNotNull().collect { id ->
            controller.browsedTo.value = null
            val i = latestPosts.indexOfFirst { it.id == id }
            if (i >= 0) {
                listState.scrollToItem(firstPostRow + i)
                // The top of the list sits under the floating chips: bring the card down
                // by the row's height, so its header stays visible (#107).
                val below = chipsHeight()
                if (below > 0) listState.scrollBy(-below.toFloat())
            }
        }
    }
    // 10 posts from the end = 11 rows counting the footer.
    LoadMoreNearEnd(listState, fromEnd = 11, page = state.posts.size to state.after, onLoadMore = controller::loadMore)
    LaunchedEffect(listState) {
        snapshotFlow { listState.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0 }
            .distinctUntilChanged()
            .collect { last ->
                val ps = latestPosts
                val postIndex = last - headerCount
                // Mini cards only show small thumbnails; not worth warming.
                val s = app.settings.value
                if (s.postDisplay == PostDisplay.MINI) return@collect
                val loader = SingletonImageLoader.get(context)
                for (p in ps.drop((postIndex + 1).coerceAtLeast(0)).take(8)) {
                    val url = feedImageUrl(p, s) ?: continue
                    if (!prefetched.add(url)) continue
                    loader.enqueue(
                        ImageRequest.Builder(context).data(url)
                            .size(Size(Dimension(decodeWidth), Dimension.Undefined)).build(),
                    )
                }
            }
    }

    LazyColumn(
        Modifier.fillMaxSize(),
        state = listState,
        contentPadding = listPadding,
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        if (header != null) item(key = "header", contentType = "header") { header() }
        item(key = "sortbar", contentType = "sortbar") { chips() }
        // Not your live Home: say what this is instead (until the next load works).
        if (homeStatus is HomeStatus.Saved || homeStatus is HomeStatus.FellBack) {
            item(key = "homestatus", contentType = "homestatus") { HomeStatusStrip(homeStatus, onRetry) }
        }
        items(posts.size, key = { posts[it].id }, contentType = { "post_${posts[it].type}" }) { i ->
            val p = posts[i]
            if (deckMode && i < 3) {
                // The first cards after the loading deck are dealt in.
                if (i == 2) LaunchedEffect(Unit) { onDealt() }
                DealIn(i, animate = dealHome) { CompositionLocalProvider(LocalDismissible provides dismissible, LocalFrontpage provides frontpage) { PostCard(p) } }
            } else {
                CompositionLocalProvider(LocalDismissible provides dismissible, LocalFrontpage provides frontpage) { PostCard(p) }
            }
        }
        item(key = "footer", contentType = "footer") {
            val muted = MaterialTheme.colorScheme.onSurfaceVariant
            Column(Modifier.fillMaxWidth().padding(vertical = 24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                when {
                    state.loadingMore -> Loading()
                    state.hasMore -> {}
                    else -> Text("— end —", color = muted)
                }
                if (hidden > 0) {
                    Text(
                        "$hidden ${if (hidden == 1) "post" else "posts"} hidden",
                        Modifier.padding(top = 8.dp),
                        color = muted,
                        fontSize = 12.5.sp,
                    )
                }
            }
        }
    }
}

/**
 * [posts] as the feed list shows them: without posts hidden or dismissed,
 * subreddits hidden from the front page, content filters (Hide NSFW
 * included) and, in For You, read posts when auto-hidden. Browse media
 * (#103) shows the same posts.
 */
@Composable
internal fun rememberShownPosts(feedKey: String, posts: List<Post>): List<Post> {
    val settings by app.settings.state.collectAsStateWithLifecycle()
    val isFrontpage = feedKey.isEmpty()
    // With the Posts tab on r/all (Settings) the frontpage is a plain page: no For You / Home.
    val engines = isFrontpage && !settings.postsTabAll
    val homeMode = engines && settings.redditHomeAllowed && settings.redditHomeFeed
    val deckMode = engines && (homeMode || settings.forYouFeed)
    val hiddenIds by app.hiddenPosts.ids.collectAsStateWithLifecycle()
    // Home / For You: posts dismissed with the "Dismiss" swipe (kept a day).
    val dismissedIds = if (isFrontpage && deckMode) app.dismissedPosts.ids.collectAsStateWithLifecycle().value else emptySet()
    // Subreddits hidden for 7 days: anywhere on the front page (Home, For You
    // and Best / Hot / New), and in the feed the Posts tab shows when it's r/all.
    val homeFeed = isFrontpage || feedKey == settings.postsTabKey
    val hiddenSubs = if (homeFeed) app.hiddenHomeSubs.ids.collectAsStateWithLifecycle().value else emptySet()
    val filters by app.contentFilters.state.collectAsStateWithLifecycle()
    // Auto-hide already-read items in the For You feed (live: updates when
    // history changes). Only watched while the option is on. Not in Reddit
    // Home: its recommended posts carry Reddit's reason too, and opening one
    // made it vanish on return.
    val seen: Set<String>? = if (settings.autoHideReadForYou && !homeMode) app.history.ids.collectAsStateWithLifecycle().value else null
    // A subreddit feed still shows that subreddit's own posts.
    val viewing = if (feedKey.isEmpty() || feedKey.startsWith("m::")) null else feedKey

    return remember(posts, seen, hiddenIds, dismissedIds, hiddenSubs, filters, viewing) {
        var list = posts
        if (seen != null) list = list.filter { !(it.feedReason != null && it.id in seen) }
        // Posts hidden this session (Hide / swipe-to-hide).
        if (hiddenIds.isNotEmpty()) list = list.filter { it.id !in hiddenIds }
        if (dismissedIds.isNotEmpty()) list = list.filter { it.id !in dismissedIds }
        if (hiddenSubs.isNotEmpty()) list = list.filter { it.subreddit.lowercase() !in hiddenSubs }
        // User content filters (keywords / domains / flairs / subreddits).
        if (!filters.isEmpty) list = list.filter { !filters.hides(it, viewingSubreddit = viewing) }
        // A page boundary can repeat a post that moved up meanwhile; the list
        // needs unique keys.
        list.distinctBy { it.id }
    }
}

/**
 * Tappable pill shown when a fresh feed page is staged after returning to a
 * stale feed — applies it and scrolls to top.
 */
@Composable
private fun NewPostsPill(modifier: Modifier, onClick: () -> Unit) {
    val cs = MaterialTheme.colorScheme
    Surface(modifier, shape = CircleShape, color = cs.primary, shadowElevation = 3.dp) {
        Row(
            Modifier.clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Rounded.ArrowUpward, null, Modifier.size(16.dp), tint = cs.onPrimary)
            Spacer(Modifier.width(6.dp))
            Text("New posts", color = cs.onPrimary, fontWeight = FontWeight.Bold)
        }
    }
}

private fun iconFor(s: PostSort): ImageVector = when (s) {
    PostSort.BEST -> Icons.Rounded.Star
    PostSort.HOT -> Icons.Rounded.LocalFireDepartment
    PostSort.NEWEST -> Icons.Rounded.Schedule
    PostSort.TOP -> Icons.Rounded.Leaderboard
    PostSort.RISING -> Icons.AutoMirrored.Rounded.TrendingUp
}

/** The profile's sort: a button that opens the list (no room beside its tabs for [FeedChips]). */
@Composable
fun SortBar(
    sort: PostSort,
    time: TopTime,
    onPick: (PostSort, TopTime?) -> Unit,
    sorts: List<PostSort>,
) {
    val scope = rememberCoroutineScope()
    Row(Modifier.padding(horizontal = 6.dp, vertical = 8.dp)) {
        AssistChip(
            onClick = { scope.launch { showSortSheet(sort, time, onPick, sorts) } },
            label = { Text(if (sort.needsTime) "${sort.label} · ${time.label}" else sort.label) },
            leadingIcon = { Icon(Icons.AutoMirrored.Rounded.Sort, null, Modifier.size(18.dp)) },
            shape = CircleShape,
            border = null,
            colors = AssistChipDefaults.assistChipColors(containerColor = MaterialTheme.colorScheme.surfaceContainerHigh),
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
private suspend fun showSortSheet(sort: PostSort, time: TopTime, onPick: (PostSort, TopTime?) -> Unit, sorts: List<PostSort>) {
    val pick = Overlays.show<PostSort> { done ->
        ModalBottomSheet(onDismissRequest = { done(null) }) {
            TapGuard {
                Column(Modifier.navigationBarsPadding()) {
                    for (s in sorts) {
                        SheetTile(iconFor(s), s.label, null, checked = s == sort) { done(s) }
                    }
                }
            }
        }
    } ?: return
    if (pick.needsTime) {
        onPick(pick, pickTopTime(time) ?: return)
    } else {
        onPick(pick, null)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
internal suspend fun pickTopTime(time: TopTime): TopTime? = Overlays.show<TopTime> { done ->
    ModalBottomSheet(onDismissRequest = { done(null) }) {
        TapGuard {
            Column(Modifier.navigationBarsPadding()) {
                for (t in TopTime.entries) SheetTile(null, t.label, null, checked = t == time) { done(t) }
            }
        }
    }
}

private sealed interface FeedChoice {
    data object ForYou : FeedChoice
    data object Blend : FeedChoice
    data object Home : FeedChoice
    data class Sort(val sort: PostSort) : FeedChoice
}

/**
 * A feed's sorts, and on the frontpage its For You / Blend / Home feeds, as
 * Material 3 Expressive filter chips (#53): one tap, and the tapped chip
 * morphs into a pill with a check. Top asks for its time range first. Picking
 * swaps the list for its loading state, which rebuilds this row, so the pick
 * shows for a moment before it's applied, or the morph would never be seen.
 */
@Composable
private fun FeedChips(
    outline: Float, // how much of an outline the chips have, 0 to 1
    sort: PostSort,
    time: TopTime,
    state: LazyListState,
    onPick: (PostSort, TopTime?) -> Unit,
    isFrontpage: Boolean,
    forYou: Boolean,
    onForYou: () -> Unit,
    redditHome: Boolean,
    onRedditHome: (() -> Unit)?, // null unless enabled in Settings
    blend: Boolean,
    onBlend: (() -> Unit)?, // null unless Reddit Home is enabled
) {
    val scope = rememberCoroutineScope()
    val current = when {
        redditHome -> FeedChoice.Home
        blend -> FeedChoice.Blend
        forYou -> FeedChoice.ForYou
        else -> FeedChoice.Sort(sort)
    }
    var picked by remember { mutableStateOf<FeedChoice?>(null) }
    var pickedTime by remember { mutableStateOf<TopTime?>(null) }

    fun choose(choice: FeedChoice, topTime: TopTime? = null, action: () -> Unit) {
        picked = choice
        pickedTime = topTime
        scope.launch {
            delay(240)
            action()
            picked = null
            pickedTime = null
        }
    }

    val shown = picked ?: current
    val chips = buildList {
        if (isFrontpage) {
            add(FeedChoice.ForYou)
            if (onBlend != null) add(FeedChoice.Blend)
            if (onRedditHome != null) add(FeedChoice.Home)
        }
        addAll(PostSort.entries.map { FeedChoice.Sort(it) })
    }
    // Keep the selected chip in view: Home's row can start with it off screen.
    LaunchedEffect(current) {
        val i = chips.indexOf(current)
        val info = state.layoutInfo
        val seen = info.visibleItemsInfo.find { it.index == i }
        if (seen == null || seen.offset < 0 || seen.offset + seen.size > info.viewportEndOffset) {
            state.animateScrollToItem((i - 1).coerceAtLeast(0))
        }
    }
    LazyRow(
        Modifier.fillMaxWidth().padding(vertical = 8.dp),
        state = state,
        contentPadding = PaddingValues(horizontal = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        items(chips, key = { it.toString() }) { chip ->
            val label = when (chip) {
                FeedChoice.ForYou -> "For You"
                FeedChoice.Blend -> "Blend · Beta"
                FeedChoice.Home -> "Home"
                is FeedChoice.Sort ->
                    if (chip.sort.needsTime && chip == shown) "${chip.sort.label} · ${(pickedTime ?: time).label}" else chip.sort.label
            }
            FeedChip(label, chip == shown, outline) {
                if (picked != null) return@FeedChip
                when (chip) {
                    FeedChoice.ForYou -> if (chip != current) choose(chip, action = onForYou)
                    FeedChoice.Blend -> if (chip != current) choose(chip) { onBlend?.invoke() }
                    FeedChoice.Home -> if (chip != current) choose(chip) { onRedditHome?.invoke() }
                    is FeedChoice.Sort -> if (chip.sort.needsTime) {
                        scope.launch {
                            val t = pickTopTime(time) ?: return@launch
                            if (chip != current || t != time) choose(chip, t) { onPick(chip.sort, t) }
                        }
                    } else if (chip != current) {
                        choose(chip) { onPick(chip.sort, null) }
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
internal fun FeedChip(label: String, selected: Boolean, outline: Float = 0f, onClick: () -> Unit) {
    val cs = MaterialTheme.colorScheme
    val corner by animateDpAsState(if (selected) 18.dp else 8.dp, MaterialTheme.motionScheme.fastSpatialSpec(), label = "chipCorner")
    // The tick sits inside the label, so it starts from the label's padding:
    // pull it out toward the chip's edge, where a chip's leading icon belongs (#57).
    val pull by animateDpAsState(if (selected) 8.dp else 0.dp, MaterialTheme.motionScheme.fastSpatialSpec(), label = "chipTick")
    FilterChip(
        selected = selected,
        onClick = onClick,
        label = {
            Row(
                Modifier.layout { measurable, constraints ->
                    val p = measurable.measure(constraints)
                    val px = pull.roundToPx()
                    layout(p.width - px, p.height) { p.place(-px, 0) }
                },
                verticalAlignment = Alignment.CenterVertically,
            ) {
                AnimatedVisibility(
                    selected,
                    enter = expandHorizontally(MaterialTheme.motionScheme.fastSpatialSpec()) + fadeIn(),
                    exit = shrinkHorizontally(MaterialTheme.motionScheme.fastSpatialSpec()) + fadeOut(),
                ) {
                    Row {
                        Icon(Icons.Rounded.Check, null, Modifier.size(18.dp))
                        Spacer(Modifier.width(8.dp))
                    }
                }
                Text(label)
            }
        },
        modifier = Modifier.height(36.dp),
        shape = RoundedCornerShape(corner),
        border = if (outline > 0f) BorderStroke(1.dp, cs.outlineVariant.copy(alpha = outline)) else null,
        colors = FilterChipDefaults.filterChipColors(
            containerColor = cs.surfaceContainerHigh,
            labelColor = cs.onSurface,
            selectedContainerColor = cs.secondaryContainer,
            selectedLabelColor = cs.onSecondaryContainer,
        ),
    )
}

/** A bottom-sheet row: icon, title (+ subtitle), trailing check when selected. */
@Composable
fun SheetTile(icon: ImageVector?, title: String, subtitle: String?, checked: Boolean = false, onClick: () -> Unit) {
    Tile(
        title = { Text(title) },
        subtitle = subtitle?.let { { Text(it) } },
        leading = icon?.let { { Icon(it, null) } },
        trailing = if (checked) ({ Icon(Icons.Rounded.Check, "Selected") }) else null,
                onClick = onClick,
    )
}

/** "Saved Home from 2h ago · Refresh" / "Home couldn't load · showing For You · Retry". */
@Composable
private fun HomeStatusStrip(status: HomeStatus, onRetry: () -> Unit) {
    val cs = MaterialTheme.colorScheme
    val nav = LocalNavigator.current
    val (icon, text) = when (status) {
        is HomeStatus.Saved -> Icons.Rounded.History to "Saved Home, from ${timeAgoPhrase(status.at)}"
        is HomeStatus.FellBack -> Icons.Rounded.CloudOff to
            if (status.signedOut) "Website sign-in expired · showing For You" else "Home couldn't load · showing For You"
        is HomeStatus.Live -> return
    }
    val signIn = status is HomeStatus.FellBack && status.signedOut
    Row(
        Modifier
            .padding(horizontal = 4.dp)
            .fillMaxWidth()
            .background(cs.secondaryContainer, RoundedCornerShape(18.dp))
            .padding(start = 14.dp, end = 4.dp, top = 2.dp, bottom = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, null, Modifier.size(18.dp), tint = cs.onSecondaryContainer)
        Spacer(Modifier.width(10.dp))
        Text(text, Modifier.weight(1f), fontSize = 13.sp, color = cs.onSecondaryContainer, maxLines = 2)
        TextButton(onClick = { if (signIn) nav.push(Route.WebLogin()) else onRetry() }) {
            Text(if (signIn) "Sign in" else if (status is HomeStatus.Saved) "Refresh" else "Retry")
        }
    }
}
