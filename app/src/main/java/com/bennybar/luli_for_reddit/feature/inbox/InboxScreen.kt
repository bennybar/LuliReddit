package com.bennybar.luli_for_reddit.feature.inbox

import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import com.bennybar.luli_for_reddit.feature.feed.FeedChip
import com.bennybar.luli_for_reddit.feature.feed.HidingTopBar
import com.bennybar.luli_for_reddit.feature.feed.rememberHidingBar
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import com.bennybar.luli_for_reddit.feature.home.LocalEdgeDrag
import com.bennybar.luli_for_reddit.feature.home.SideBarEdge
import com.bennybar.luli_for_reddit.feature.feed.rememberFabScroll
import com.bennybar.luli_for_reddit.feature.feed.CollapsingFab
import androidx.compose.ui.input.nestedscroll.nestedScroll
import com.bennybar.luli_for_reddit.ui.RefreshBox
import com.bennybar.luli_for_reddit.ui.Loading
import com.bennybar.luli_for_reddit.feature.home.SideBarButton
import com.bennybar.luli_for_reddit.feature.home.aboveFloatingNav
import com.bennybar.luli_for_reddit.feature.home.LocalSideBar
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.PointerInputChange
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.unit.LayoutDirection
import kotlin.math.abs
import androidx.compose.runtime.DisposableEffect
import androidx.compose.material3.TextButton
import androidx.compose.material.icons.rounded.ArrowUpward
import androidx.compose.material.icons.outlined.Notifications
import com.bennybar.luli_for_reddit.feature.home.SettingsButton
import com.bennybar.luli_for_reddit.feature.web.rememberWebSignIn
import com.bennybar.luli_for_reddit.feature.web.RedditWeb
import androidx.compose.material.icons.automirrored.outlined.Chat
import com.bennybar.luli_for_reddit.feature.feed.LoadMoreNearEnd
import com.bennybar.luli_for_reddit.feature.feed.SwipeSpec
import com.bennybar.luli_for_reddit.feature.feed.SwipeActions
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.Login
import androidx.compose.material.icons.automirrored.rounded.Reply
import androidx.compose.material.icons.outlined.DeleteOutline
import androidx.compose.material.icons.outlined.Forum
import androidx.compose.material.icons.outlined.MailOutline
import androidx.compose.material.icons.outlined.MarkEmailRead
import androidx.compose.material.icons.outlined.MarkEmailUnread
import androidx.compose.material.icons.rounded.AlternateEmail
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material.icons.rounded.TravelExplore
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.snapshots.Snapshot
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.auth.SessionState
import com.bennybar.luli_for_reddit.core.timeAgo
import com.bennybar.luli_for_reddit.feature.auth.BloomCard
import com.bennybar.luli_for_reddit.model.InboxItem
import com.bennybar.luli_for_reddit.model.InboxKind
import com.bennybar.luli_for_reddit.nav.AppNavigator
import com.bennybar.luli_for_reddit.nav.LocalNavigator
import com.bennybar.luli_for_reddit.nav.NavCache
import com.bennybar.luli_for_reddit.nav.Route
import androidx.compose.foundation.layout.RowScope
import com.bennybar.luli_for_reddit.feature.home.TabSearchBar
import com.bennybar.luli_for_reddit.feature.feed.CollapsingTitleBar
import com.bennybar.luli_for_reddit.feature.feed.rememberCollapsingTitle
import com.bennybar.luli_for_reddit.settings.TopBarMode
import com.bennybar.luli_for_reddit.ui.friendlyError
import com.bennybar.luli_for_reddit.feature.post.confirmDelete
import kotlinx.coroutines.launch
import com.bennybar.luli_for_reddit.ui.userName

/** The Inbox tab. [reselect] bumps when the tab is re-tapped (scroll to top). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InboxScreen(reselect: Int, selected: Boolean = true, /** A page of its own (Inbox in Profile), with ←. */ pushed: Boolean = false) {
    val nav = LocalNavigator.current
    val session by app.session.state.collectAsStateWithLifecycle()
    val anonymous = (session as? SessionState.LoggedIn)?.session?.anonymous == true
    val appBarColors = TopAppBarDefaults.topAppBarColors(
        containerColor = MaterialTheme.colorScheme.surface,
        scrolledContainerColor = MaterialTheme.colorScheme.surface,
    )
    val title: @Composable () -> Unit = {
        Text("Inbox", style = MaterialTheme.typography.headlineSmall.copy(fontWeight = FontWeight.Bold))
    }

    if (anonymous) {
        Scaffold(Modifier.statusBarsPadding(), topBar = { TopAppBar(title = title, navigationIcon = { SideBarButton() }, colors = appBarColors) }) { padding ->
            Box(Modifier.padding(padding)) {
                SignInPrompt("Sign in to see your messages, replies and mentions.")
            }
        }
        return
    }

    // Signed in on the web: Reddit's own notifications (a chip) and Chat.
    val webSignIn = rememberWebSignIn()
    // One row of chips (#246), each a page you can also swipe to: what were the tabs and,
    // under All, a second row of filters ("Messages" was in both).
    val pages = if (webSignIn) INBOX_PAGES + InboxPage("Reddit", REDDIT_TAB) else INBOX_PAGES
    val pager = rememberPagerState { pages.size }
    val lists = pages.map { rememberLazyListState() }
    val scope = rememberCoroutineScope()

    // Opening Inbox reloads what's a minute old, and new mail (the badge going
    // up) reloads it at once (#150): it used to wait for a pull.
    val unread by app.inbox.unreadCount.collectAsStateWithLifecycle()
    var lastUnread by remember { mutableIntStateOf(unread) }
    var newMail by remember { mutableStateOf(false) }
    LaunchedEffect(unread) {
        if (unread > lastUnread) newMail = true
        lastUnread = unread
    }
    LaunchedEffect(selected, newMail) {
        if (!selected) return@LaunchedEffect
        app.inbox.refreshStale(if (newMail) 0L else 60_000L)
        newMail = false
    }

    val fab = rememberFabScroll()
    val settings by app.settings.state.collectAsStateWithLifecycle()
    val collapsing = rememberCollapsingTitle {
        val l = lists[pager.currentPage]
        l.firstVisibleItemIndex == 0 && l.firstVisibleItemScrollOffset == 0
    }
    // The bar (and its chips) floats over the lists and slides away as they scroll, back
    // as you scroll up, over a softly faded status bar: as Posts and Explore (#246).
    val bar = rememberHidingBar(lists[pager.currentPage])
    val expandable = pushed || settings.topBarMode != TopBarMode.FULL

    // Re-tapping the Inbox tab scrolls the current list to top.
    val initialReselect = remember { reselect }
    LaunchedEffect(reselect) {
        if (reselect != initialReselect) {
            lists[pager.currentPage].animateScrollToItem(0)
            bar.slide(0f)
        }
    }
    // Another chip: the bar comes back out, over a list that may be anywhere, and the
    // big title opens over one at its top (the swipe there counted as a scroll).
    LaunchedEffect(pager.currentPage) {
        bar.slide(0f)
        val l = lists[pager.currentPage]
        if (l.firstVisibleItemIndex == 0 && l.firstVisibleItemScrollOffset == 0) collapsing.expand()
    }

    val openSideBar = LocalSideBar.current
    val rtl = LocalLayoutDirection.current == LayoutDirection.Rtl
    val barActions: @Composable RowScope.() -> Unit = {
        if (webSignIn) {
            IconButton(onClick = { nav.push(Route.RedditWeb(RedditWeb.CHAT, "Chat")) }) {
                Icon(Icons.AutoMirrored.Outlined.Chat, "Reddit Chat")
            }
        }
        // Reddit's notifications are read-only here: nothing to mark.
        if (pages[pager.currentPage].where != REDDIT_TAB) IconButton(onClick = {
            scope.launch {
                try {
                    app.inbox.markAllRead(pages[pager.currentPage].where)
                } catch (e: Exception) {
                    nav.showSnackbar("Couldn't mark all read: ${friendlyError(e)}")
                }
            }
        }) { Icon(Icons.Outlined.MarkEmailRead, "Mark all read") }
        // The side bar always has Settings (#145).
        if (openSideBar == null) SettingsButton()
    }
    Scaffold(
        floatingActionButton = {
            CollapsingFab(
                Icons.Rounded.Edit,
                "New message",
                fab.expanded,
                onClick = { nav.push(Route.ComposeMessage()) },
                // Over the home shell's floating nav, down with it as it hides (the
                // Scaffold keeps it 16dp above the system bar).
                modifier = Modifier.aboveFloatingNav(),
            )
        },
    ) { _ ->
        // Expandable: scrolling a list folds the title first, then the bar slides away (#226).
        Box(Modifier.fillMaxSize().clipToBounds().then(if (expandable) Modifier.nestedScroll(collapsing) else Modifier).nestedScroll(bar)) {
        val barHeight = with(LocalDensity.current) { bar.height.toDp() }
        // A drag from the start edge goes to the side bar, which follows the finger (#158).
        SideBarEdge(Modifier.fillMaxSize()) {
        HorizontalPager(
            pager,
            Modifier.fillMaxSize().nestedScroll(fab),
            beyondViewportPageCount = 1,
            userScrollEnabled = !LocalEdgeDrag.current.value,
        ) { page ->
            Box(if (openSideBar == null) Modifier else Modifier.pointerInput(rtl) {
                // The side bar's own drag sits above the pager, which takes every
                // sideways drag first, even on the first section where it can only
                // stretch (#113). From the start edge the pager and rows step aside
                // and the side bar's own drag follows the finger (SideBarEdge, #158);
                // elsewhere on the first section, a drag toward it opens it after the
                // rows have seen it, so a row's swipe still wins there.
                val edge = 48.dp.toPx()
                awaitEachGesture {
                    val down = awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
                    val fromEdge = if (rtl) down.position.x > size.width - edge else down.position.x < edge
                    if (fromEdge || pager.canScrollBackward) return@awaitEachGesture
                    val pass = PointerEventPass.Main
                    // The down's own Main pass: a row's tap has consumed it by then.
                    awaitPointerEvent(pass)
                    val slop = viewConfiguration.touchSlop
                    var total = Offset.Zero
                    var change: PointerInputChange
                    do {
                        change = awaitPointerEvent(pass).changes.firstOrNull { it.id == down.id } ?: return@awaitEachGesture
                        if (!change.pressed || change.isConsumed) return@awaitEachGesture
                        total += change.positionChange()
                    } while (total.getDistance() < slop)
                    if (!isSideBarDrag(total.x, total.y, rtl)) return@awaitEachGesture
                    change.consume()
                    openSideBar()
                    // Keep the rest of it, or the pager or list picks the drag back up.
                    while (true) {
                        change = awaitPointerEvent(pass).changes.firstOrNull { it.id == down.id } ?: break
                        if (!change.pressed) break
                        change.consume()
                    }
                }
            }) {
                if (pages[page].where == REDDIT_TAB) RedditNotificationsList(active = pager.currentPage == page, lists[page], barHeight)
                else InboxList(pages[page], lists[page], barHeight)
            }
        }
        }
        HidingTopBar(bar, Modifier.statusBarsPadding()) {
            Column {
                // Settings › Appearance › Top bar, as Posts and Explore (#214): Full, the
                // round search bar with Inbox's buttons after it; Expandable, the title.
                if (pushed) {
                    // A page of its own: its title, with ← (no search bar: that's the tabs').
                    CollapsingTitleBar(
                        collapsing, "Inbox", hasNavigation = true, underStatusBar = false,
                        navigation = {
                            IconButton(onClick = { nav.pop() }) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Back") }
                        },
                        actions = barActions,
                    )
                } else if (!expandable) {
                    TabSearchBar("Search Reddit", onSearch = { nav.push(Route.Search()) }, actions = barActions)
                } else {
                    // Expandable: the big title that folds into the bar as the list scrolls.
                    CollapsingTitleBar(
                        collapsing, "Inbox", hasNavigation = openSideBar != null, underStatusBar = false,
                        navigation = { SideBarButton() }, actions = barActions,
                    )
                }
                InboxChips(pages, pager.currentPage, unread) { scope.launch { pager.animateScrollToPage(it) } }
            }
        }
        }
    }
}

/** A chip of Inbox's row (#246): Reddit's [where] list, only its [kinds] when set. */
private data class InboxPage(val label: String, val where: String, val kinds: Set<InboxKind>? = null)

/**
 * All, Unread, Replies, Mentions, Messages, Sent. Replies are All's comment and post
 * replies (Reddit lists those two apart); Mentions are Reddit's own list of them.
 */
private val INBOX_PAGES = listOf(
    InboxPage("All", "inbox"),
    InboxPage("Unread", "unread"),
    InboxPage("Replies", "inbox", setOf(InboxKind.COMMENT_REPLY, InboxKind.POST_REPLY)),
    InboxPage("Mentions", "mentions"),
    InboxPage("Messages", "messages"),
    InboxPage("Sent", "sent"),
)

/** The chips, the one picked kept in view as you swipe between them. */
@Composable
private fun InboxChips(pages: List<InboxPage>, current: Int, unread: Int, onPick: (Int) -> Unit) {
    val row = rememberLazyListState()
    LaunchedEffect(current) { row.animateScrollToItem((current - 1).coerceAtLeast(0)) }
    LazyRow(
        Modifier.fillMaxWidth().padding(vertical = 8.dp),
        state = row,
        contentPadding = PaddingValues(horizontal = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        itemsIndexed(pages, key = { _, p -> p.label }) { i, p ->
            FeedChip(if (p.where == "unread" && unread > 0) "Unread · $unread" else p.label, i == current) { onPick(i) }
        }
    }
}

/**
 * Whether a drag of ([dx], [dy]) px, as it leaves the touch slop, heads for
 * the side bar (toward the end edge, rightward in left-to-right layouts):
 * one the pager would have taken, sideways more than up or down.
 */
internal fun isSideBarDrag(dx: Float, dy: Float, rtl: Boolean): Boolean = (if (rtl) -dx else dx) > abs(dy)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun InboxList(page: InboxPage, listState: LazyListState, top: Dp) {
    val where = page.where
    val nav = LocalNavigator.current
    val state by app.inbox.tab(where).collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    var refreshing by remember { mutableStateOf(false) }

    LaunchedEffect(where) { app.inbox.ensureLoaded(where) }

    val items = remember(state.items, page.kinds) {
        page.kinds?.let { kinds -> state.items.filter { it.kind in kinds } } ?: state.items
    }

    // Load the next page as the end comes into view (asking again whenever a
    // page lands, so a filter showing few rows doesn't stall).
    LoadMoreNearEnd(listState, 4, page = state.items.size to state.after) { app.inbox.loadMore(where) }
    // A kind filter can leave too few rows to scroll (or none, and no list):
    // keep fetching, within a bound, until there's a screenful.
    LaunchedEffect(items.size, state.items.size, state.after, state.loadingMore, state.loading) {
        if (items.size < 10 && state.hasMore && !state.loading && !state.loadingMore && state.items.size < 500) {
            app.inbox.loadMore(where)
        }
    }

    // Under the floating bar ([top] tall): the rows start below it and run up under it.
    Column(Modifier.fillMaxSize()) {
        RefreshBox(
            isRefreshing = refreshing,
            onRefresh = {
                scope.launch {
                    refreshing = true
                    app.inbox.refreshAndWait(where)
                    refreshing = false
                }
            },
            modifier = Modifier.fillMaxSize(),
            indicatorPadding = top,
        ) {
            when {
                state.loading && state.items.isEmpty() -> Box(Modifier.fillMaxSize().padding(top = top), contentAlignment = Alignment.Center) {
                    Loading()
                }
                // A failed (re)load shows the error even over loaded items, as in
                // Flutter (its AsyncError replaced the list); pull to retry.
                state.error != null -> LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(top = top)) {
                    item {
                        Text(
                            "Could not load inbox.\n${friendlyError(state.error)}",
                            Modifier.fillMaxWidth().padding(32.dp),
                            textAlign = TextAlign.Center,
                        )
                    }
                }
                items.isEmpty() -> LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(top = top)) {
                    item {
                        Spacer(Modifier.height(120.dp))
                        Text("Nothing here", Modifier.fillMaxWidth(), textAlign = TextAlign.Center)
                    }
                }
                else -> {
                    // New items land above the first row, and the list kept its row in view, so
                    // they were off screen (#150): a list at its top stays at its top. Read as the
                    // new first item arrives, before the list lays it out.
                    val firstKey = items.first().fullname
                    val wasAtTop = remember(firstKey) {
                        Snapshot.withoutReadObservation { listState.firstVisibleItemIndex == 0 && listState.firstVisibleItemScrollOffset == 0 }
                    }
                    LaunchedEffect(firstKey) { if (wasAtTop) listState.scrollToItem(0) }
                    LazyColumn(
                    state = listState,
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(start = 12.dp, end = 12.dp, top = top + 4.dp, bottom = 130.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    items(items, key = { it.fullname }, contentType = { "inbox" }) { item ->
                        SwipeableInboxCard(item, onOpen = { open(nav, item) })
                    }
                    if (state.loadingMore) {
                        item(key = "loadingMore", contentType = "loading") {
                            Box(Modifier.fillMaxWidth().padding(16.dp), contentAlignment = Alignment.Center) {
                                Loading()
                            }
                        }
                    }
                }
                }
            }
        }
    }
}

private fun open(nav: AppNavigator, item: InboxItem) {
    if (item.isNew) app.inbox.markRead(item.fullname)
    if (item.isMessage) {
        NavCache.put(item.fullname, item)
        nav.push(Route.MessageThread(item.fullname))
    } else {
        val (sub, postId) = item.postRef ?: return
        // Comment replies/mentions are t1_<id> → jump straight to that comment.
        val commentId = if (item.fullname.startsWith("t1_")) item.fullname.removePrefix("t1_") else item.contextCommentId
        nav.push(Route.Post(sub, postId, commentId))
    }
}

/**
 * Messages: swipe right = read/unread, swipe left = delete.
 * Comment replies/mentions: read/unread only (they can't be deleted).
 */
@Composable
private fun SwipeableInboxCard(item: InboxItem, onOpen: () -> Unit) {
    // The feed's swipe (fires once on release, then springs back). The Material
    // dismiss box left rows stuck half-way and could fire repeatedly.
    val cs = MaterialTheme.colorScheme
    val start = remember(item.fullname, item.isNew) {
        SwipeSpec(if (item.isNew) Icons.Outlined.MarkEmailRead else Icons.Outlined.MarkEmailUnread, Color(0xFF2E7D32)) {
            if (item.isNew) app.inbox.markRead(item.fullname) else app.inbox.markUnread(item.fullname)
        }
    }
    val end = remember(item.fullname, item.isMessage, cs.error) {
        // Deleting can't be undone, so the swipe asks first.
        if (item.isMessage) {
            SwipeSpec(Icons.Outlined.DeleteOutline, cs.error) {
                app.scope.launch { if (confirmDelete("message")) app.inbox.deleteMessage(item.fullname) }
            }
        } else null
    }
    SwipeActions(start = start, end = end) { InboxCard(item, onOpen) }
}

@Composable
private fun InboxCard(item: InboxItem, onTap: () -> Unit) {
    val cs = MaterialTheme.colorScheme
    val (icon, label) = when (item.kind) {
        InboxKind.MESSAGE -> Icons.Outlined.MailOutline to "Message"
        InboxKind.COMMENT_REPLY -> Icons.AutoMirrored.Rounded.Reply to "Comment reply"
        InboxKind.POST_REPLY -> Icons.Outlined.Forum to "Post reply"
        InboxKind.MENTION -> Icons.Rounded.AlternateEmail to "Mention"
    }
    val heading = if (item.isMessage) item.subject.ifEmpty { "(no subject)" } else item.linkTitle ?: label
    val snippet = remember(item.body) { item.body.replace('\n', ' ') }

    // Unread: the whole card in the selected side-bar entry's colour, not just a dot (#120).
    BloomCard(Modifier.fillMaxWidth(), onClick = onTap, color = if (item.isNew) cs.secondaryContainer else cs.surfaceContainerLow) {
        Column(Modifier.padding(14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(icon, null, Modifier.size(16.dp), tint = cs.primary)
                Spacer(Modifier.width(6.dp))
                Text(label, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = cs.primary)
                Spacer(Modifier.width(8.dp))
                Text(
                    "${userName(item.author)} · ${timeAgo(item.createdUtc)}",
                    Modifier.weight(1f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    fontSize = 12.sp,
                    color = cs.onSurfaceVariant,
                )
            }
            Spacer(Modifier.height(8.dp))
            Text(heading, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Spacer(Modifier.height(4.dp))
            Text(snippet, maxLines = 2, overflow = TextOverflow.Ellipsis, color = cs.onSurfaceVariant)
        }
    }
}

/** Shown instead of the inbox while browsing without an account. */
@Composable
private fun SignInPrompt(message: String) {
    val scope = rememberCoroutineScope()
    BloomCard(Modifier.padding(16.dp).fillMaxWidth()) {
        Column(Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Rounded.TravelExplore, null, tint = MaterialTheme.colorScheme.primary)
                Spacer(Modifier.width(10.dp))
                Text(
                    "Browsing without an account",
                    style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold),
                )
            }
            Spacer(Modifier.height(8.dp))
            Text(message)
            Spacer(Modifier.height(12.dp))
            // Ends the anonymous session; the root then shows login (the Client ID stays filled in).
            Button(onClick = { scope.launch { app.session.logout() } }) {
                Icon(Icons.AutoMirrored.Rounded.Login, null, Modifier.size(18.dp))
                Spacer(Modifier.width(8.dp))
                Text("Sign in")
            }
        }
    }
}

/** The Inbox pager key for Reddit's own notifications (website sign-in only). */
private const val REDDIT_TAB = "reddit"

/**
 * Reddit's own notifications (replies, mentions, upvote milestones…), read
 * from reddit.com when this tab is shown and kept a few minutes. A tap opens
 * the post or comment in Ilay; older ones are on reddit.com.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun RedditNotificationsList(active: Boolean, listState: LazyListState, top: Dp) {
    val nav = LocalNavigator.current
    val state by app.redditNotifications.state.collectAsStateWithLifecycle()
    // Only when you're on this tab (the pager also builds its neighbour);
    // leaving it lets the hidden page close.
    LaunchedEffect(active) { if (active) app.redditNotifications.refresh() else app.redditNotifications.release() }
    DisposableEffect(Unit) { onDispose { app.redditNotifications.release() } }
    val data = state as? RedditNotifications.State.Data
    LoadMoreNearEnd(listState, 4, page = (data?.items?.size ?: 0) to data?.hasMore) { app.redditNotifications.loadMore() }
    val openWeb = { nav.push(Route.RedditWeb(RedditNotifications.URL, "Reddit notifications")) }
    var refreshing by remember { mutableStateOf(false) }
    LaunchedEffect(state) { if (state !is RedditNotifications.State.Loading) refreshing = false }

    RefreshBox(
        isRefreshing = refreshing,
        onRefresh = {
            refreshing = true
            app.redditNotifications.refresh(force = true)
        },
        modifier = Modifier.fillMaxSize(),
        indicatorPadding = top,
    ) {
        when (val s = state) {
            null, RedditNotifications.State.Loading -> Box(Modifier.fillMaxSize().padding(top = top), contentAlignment = Alignment.Center) {
                Loading()
            }
            is RedditNotifications.State.Failed -> LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(top = top)) {
                item {
                    Column(Modifier.fillMaxWidth().padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(
                            if (s.signedOut) "Your Reddit website sign-in has expired. Sign in again to see Reddit's notifications."
                            else "Couldn't load Reddit's notifications. Pull to try again.",
                            textAlign = TextAlign.Center,
                        )
                        Spacer(Modifier.height(12.dp))
                        Button(onClick = openWeb) { Text("Open on reddit.com") }
                    }
                }
            }
            is RedditNotifications.State.Data -> LazyColumn(
                state = listState,
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(start = 12.dp, end = 12.dp, top = top + 4.dp, bottom = 130.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                if (s.items.isEmpty()) {
                    item(key = "empty") {
                        Spacer(Modifier.height(120.dp))
                        Text("No notifications", Modifier.fillMaxWidth(), textAlign = TextAlign.Center)
                    }
                }
                items(s.items, key = { it.id }, contentType = { "reddit" }) { n ->
                    RedditNotificationCard(n) {
                        app.redditNotifications.opened(n)
                        n.link?.let(nav::openLink) ?: openWeb()
                    }
                }
                if (s.loadingMore) {
                    item(key = "loadingMore", contentType = "loading") {
                        Box(Modifier.fillMaxWidth().padding(16.dp), contentAlignment = Alignment.Center) { Loading() }
                    }
                } else if (!s.hasMore && s.items.isNotEmpty()) {
                    item(key = "older", contentType = "older") {
                        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                            TextButton(onClick = openWeb) { Text("Older notifications on reddit.com") }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun RedditNotificationCard(n: RedditNotification, onTap: () -> Unit) {
    val cs = MaterialTheme.colorScheme
    val (icon, label) = when {
        n.type == "POST_REPLY" -> Icons.Outlined.Forum to "Post reply"
        n.type == "COMMENT_REPLY" -> Icons.AutoMirrored.Rounded.Reply to "Comment reply"
        n.type.contains("MENTION") -> Icons.Rounded.AlternateEmail to "Mention"
        n.type.startsWith("UPVOTE") -> Icons.Rounded.ArrowUpward to "Upvotes"
        else -> Icons.Outlined.Notifications to "Reddit"
    }
    BloomCard(Modifier.fillMaxWidth(), onClick = onTap, color = if (n.unread) cs.secondaryContainer else cs.surfaceContainerLow) {
        Column(Modifier.padding(14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(icon, null, Modifier.size(16.dp), tint = cs.primary)
                Spacer(Modifier.width(6.dp))
                Text(label, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = cs.primary)
                if (n.at > 0) {
                    Spacer(Modifier.width(8.dp))
                    Text(timeAgo(n.at), fontSize = 12.sp, color = cs.onSurfaceVariant)
                }
            }
            Spacer(Modifier.height(8.dp))
            Text(n.title, fontWeight = FontWeight.Bold, maxLines = 2, overflow = TextOverflow.Ellipsis)
            if (n.body.isNotEmpty()) {
                Spacer(Modifier.height(4.dp))
                Text(n.body, maxLines = 2, overflow = TextOverflow.Ellipsis, color = cs.onSurfaceVariant)
            }
        }
    }
}
