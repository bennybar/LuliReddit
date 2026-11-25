package com.bennybar.luli_for_reddit.feature.digest

import com.bennybar.luli_for_reddit.feature.feed.rememberPageHeader
import com.bennybar.luli_for_reddit.feature.feed.collapsingHeader
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
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.DoneAll
import androidx.compose.material.icons.rounded.History
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material.icons.rounded.RemoveDone
import androidx.compose.material.icons.rounded.RestartAlt
import androidx.compose.material.icons.rounded.Visibility
import androidx.compose.material.icons.rounded.VisibilityOff
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.core.timeAgoPhrase
import com.bennybar.luli_for_reddit.feature.feed.BloomTopBar
import com.bennybar.luli_for_reddit.feature.feed.HidingTopBar
import com.bennybar.luli_for_reddit.feature.feed.PostCard
import com.bennybar.luli_for_reddit.feature.feed.PostSkeleton
import com.bennybar.luli_for_reddit.feature.feed.SwipeSpec
import com.bennybar.luli_for_reddit.feature.feed.historyDayLabel
import com.bennybar.luli_for_reddit.feature.home.SideBarButton
import com.bennybar.luli_for_reddit.feature.feed.rememberHidingBar
import com.bennybar.luli_for_reddit.feature.settings.PickOption
import com.bennybar.luli_for_reddit.feature.settings.confirmDialog
import com.bennybar.luli_for_reddit.feature.settings.pickOption
import com.bennybar.luli_for_reddit.nav.AppNavigator
import com.bennybar.luli_for_reddit.nav.LocalNavigator
import com.bennybar.luli_for_reddit.nav.Route
import com.bennybar.luli_for_reddit.ui.ErrorView
import com.bennybar.luli_for_reddit.ui.RefreshBox
import com.bennybar.luli_for_reddit.ui.friendlyError
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import java.time.LocalDate

/**
 * The Digest on a page of its own (side bar, Profile ⋯ menu, the "menu only" choice), or
 * as a tab ([tab]: Show Digest in › Bottom tab), built when [selected] and scrolled to
 * the top when re-tapped ([reselect]).
 */
@Composable
fun DigestScreen(tab: Boolean = false, selected: Boolean = true, reselect: Int = 0) {
    val cs = MaterialTheme.colorScheme
    val v = rememberDigestView(active = selected)
    val listState = rememberLazyListState()
    val bar = rememberHidingBar(listState)
    val header = rememberPageHeader(listState)
    val firstReselect = remember { reselect }
    LaunchedEffect(reselect) { if (reselect != firstReselect) listState.animateScrollToItem(0) }
    Box(Modifier.fillMaxSize().background(cs.surface).clipToBounds().collapsingHeader(header).nestedScroll(bar)) {
        val top = with(LocalDensity.current) { bar.height.toDp() }
        RefreshBox(v.refreshing, { v.refresh(manual = true) }, Modifier.fillMaxSize(), indicatorPadding = top) {
            LazyColumn(
                Modifier.fillMaxSize(),
                state = listState,
                // A tab's list ends clear of the floating bottom bar.
                contentPadding = PaddingValues(start = 7.dp, top = top, end = 7.dp, bottom = if (tab) 130.dp else 32.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) { digestRows(v) }
        }
        // A tab has ☰ (with the side bar) where a page has ←.
        HidingTopBar(bar) { if (tab) BloomTopBar("Digest", navigation = { SideBarButton() }, collapsing = header) else BloomTopBar("Digest", collapsing = header) }
    }
}

/**
 * What the Digest shows (its screen, or Posts with the Digest chip picked): the day,
 * what's been marked read here, how the last build went.
 */
@Stable
class DigestView internal constructor(private val scope: CoroutineScope, private val nav: AppNavigator) {
    /** The day shown: null for today. */
    var day by mutableStateOf<String?>(null)
    var outcome by mutableStateOf<DigestModule.Outcome?>(null)
    var refreshing by mutableStateOf(false)

    /** Each day's "seen" time when it was first shown here: what came after it is New. */
    internal val seenAt = HashMap<String, Long>()

    // Collected by rememberDigestView, read by the rows.
    internal var days by mutableStateOf(emptyList<DigestDay>())
    internal var building by mutableStateOf(false)
    internal var readIds by mutableStateOf(emptySet<String>())
    internal var showRead by mutableStateOf(false)
    internal var order by mutableStateOf(DigestOrder.NOTABLE)
    internal var swipeSide by mutableStateOf(0)
    internal var progress by mutableStateOf<String?>(null)
    internal var showOverview by mutableStateOf(false)

    fun refresh(manual: Boolean, rebuild: Boolean = false) {
        if (refreshing) return
        day = null
        scope.launch {
            refreshing = manual
            try {
                val out = app.digest.refresh(manual, rebuild)
                outcome = out
                if (!manual) return@launch
                when (out) {
                    DigestModule.Outcome.UpToDate -> nav.showSnackbar("Up to date")
                    is DigestModule.Outcome.Updated -> nav.showSnackbar(
                        if (rebuild) "Rebuilt" else if (out.added == 0) "Nothing new yet" else "${out.added} new",
                    )
                    is DigestModule.Outcome.Failed -> nav.showSnackbar("Couldn't refresh: ${friendlyError(out.error)}")
                    else -> {}
                }
            } finally {
                refreshing = false
            }
        }
    }

    fun markRead(item: DigestItem) {
        val id = item.post.id
        // Read: off the list at once (Show read off), as a hidden card in the feed; Undo brings it back.
        app.history.markViewed(item.post)
        nav.showSnackbar("Marked read", actionLabel = "Undo") { app.history.removeViewed(id) }
    }

    fun markUnread(item: DigestItem) {
        app.history.removeViewed(item.post.id)
        nav.showSnackbar("Marked unread")
    }

    fun menu() = scope.launch {
        val s = app.settings.value
        val choice = pickOption(
            listOf(
                PickOption(0, if (s.digestShowRead) "Hide read" else "Show read", icon = if (s.digestShowRead) Icons.Rounded.VisibilityOff else Icons.Rounded.Visibility),
                PickOption(1, "Previous digests", icon = Icons.Rounded.History),
                PickOption(2, "Rebuild today's digest", icon = Icons.Rounded.RestartAlt),
                PickOption(3, "Digest settings", icon = Icons.Outlined.Settings),
            ),
            null,
        ) ?: return@launch
        when (choice) {
            0 -> app.settings.setDigestShowRead(!s.digestShowRead)
            1 -> {
                val today = LocalDate.now()
                val picked = pickOption(
                    days.map { d -> PickOption(d.day, historyDayLabel(LocalDate.parse(d.day), today), "${d.items.size} post${if (d.items.size == 1) "" else "s"}") },
                    day ?: app.digest.today(),
                ) ?: return@launch
                day = picked.takeIf { it != app.digest.today() }
            }
            2 -> if (confirmDialog(
                    "Rebuild today's digest?",
                    "Today's digest starts over from the posts on Reddit now. Posts it already showed may not come back.",
                    "Rebuild",
                )
            ) refresh(manual = true, rebuild = true)
            3 -> nav.push(Route.SettingsSection("Digest"))
        }
    }
}

/**
 * A [DigestView] for this screen: while [active] (a tab: selected), builds today's when it's
 * missing or stale, and marks it seen on leaving.
 */
@Composable
fun rememberDigestView(active: Boolean = true): DigestView {
    val nav = LocalNavigator.current
    val scope = rememberCoroutineScope()
    val v = remember { DigestView(scope, nav) }
    v.days = app.digest.store.days.collectAsStateWithLifecycle().value
    v.building = app.digest.building.collectAsStateWithLifecycle().value
    v.readIds = app.history.ids.collectAsStateWithLifecycle().value
    val s = app.settings.state.collectAsStateWithLifecycle().value
    v.showRead = s.digestShowRead
    v.swipeSide = s.digestSwipe
    v.progress = app.digest.progress.collectAsStateWithLifecycle().value
    v.showOverview = s.digestAi && s.digestOverview
    // The AI's order only means something while it's on.
    v.order = DigestOrder.of(s.digestOrder).let { if (it == DigestOrder.AI && !s.digestAi) DigestOrder.NOTABLE else it }
    LaunchedEffect(active) {
        if (!active) return@LaunchedEffect
        v.seenAt.clear() // what was New last time has been seen
        app.digest.refreshIfStale()?.let { v.outcome = it }
    }
    DisposableEffect(active) { onDispose { if (active) app.digest.markSeen() } }
    return v
}

/** The Digest's rows, under whatever header the list has. */
fun LazyListScope.digestRows(v: DigestView) {
    val today = app.digest.today()
    val d = v.days.firstOrNull { it.day == (v.day ?: today) }
    item(key = "digest_head", contentType = "digest_head") { DigestHead(v, d) }
    if (d?.aiFailed == true) item(key = "digest_ai_failed") {
        DigestNote("AI wasn't available; picked by activity")
    }
    d?.overview?.takeIf { v.showOverview }?.let { text ->
        item(key = "digest_overview") { DigestOverview(text) }
    }
    if (d == null) {
        val out = v.outcome
        when {
            out is DigestModule.Outcome.SignedOut -> item(key = "digest_state") {
                DigestMessage("Sign in to get your digest", "It's built from communities you follow.")
            }
            out is DigestModule.Outcome.NoCommunities -> item(key = "digest_state") {
                val nav = LocalNavigator.current
                DigestMessage(
                    "No communities yet",
                    "Star a few favourites in your subscriptions, or choose the communities in Digest settings.",
                    "Choose communities",
                ) { nav.push(Route.SettingsSection("Digest")) }
            }
            out is DigestModule.Outcome.Failed && !v.building -> item(key = "digest_state") {
                ErrorView(out.error, Modifier.height(360.dp), onRetry = { v.refresh(manual = false) })
            }
            else -> items(4, key = { "digest_sk$it" }, contentType = { "skeleton" }) { PostSkeleton() }
        }
        return
    }
    if (d.items.isEmpty()) {
        item(key = "digest_state") {
            DigestMessage("Nothing notable today", "No post stands out in your communities yet. Pull down to check again later.")
        }
        return
    }
    val seenAt = v.seenAt.getOrPut(d.day) { d.seenAt }
    // Read (swiped, or opened and back): gone unless Show read is on.
    val shown = d.items.filter { v.showRead || it.post.id !in v.readIds }
    if (shown.isEmpty()) {
        item(key = "digest_state") {
            DigestMessage("You're all caught up", "You've read everything in this digest.", "Show read") {
                app.settings.setDigestShowRead(true)
            }
        }
        return
    }
    // One list, not a section per community: a digest is read across them.
    val shownIds = shown.mapTo(HashSet()) { it.post.id }
    val items = orderDigest(d.items, v.order).filter { it.post.id in shownIds }
    items(items, key = { "digest_${it.post.id}" }, contentType = { "digest_post" }) { item ->
        DigestCard(v, item, isNew = item.addedAt > d.builtAt && item.addedAt > seenAt)
    }
}

@Composable
private fun DigestHead(v: DigestView, d: DigestDay?) {
    val cs = MaterialTheme.colorScheme
    val label = d?.let { historyDayLabel(LocalDate.parse(it.day), LocalDate.now()) } ?: "Today"
    val detail = when {
        v.building && v.progress != null -> v.progress!!
        d == null -> if (v.building) "Building your digest…" else ""
        v.building -> "Checking for new posts…"
        else -> "Updated ${timeAgoPhrase(d.refreshedAt)}"
    }
    Row(Modifier.fillMaxWidth().padding(start = 14.dp, top = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(label, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            if (detail.isNotEmpty()) Text(detail, fontSize = 12.sp, color = cs.onSurfaceVariant)
        }
        IconButton(onClick = { v.menu() }) { Icon(Icons.Rounded.MoreVert, "Digest menu") }
    }
}

@Composable
private fun DigestCard(v: DigestView, item: DigestItem, isNew: Boolean) {
    val cs = MaterialTheme.colorScheme
    val read = item.post.id in v.readIds
    val tint = cs.primary
    // Settings › Digest › Swipe to mark read: left (the end side), right (the start side) or
    // both; a side it doesn't use keeps the user's own swipe (null).
    val spec = remember(item.post.id, read, v.showRead) {
        if (read) SwipeSpec(Icons.Rounded.RemoveDone, tint) { v.markUnread(item) }
        // Leaving the list (Show read off): it slides all the way out, as a hidden card.
        else SwipeSpec(Icons.Rounded.DoneAll, tint, removes = !v.showRead) { v.markRead(item) }
    }
    Column {
        Row(Modifier.padding(start = 14.dp, end = 14.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            if (isNew) {
                Text(
                    "New",
                    Modifier.background(cs.primaryContainer, RoundedCornerShape(50)).padding(horizontal = 7.dp, vertical = 1.dp),
                    fontSize = 11.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = cs.onPrimaryContainer,
                )
                Spacer(Modifier.width(6.dp))
            } else {
                Icon(Icons.Outlined.Info, null, Modifier.size(13.dp), tint = cs.primary)
                Spacer(Modifier.width(5.dp))
            }
            Text(item.why, fontSize = 12.sp, color = cs.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        PostCard(item.post, swipeOverride = (spec.takeIf { v.swipeSide != 0 }) to (spec.takeIf { v.swipeSide != 1 }))
    }
}

/** The AI's paragraph about the day. */
@Composable
private fun DigestOverview(text: String) {
    val cs = MaterialTheme.colorScheme
    Column(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 4.dp)
            .background(cs.surfaceContainerLow, RoundedCornerShape(28.dp))
            .padding(horizontal = 18.dp, vertical = 14.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Rounded.AutoAwesome, null, Modifier.size(16.dp), tint = cs.primary)
            Spacer(Modifier.width(6.dp))
            Text("Today in your communities", style = MaterialTheme.typography.titleSmall, color = cs.primary)
        }
        Spacer(Modifier.height(6.dp))
        Text(text, style = MaterialTheme.typography.bodyMedium)
    }
}

@Composable
private fun DigestNote(text: String) {
    Row(Modifier.padding(horizontal = 14.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(Icons.Outlined.Info, null, Modifier.size(14.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.width(6.dp))
        Text(text, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun DigestMessage(title: String, text: String, action: String? = null, onAction: (() -> Unit)? = null) {
    Column(
        Modifier.fillMaxWidth().padding(horizontal = 32.dp, vertical = 64.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(title, style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center)
        Spacer(Modifier.height(6.dp))
        Text(text, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
        if (action != null && onAction != null) {
            Spacer(Modifier.height(16.dp))
            Button(onClick = onAction) { Text(action) }
        }
    }
}

/** Today's digest posts not read yet: the count on the Posts chip. */
@Composable
fun rememberDigestUnread(): Int {
    val days by app.digest.store.days.collectAsStateWithLifecycle()
    val read by app.history.ids.collectAsStateWithLifecycle()
    return remember(days, read) {
        days.firstOrNull { it.day == app.digest.today() }?.items?.count { it.post.id !in read } ?: 0
    }
}
