package com.bennybar.luli_for_reddit.feature.feed

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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.layout.LazyLayoutCacheWindow
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.Sort
import androidx.compose.material.icons.automirrored.rounded.TrendingUp
import androidx.compose.material.icons.rounded.ArrowUpward
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Home
import androidx.compose.material.icons.rounded.Leaderboard
import androidx.compose.material.icons.rounded.LocalFireDepartment
import androidx.compose.material.icons.rounded.Schedule
import androidx.compose.material.icons.rounded.Star
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
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
import com.bennybar.luli_for_reddit.data.PostSort
import com.bennybar.luli_for_reddit.data.TopTime
import com.bennybar.luli_for_reddit.feature.foryou.DealIn
import com.bennybar.luli_for_reddit.feature.foryou.HomeLoadingDeck
import com.bennybar.luli_for_reddit.nav.LocalNavigator
import com.bennybar.luli_for_reddit.settings.PostDisplay
import com.bennybar.luli_for_reddit.ui.ErrorView
import com.bennybar.luli_for_reddit.ui.Overlays
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.launch

/** The [FeedController] for [feedKey], re-fetched after an account switch. */
@Composable
fun rememberFeedController(feedKey: String): FeedController {
    val version by app.feed.version.collectAsState()
    // Started right here (not in an effect) so the cached page can paint a frame sooner.
    return remember(feedKey, version) { app.feed.controller(feedKey).also { it.start() } }
}

/** Feed list bottom padding: room for the floating nav / FABs. */
val FeedPadding = PaddingValues(start = 10.dp, end = 10.dp, bottom = 130.dp)

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
) {
    val controller = rememberFeedController(feedKey)
    val ui by controller.ui.collectAsStateWithLifecycle()
    val settings by app.settings.state.collectAsStateWithLifecycle()
    val nav = LocalNavigator.current
    val view = rememberView()
    val scope = rememberCoroutineScope()
    // Build cards about a screen ahead (Flutter's 1200px cache extent; the
    // default is one item), so they're laid out and their images decoding
    // before they appear.
    val listState = rememberLazyListState(cacheWindow = remember { LazyLayoutCacheWindow(ahead = 440.dp, behind = 440.dp) })
    var refreshing by remember { mutableStateOf(false) }
    val isFrontpage = feedKey.isEmpty()
    val homeMode = isFrontpage && settings.redditHomeAllowed && settings.redditHomeFeed
    // Home and For You load behind the shuffling deck.
    val deckMode = isFrontpage && (homeMode || settings.forYouFeed)
    // The loading deck was just showing: deal the first cards in.
    var dealHome by remember { mutableStateOf(false) }

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

    // Returning to the feed after a pushed route (e.g. a post) is popped:
    // pull in fresh posts if the feed has gone stale. (The first resume is
    // this screen opening.)
    var resumedOnce by rememberSaveable { mutableStateOf(false) }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) {
        if (resumedOnce) controller.refreshIfStale() else resumedOnce = true
    }

    // A sort / feed change replaces the list: start the new one at the top.
    val isLoading = ui is FeedUi.Loading
    LaunchedEffect(isLoading) { if (isLoading) listState.scrollToItem(0) }

    if (isFrontpage) {
        // Frontpage only: respond to the "tap active tab" signal — scroll to
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
        // "Reddit Home couldn't load, showing For You" and similar.
        LaunchedEffect(Unit) {
            app.forYou.redditHome.notice.collect { msg ->
                if (msg != null) {
                    nav.showSnackbar(msg)
                    app.forYou.redditHome.notice.value = null
                }
            }
        }
    }

    Box(modifier.fillMaxSize()) {
        PullToRefreshBox(
            isRefreshing = refreshing,
            onRefresh = { refresh() },
            modifier = Modifier.fillMaxSize(),
        ) {
            when (val u = ui) {
                FeedUi.Loading -> {
                    // Home (no saved page to show yet): the shuffling deck with a
                    // live count of posts found; its cards are then dealt in.
                    if (deckMode) SideEffect { dealHome = true }
                    LazyColumn(Modifier.fillMaxSize(), contentPadding = FeedPadding, userScrollEnabled = true) {
                        if (header != null) item(key = "header", contentType = "header") { header() }
                        if (deckMode) {
                            item(key = "deck") {
                                Column {
                                    Spacer(Modifier.height(120.dp))
                                    HomeLoadingDeck(forYou = !homeMode)
                                }
                            }
                        } else {
                            item(key = "gap") { Spacer(Modifier.height(8.dp)) }
                            items(5, key = { "sk$it" }, contentType = { "skeleton" }) {
                                PostSkeleton(Modifier.padding(bottom = 10.dp))
                            }
                        }
                    }
                }
                is FeedUi.Error -> LazyColumn(Modifier.fillMaxSize()) {
                    if (header != null) item(key = "header", contentType = "header") { header() }
                    item(key = "error") {
                        ErrorView(u.error, Modifier.height(360.dp), onRetry = controller::retry)
                    }
                }
                is FeedUi.Data -> FeedList(
                    feedKey = feedKey,
                    state = u.state,
                    controller = controller,
                    listState = listState,
                    header = header,
                    homeMode = homeMode,
                    deckMode = deckMode,
                    dealHome = dealHome,
                    onDealt = { dealHome = false },
                    onSort = { s, t -> controller.changeSort(s, t) },
                )
            }
        }
        val pending = (ui as? FeedUi.Data)?.state?.hasPending == true
        if (pending) {
            NewPostsPill(
                Modifier.align(Alignment.TopCenter).padding(top = 8.dp),
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
    state: FeedState,
    controller: FeedController,
    listState: LazyListState,
    header: (@Composable () -> Unit)?,
    homeMode: Boolean,
    deckMode: Boolean,
    dealHome: Boolean,
    onDealt: () -> Unit,
    onSort: (PostSort, TopTime?) -> Unit,
) {
    val settings by app.settings.state.collectAsStateWithLifecycle()
    val hiddenIds by app.hiddenPosts.ids.collectAsStateWithLifecycle()
    val filters by app.contentFilters.state.collectAsStateWithLifecycle()
    // Auto-hide already-read items in the For You feed (live: updates when
    // history changes). Only watched while the option is on.
    val seen: Set<String>? = if (settings.autoHideReadForYou) app.history.ids.collectAsStateWithLifecycle().value else null
    // A subreddit feed still shows that subreddit's own posts.
    val viewing = if (feedKey.isEmpty() || feedKey.startsWith("m::")) null else feedKey

    val posts = remember(state.posts, seen, hiddenIds, filters, viewing) {
        var list = state.posts
        if (seen != null) list = list.filter { !(it.feedReason != null && it.id in seen) }
        // Posts hidden this session (Hide / swipe-to-hide).
        if (hiddenIds.isNotEmpty()) list = list.filter { it.id !in hiddenIds }
        // User content filters (keywords / domains / flairs / subreddits).
        if (!filters.isEmpty) list = list.filter { !filters.hides(it, viewingSubreddit = viewing) }
        // A page boundary can repeat a post that moved up meanwhile; the list
        // needs unique keys.
        list.distinctBy { it.id }
    }
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

    val isFrontpage = feedKey.isEmpty()
    LazyColumn(
        Modifier.fillMaxSize(),
        state = listState,
        contentPadding = FeedPadding,
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        if (header != null) item(key = "header", contentType = "header") { header() }
        item(key = "sortbar", contentType = "sortbar") {
            SortBar(
                sort = state.sort,
                time = state.time,
                onPick = onSort,
                isFrontpage = isFrontpage,
                forYou = settings.forYouFeed && isFrontpage,
                onForYou = controller::selectForYou,
                redditHome = homeMode,
                onRedditHome = if (settings.redditHomeAllowed) controller::selectRedditHome else null,
            )
        }
        items(posts.size, key = { posts[it].id }, contentType = { "post_${posts[it].type}" }) { i ->
            val p = posts[i]
            if (deckMode && i < 3) {
                // The first cards after the loading deck are dealt in.
                if (i == 2) LaunchedEffect(Unit) { onDealt() }
                DealIn(i, animate = dealHome) { PostCard(p) }
            } else {
                PostCard(p)
            }
        }
        item(key = "footer", contentType = "footer") {
            val muted = MaterialTheme.colorScheme.onSurfaceVariant
            Column(Modifier.fillMaxWidth().padding(vertical = 24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                when {
                    state.loadingMore -> CircularProgressIndicator()
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

@Composable
fun SortBar(
    sort: PostSort,
    time: TopTime,
    onPick: (PostSort, TopTime?) -> Unit,
    isFrontpage: Boolean = false,
    forYou: Boolean = false,
    onForYou: (() -> Unit)? = null,
    redditHome: Boolean = false,
    onRedditHome: (() -> Unit)? = null, // null unless enabled in Settings
) {
    val scope = rememberCoroutineScope()
    val label = when {
        redditHome -> "Home"
        forYou -> "For You · Beta"
        sort.needsTime -> "${sort.label} · ${time.label}"
        else -> sort.label
    }
    Row(Modifier.padding(horizontal = 6.dp, vertical = 8.dp)) {
        AssistChip(
            onClick = {
                scope.launch {
                    showSortSheet(sort, time, onPick, isFrontpage, forYou, onForYou, redditHome, onRedditHome)
                }
            },
            label = { Text(label) },
            leadingIcon = {
                Icon(
                    when {
                        redditHome -> Icons.Rounded.Home
                        forYou -> Icons.Rounded.AutoAwesome
                        else -> Icons.AutoMirrored.Rounded.Sort
                    },
                    null,
                    Modifier.size(18.dp),
                )
            },
            shape = CircleShape,
            border = null,
            colors = AssistChipDefaults.assistChipColors(containerColor = MaterialTheme.colorScheme.surfaceContainerHigh),
        )
    }
}

private sealed interface SortPick {
    data object ForYou : SortPick
    data object Home : SortPick
    data class Sort(val sort: PostSort) : SortPick
}

@OptIn(ExperimentalMaterial3Api::class)
private suspend fun showSortSheet(
    sort: PostSort,
    time: TopTime,
    onPick: (PostSort, TopTime?) -> Unit,
    isFrontpage: Boolean,
    forYou: Boolean,
    onForYou: (() -> Unit)?,
    redditHome: Boolean,
    onRedditHome: (() -> Unit)?,
) {
    val pick = Overlays.show<SortPick> { done ->
        ModalBottomSheet(onDismissRequest = { done(null) }) {
            TapGuard {
                Column(Modifier.navigationBarsPadding()) {
                    if (isFrontpage && onForYou != null) {
                        SheetTile(Icons.Rounded.AutoAwesome, "For You", "Personalized · Beta", checked = forYou) { done(SortPick.ForYou) }
                    }
                    if (isFrontpage && onRedditHome != null) {
                        SheetTile(Icons.Rounded.Home, "Home", "Your reddit.com Home", checked = redditHome) { done(SortPick.Home) }
                    }
                    for (s in PostSort.entries) {
                        SheetTile(iconFor(s), s.label, null, checked = !forYou && !redditHome && s == sort) { done(SortPick.Sort(s)) }
                    }
                }
            }
        }
    } ?: return
    when (pick) {
        SortPick.ForYou -> onForYou?.invoke()
        SortPick.Home -> onRedditHome?.invoke()
        is SortPick.Sort -> if (pick.sort.needsTime) {
            val t = Overlays.show<TopTime> { done ->
                ModalBottomSheet(onDismissRequest = { done(null) }) {
                    TapGuard {
                        Column(Modifier.navigationBarsPadding()) {
                            for (t in TopTime.entries) SheetTile(null, t.label, null, checked = t == time) { done(t) }
                        }
                    }
                }
            } ?: return
            onPick(pick.sort, t)
        } else {
            onPick(pick.sort, null)
        }
    }
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
