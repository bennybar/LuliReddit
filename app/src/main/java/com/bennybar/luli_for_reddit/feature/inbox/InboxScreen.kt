package com.bennybar.luli_for_reddit.feature.inbox

import com.bennybar.luli_for_reddit.feature.feed.LoadMoreNearEnd
import com.bennybar.luli_for_reddit.feature.feed.SwipeSpec
import com.bennybar.luli_for_reddit.feature.feed.SwipeActions
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
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
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.PrimaryScrollableTabRow
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
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
import com.bennybar.luli_for_reddit.ui.friendlyError
import kotlinx.coroutines.launch

/** The Inbox tab. [reselect] bumps when the tab is re-tapped (scroll to top). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InboxScreen(reselect: Int) {
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
        Scaffold(topBar = { TopAppBar(title = title, colors = appBarColors) }) { padding ->
            Box(Modifier.padding(padding)) {
                SignInPrompt("Sign in to see your messages, replies and mentions.")
            }
        }
        return
    }

    val tabs = InboxModule.TABS
    val pager = rememberPagerState { tabs.size }
    val lists = tabs.map { rememberLazyListState() }
    val scope = rememberCoroutineScope()

    // Re-tapping the Inbox tab scrolls the current list to top.
    val initialReselect = remember { reselect }
    LaunchedEffect(reselect) {
        if (reselect != initialReselect) lists[pager.currentPage].animateScrollToItem(0)
    }

    Scaffold(
        topBar = {
            Column {
                TopAppBar(
                    title = title,
                    colors = appBarColors,
                    actions = {
                        IconButton(onClick = {
                            scope.launch {
                                try {
                                    app.inbox.markAllRead(tabs[pager.currentPage].second)
                                } catch (e: Exception) {
                                    nav.showSnackbar("Couldn't mark all read: ${friendlyError(e)}")
                                }
                            }
                        }) { Icon(Icons.Outlined.MarkEmailRead, "Mark all read") }
                    },
                )
                PrimaryScrollableTabRow(
                    selectedTabIndex = pager.currentPage,
                    edgePadding = 0.dp,
                    containerColor = MaterialTheme.colorScheme.surface,
                ) {
                    tabs.forEachIndexed { i, (label, _) ->
                        Tab(
                            selected = pager.currentPage == i,
                            onClick = { scope.launch { pager.animateScrollToPage(i) } },
                            text = { Text(label) },
                        )
                    }
                }
            }
        },
        floatingActionButton = {
            ExtendedFloatingActionButton(
                onClick = { nav.push(Route.ComposeMessage()) },
                icon = { Icon(Icons.Rounded.Edit, null) },
                text = { Text("New message") },
                shape = RoundedCornerShape(20.dp),
                containerColor = MaterialTheme.colorScheme.primaryContainer,
                contentColor = MaterialTheme.colorScheme.onPrimaryContainer,
                // Clear of the home shell's floating nav bar.
                modifier = Modifier.padding(bottom = nav.snackbarBottomPadding),
            )
        },
    ) { padding ->
        HorizontalPager(
            pager,
            Modifier.fillMaxSize().padding(top = padding.calculateTopPadding()),
            beyondViewportPageCount = 1,
        ) { page ->
            InboxList(tabs[page].second, lists[page])
        }
    }
}

private val kindFilters = listOf("all" to "All", "replies" to "Replies", "mentions" to "Mentions", "messages" to "Messages")

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun InboxList(where: String, listState: LazyListState) {
    val nav = LocalNavigator.current
    val state by app.inbox.tab(where).collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    var refreshing by remember { mutableStateOf(false) }
    // Kind filter, only used on the "All" tab: all | replies | mentions | messages.
    var kindFilter by rememberSaveable { mutableStateOf("all") }

    LaunchedEffect(where) { app.inbox.ensureLoaded(where) }

    val items = remember(state.items, kindFilter, where) {
        if (where != "inbox" || kindFilter == "all") state.items
        else state.items.filter {
            when (kindFilter) {
                "replies" -> it.kind == InboxKind.COMMENT_REPLY || it.kind == InboxKind.POST_REPLY
                "mentions" -> it.kind == InboxKind.MENTION
                "messages" -> it.kind == InboxKind.MESSAGE
                else -> true
            }
        }
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

    Column(Modifier.fillMaxSize()) {
        if (where == "inbox") {
            Row(
                Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState())
                    .padding(start = 12.dp, end = 12.dp, top = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                for ((key, label) in kindFilters) {
                    FilterChip(
                        selected = kindFilter == key,
                        onClick = { kindFilter = key },
                        label = { Text(label) },
                        shape = CircleShape,
                        border = null,
                        colors = FilterChipDefaults.filterChipColors(
                            containerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
                        ),
                    )
                }
            }
        }
        PullToRefreshBox(
            isRefreshing = refreshing,
            onRefresh = {
                scope.launch {
                    refreshing = true
                    app.inbox.refreshAndWait(where)
                    refreshing = false
                }
            },
            modifier = Modifier.fillMaxSize(),
        ) {
            when {
                state.loading && state.items.isEmpty() -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
                // A failed (re)load shows the error even over loaded items, as in
                // Flutter (its AsyncError replaced the list); pull to retry.
                state.error != null -> LazyColumn(Modifier.fillMaxSize()) {
                    item {
                        Text(
                            "Could not load inbox.\n${friendlyError(state.error)}",
                            Modifier.fillMaxWidth().padding(32.dp),
                            textAlign = TextAlign.Center,
                        )
                    }
                }
                items.isEmpty() -> LazyColumn(Modifier.fillMaxSize()) {
                    item {
                        Spacer(Modifier.height(120.dp))
                        Text("Nothing here", Modifier.fillMaxWidth(), textAlign = TextAlign.Center)
                    }
                }
                else -> LazyColumn(
                    state = listState,
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(start = 12.dp, end = 12.dp, top = 12.dp, bottom = 130.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    items(items, key = { it.fullname }, contentType = { "inbox" }) { item ->
                        SwipeableInboxCard(item, onOpen = { open(nav, item) })
                    }
                    if (state.loadingMore) {
                        item(key = "loadingMore", contentType = "loading") {
                            Box(Modifier.fillMaxWidth().padding(16.dp), contentAlignment = Alignment.Center) {
                                CircularProgressIndicator()
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
        if (item.isMessage) SwipeSpec(Icons.Outlined.DeleteOutline, cs.error) { app.inbox.deleteMessage(item.fullname) } else null
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

    BloomCard(Modifier.fillMaxWidth(), onClick = onTap) {
        Column(Modifier.padding(14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(icon, null, Modifier.size(16.dp), tint = cs.primary)
                Spacer(Modifier.width(6.dp))
                Text(label, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = cs.primary)
                Spacer(Modifier.width(8.dp))
                Text(
                    "u/${item.author} · ${timeAgo(item.createdUtc)}",
                    Modifier.weight(1f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    fontSize = 12.sp,
                    color = cs.onSurfaceVariant,
                )
                if (item.isNew) Box(Modifier.size(9.dp).background(cs.primary, CircleShape))
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
