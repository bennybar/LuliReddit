package com.bennybar.luli_for_reddit.feature.feed

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
import androidx.compose.material.icons.rounded.Merge
import androidx.compose.material.icons.rounded.Leaderboard
import androidx.compose.material.icons.rounded.LocalFireDepartment
import androidx.compose.material.icons.rounded.Schedule
import androidx.compose.material.icons.rounded.Star
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
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
val FeedPadding = PaddingValues(start = 7.dp, end = 7.dp, bottom = 130.dp)

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

    // Returning to the feed after a pushed route (e.g. a post) is popped, or
    // to the app: the frontpage keeps its posts for 30 minutes, then loads
    // anew; other feeds stage fresh posts behind a "New posts" pill once
    // stale. (The first resume is this screen opening.)
    var resumedOnce by rememberSaveable { mutableStateOf(false) }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) {
        when {
            !resumedOnce -> resumedOnce = true
            isFrontpage -> controller.refreshIfExpired()
            else -> controller.refreshIfStale()
        }
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
        // Back on the Posts tab (Settings → Back scrolls Posts to top).
        LaunchedEffect(listState) {
            app.feed.frontpageBackSignal.drop(1).collect { listState.animateScrollToItem(0) }
        }
        // Home (and Blend's Home posts): follow the card on screen in the hidden
        // reddit.com page, so Reddit's own "seen" tracking matches what was
        // actually read and the next load brings new posts. (Cards not on its
        // page are ignored there.)
        val blendMode = isFrontpage && settings.forYouFeed && settings.blendHome && settings.redditHomeAllowed
        if (homeMode || blendMode) LaunchedEffect(listState) {
            snapshotFlow {
                listState.layoutInfo.visibleItemsInfo.firstOrNull { (it.contentType as? String)?.startsWith("post_") == true }?.key as? String
            }.distinctUntilChanged().collect { id -> if (id != null) app.forYou.redditHome.viewing(id) }
        }
    }

    Box(modifier.fillMaxSize()) {
        RefreshBox(
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
                    onRetry = { refresh() },
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
    onRetry: () -> Unit,
) {
    val settings by app.settings.state.collectAsStateWithLifecycle()
    val homeStatus = if (homeMode) app.forYou.redditHome.status.collectAsStateWithLifecycle().value else null
    val hiddenIds by app.hiddenPosts.ids.collectAsStateWithLifecycle()
    // Home / For You: posts dismissed with the "Dismiss" swipe (kept a day).
    val dismissible = feedKey.isEmpty() && deckMode
    val dismissedIds = if (dismissible) app.dismissedPosts.ids.collectAsStateWithLifecycle().value else emptySet()
    // Subreddits hidden for 7 days: anywhere on the front page (Home, For You
    // and Best / Hot / New).
    val frontpage = feedKey.isEmpty()
    val hiddenSubs = if (frontpage) app.hiddenHomeSubs.ids.collectAsStateWithLifecycle().value else emptySet()
    val filters by app.contentFilters.state.collectAsStateWithLifecycle()
    // Auto-hide already-read items in the For You feed (live: updates when
    // history changes). Only watched while the option is on. Not in Reddit
    // Home: its recommended posts carry Reddit's reason too, and opening one
    // made it vanish on return.
    val seen: Set<String>? = if (settings.autoHideReadForYou && !homeMode) app.history.ids.collectAsStateWithLifecycle().value else null
    // A subreddit feed still shows that subreddit's own posts.
    val viewing = if (feedKey.isEmpty() || feedKey.startsWith("m::")) null else feedKey

    val posts = remember(state.posts, seen, hiddenIds, dismissedIds, hiddenSubs, filters, viewing) {
        var list = state.posts
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
                blend = settings.forYouFeed && settings.blendHome && settings.redditHomeAllowed && isFrontpage,
                onBlend = if (settings.redditHomeAllowed) controller::selectBlend else null,
            )
        }
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
    blend: Boolean = false,
    onBlend: (() -> Unit)? = null, // null unless Reddit Home is enabled
    sorts: List<PostSort> = PostSort.entries,
) {
    val scope = rememberCoroutineScope()
    val label = when {
        redditHome -> "Home"
        blend -> "Blend · Beta"
        forYou -> "For You"
        sort.needsTime -> "${sort.label} · ${time.label}"
        else -> sort.label
    }
    Row(Modifier.padding(horizontal = 6.dp, vertical = 8.dp)) {
        AssistChip(
            onClick = {
                scope.launch {
                    showSortSheet(sort, time, onPick, isFrontpage, forYou && !blend, onForYou, redditHome, onRedditHome, blend, onBlend, sorts)
                }
            },
            label = { Text(label) },
            leadingIcon = {
                Icon(
                    when {
                        redditHome -> Icons.Rounded.Home
                        blend -> Icons.Rounded.Merge
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
    data object Blend : SortPick
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
    blend: Boolean,
    onBlend: (() -> Unit)?,
    sorts: List<PostSort>,
) {
    val pick = Overlays.show<SortPick> { done ->
        ModalBottomSheet(onDismissRequest = { done(null) }) {
            TapGuard {
                Column(Modifier.navigationBarsPadding()) {
                    if (isFrontpage && onForYou != null) {
                        SheetTile(Icons.Rounded.AutoAwesome, "For You", "Personalized on your phone", checked = forYou) { done(SortPick.ForYou) }
                    }
                    if (isFrontpage && onBlend != null) {
                        SheetTile(Icons.Rounded.Merge, "Blend · Beta", "Your Reddit Home + For You, ranked for you", checked = blend) { done(SortPick.Blend) }
                    }
                    if (isFrontpage && onRedditHome != null) {
                        SheetTile(Icons.Rounded.Home, "Home", "Your reddit.com Home", checked = redditHome) { done(SortPick.Home) }
                    }
                    for (s in sorts) {
                        SheetTile(iconFor(s), s.label, null, checked = !forYou && !blend && !redditHome && s == sort) { done(SortPick.Sort(s)) }
                    }
                }
            }
        }
    } ?: return
    when (pick) {
        SortPick.ForYou -> onForYou?.invoke()
        SortPick.Home -> onRedditHome?.invoke()
        SortPick.Blend -> onBlend?.invoke()
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
