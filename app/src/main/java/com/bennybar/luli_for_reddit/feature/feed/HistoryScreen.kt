package com.bennybar.luli_for_reddit.feature.feed

import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.animateFloatAsState
import com.bennybar.luli_for_reddit.ui.subredditName
import android.net.Uri
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.rounded.Check
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalDensity
import com.bennybar.luli_for_reddit.core.timeAgo
import com.bennybar.luli_for_reddit.state.HistoryEntry
import com.bennybar.luli_for_reddit.ui.SearchIcon
import kotlinx.coroutines.launch
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.DeleteOutline
import androidx.compose.material.icons.rounded.FilterAlt
import androidx.compose.material.icons.rounded.FilterList
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.core.routeForRedditUrl
import com.bennybar.luli_for_reddit.nav.LocalNavigator
import com.bennybar.luli_for_reddit.nav.Route

/** Recently viewed posts (on-device only), searchable and filterable by subreddit. */
@Composable
fun HistoryScreen() {
    val cs = MaterialTheme.colorScheme
    val nav = LocalNavigator.current
    val history by app.history.state.collectAsStateWithLifecycle()
    var query by rememberSaveable { mutableStateOf("") }
    var subFilterRaw by rememberSaveable { mutableStateOf<String?>(null) } // null = all subreddits
    var filterOpen by remember { mutableStateOf(false) }
    var clearOpen by remember { mutableStateOf(false) }

    // "Hide NSFW posts" (Content filters) covers History too; entries from before it
    // was recorded have no flag and stay shown.
    val hideNsfw = app.contentFilters.state.collectAsStateWithLifecycle().value.hideNsfw
    val visible = remember(history, hideNsfw) { if (hideNsfw) history.filter { !it.nsfw } else history }
    val subs = remember(visible) { visible.map { it.subreddit }.toSortedSet().toList() }
    // Keep the chosen filter valid if its subreddit dropped out of history.
    val subFilter = subFilterRaw?.takeIf { it in subs }
    val filtered = remember(visible, query, subFilter) {
        val q = query.trim().lowercase()
        visible.filter {
            (subFilter == null || it.subreddit == subFilter) &&
                (q.isEmpty() || it.title.lowercase().contains(q) || it.subreddit.lowercase().contains(q))
        }
    }

    // Laid out like Saved and a subreddit (#142, #143): the top bar hides as you
    // scroll, the list runs under a faded status bar, and the search field
    // scrolls away (the bar's 🔍 brings it back). Rows sit in one connected
    // container, Gmail-like (#142); swipe one to the left to remove it.
    val scope = rememberCoroutineScope()
    val listState = rememberLazyListState()
    val bar = rememberHidingBar(listState)
    val focus = remember { FocusRequester() }
    var noteShown by remember { mutableStateOf(app.prefs.getBool("historyNoteDismissed") != true) } // closed once, gone for good (#119)
    val searchGone by remember(listState) { derivedStateOf { listState.layoutInfo.visibleItemsInfo.none { it.key == "search" } && listState.layoutInfo.totalItemsCount > 0 } }
    val removeColor = cs.error
    // The day each entry was read, in order (#159); legacy entries with no time come last.
    val today = remember { LocalDate.now() }
    val days = remember(filtered) {
        filtered.groupBy { e -> if (e.viewedAt > 0) Instant.ofEpochMilli(e.viewedAt).atZone(ZoneId.systemDefault()).toLocalDate() else null }
    }
    // Gmail's selection (#155): tapping a row's picture selects it, then a tap on a row
    // adds or drops it, and the bar deletes them all (Undo puts them back).
    var selected by remember { mutableStateOf(emptySet<String>()) }
    val selecting = selected.isNotEmpty()
    BackHandler(selecting) { selected = emptySet() }
    fun toggle(id: String) { selected = if (id in selected) selected - id else selected + id }
    // Each community's picture (#155): saved with what's read since this version;
    // older entries borrow it from a newer one, Recently visited or your subscriptions.
    val recentSubs by app.recentSubreddits.state.collectAsStateWithLifecycle()
    val icons = remember(history, recentSubs) {
        buildMap {
            for (s in app.repository.loadedSubscriptions.orEmpty()) s.iconUrl?.let { put(s.name.lowercase(), it) }
            for (r in recentSubs) r.iconUrl?.let { put(r.name.lowercase(), it) }
            for (h in history.asReversed()) h.icon?.let { put(h.subreddit.lowercase(), it) }
        }
    }

    Box(Modifier.fillMaxSize().background(cs.surface).clipToBounds().nestedScroll(bar)) {
        LazyColumn(
            Modifier.fillMaxSize(),
            state = listState,
            contentPadding = PaddingValues(top = with(LocalDensity.current) { bar.height.toDp() }, bottom = 32.dp),
        ) {
            if (noteShown) item(key = "note") {
                Row(
                    Modifier
                        .fillMaxWidth()
                        .padding(start = 16.dp, top = 4.dp, end = 16.dp, bottom = 4.dp)
                        .clip(RoundedCornerShape(20.dp))
                        .background(cs.surfaceContainerHigh)
                        .padding(start = 16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        "Recently viewed posts are stored only on this device — Reddit does not sync viewing history to third-party apps.",
                        Modifier.weight(1f).padding(vertical = 12.dp),
                        fontSize = 12.sp,
                        color = cs.onSurfaceVariant,
                    )
                    IconButton(onClick = { noteShown = false; app.prefs.setBool("historyNoteDismissed", true) }) {
                        Icon(Icons.Rounded.Close, "Close", tint = cs.onSurfaceVariant)
                    }
                }
            }
            if (visible.isNotEmpty()) item(key = "search") {
                PillTextField(
                    value = query,
                    onValueChange = { query = it },
                    placeholder = "Search history",
                    modifier = Modifier.fillMaxWidth().padding(start = 12.dp, top = 4.dp, end = 12.dp, bottom = 12.dp).focusRequester(focus),
                )
            }
            val empty = when {
                history.isEmpty() -> "No history yet"
                visible.isEmpty() -> "NSFW posts are hidden"
                filtered.isEmpty() -> "No matches"
                else -> null
            }
            if (empty != null) item(key = "empty") {
                Box(Modifier.fillParentMaxWidth().fillParentMaxHeight(0.6f), contentAlignment = Alignment.Center) { Text(empty) }
            }
            // A connected container a day, under its date (#159).
            for ((day, entries) in days) {
                item(key = "day_$day", contentType = "day") {
                    Text(
                        historyDayLabel(day, today),
                        Modifier.animateItem().padding(start = 28.dp, top = 12.dp, end = 16.dp, bottom = 8.dp),
                        style = MaterialTheme.typography.titleSmall,
                        color = cs.primary,
                    )
                }
                itemsIndexed(entries, key = { _, e -> e.id }) { i, e ->
                    // A row's outer corners are round only where the container starts or ends, as in Settings.
                    val top = if (i == 0) 24.dp else 4.dp
                    val bottom = if (i == entries.lastIndex) 24.dp else 4.dp
                    val spec = remember(e.id) { SwipeSpec(Icons.Rounded.DeleteOutline, removeColor) {
                        app.history.removeViewed(e.id)
                        // Swiped by accident: Undo puts it back (#154).
                        nav.showSnackbar("Removed from History", actionLabel = "Undo") { app.history.restore(e) }
                    } }
                    Box(
                        Modifier
                            .animateItem()
                            .padding(start = 16.dp, end = 16.dp, bottom = 2.dp)
                            .clip(RoundedCornerShape(top, top, bottom, bottom)),
                    ) {
                        SwipeActions(start = null, end = spec, enabled = !selecting) {
                            HistoryRow(
                                e,
                                icon = icons[e.subreddit.lowercase()],
                                selected = e.id in selected,
                                onSelect = { toggle(e.id) },
                                onSubreddit = { if (selecting) toggle(e.id) else if (e.subreddit.isNotEmpty()) nav.openSubreddit(e.subreddit) },
                            ) {
                                if (selecting) {
                                    toggle(e.id)
                                    return@HistoryRow
                                }
                                val route = if (e.permalink.isNotEmpty()) {
                                    routeForRedditUrl(Uri.parse("https://reddit.com${e.permalink}"))
                                } else {
                                    Route.Post(e.subreddit.ifEmpty { "_" }, e.id)
                                }
                                route?.let(nav::push)
                            }
                        }
                    }
                }
            }
        }
        HidingTopBar(bar) {
            if (selecting) BloomTopBar(
                "",
                showBack = false,
                titleContent = {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        IconButton(onClick = { selected = emptySet() }) { Icon(Icons.Rounded.Close, "Cancel selection") }
                        Spacer(Modifier.width(4.dp))
                        Text("${selected.size} selected")
                    }
                },
                actions = {
                    IconButton(onClick = {
                        val gone = history.filter { it.id in selected }
                        selected = emptySet()
                        gone.forEach { app.history.removeViewed(it.id) }
                        nav.showSnackbar("Removed ${gone.size} from History", actionLabel = "Undo") { gone.forEach(app.history::restore) }
                    }) { Icon(Icons.Rounded.DeleteOutline, "Remove from History") }
                },
            ) else BloomTopBar(
                "History",
                actions = {
                    if (searchGone && visible.isNotEmpty()) IconButton(onClick = {
                        scope.launch {
                            listState.animateScrollToItem(0)
                            bar.slide(0f)
                            focus.requestFocus()
                        }
                    }) { Icon(SearchIcon, "Search history") }
                        if (subs.isNotEmpty()) {
                            Box {
                                IconButton(onClick = { filterOpen = true }) {
                                    Icon(if (subFilter == null) Icons.Rounded.FilterList else Icons.Rounded.FilterAlt, "Filter by subreddit")
                                }
                                DropdownMenu(filterOpen, onDismissRequest = { filterOpen = false }) {
                                    DropdownMenuItem(text = { Text("All subreddits") }, onClick = {
                                        filterOpen = false
                                        subFilterRaw = null
                                    })
                                    for (s in subs) {
                                        DropdownMenuItem(text = { Text(subredditName(s)) }, onClick = {
                                            filterOpen = false
                                            subFilterRaw = s
                                        })
                                    }
                                }
                            }
                        }
                        if (history.isNotEmpty()) {
                            Box {
                                IconButton(onClick = { clearOpen = true }) { Icon(Icons.Rounded.DeleteOutline, "Clear history") }
                                DropdownMenu(clearOpen, onDismissRequest = { clearOpen = false }) {
                                    DropdownMenuItem(text = { Text("Clear older than 7 days") }, onClick = {
                                        clearOpen = false
                                        app.history.clearOlderThan(7 * DAY)
                                        app.recentSubreddits.clearOlderThan(7 * DAY)
                                    })
                                    DropdownMenuItem(text = { Text("Clear older than 30 days") }, onClick = {
                                        clearOpen = false
                                        app.history.clearOlderThan(30 * DAY)
                                        app.recentSubreddits.clearOlderThan(30 * DAY)
                                    })
                                    DropdownMenuItem(text = { Text("Clear all history") }, onClick = {
                                        clearOpen = false
                                        app.history.clear()
                                        app.recentSubreddits.clear()
                                        app.threadVisits.clear()
                                    })
                                }
                            }
                        }
                },
            )
        }
    }
}

/**
 * A History row, Gmail-like: the community's picture (a tap selects the row, #155),
 * then the community (a tap opens it) and when, over the title.
 */
@Composable
private fun HistoryRow(
    e: HistoryEntry,
    icon: String?,
    selected: Boolean,
    onSelect: () -> Unit,
    onSubreddit: () -> Unit,
    onClick: () -> Unit,
) {
    val cs = MaterialTheme.colorScheme
    Row(
        Modifier
            .fillMaxWidth()
            .background(if (selected) cs.secondaryContainer else cs.surfaceContainerLow)
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // Selecting flips the picture over to a tick, like Gmail (#163).
        val flip by animateFloatAsState(if (selected) 180f else 0f, tween(300), label = "flip")
        Box(
            Modifier
                .size(40.dp)
                .graphicsLayer {
                    rotationY = flip
                    cameraDistance = 12f * density
                }
                .clip(CircleShape)
                .clickable(onClickLabel = if (selected) "Unselect" else "Select", onClick = onSelect),
            contentAlignment = Alignment.Center,
        ) {
            // Both faces stay put (the picture doesn't reload on the way back); the turn
            // shows whichever faces you.
            LetterAvatar(
                e.subreddit.ifEmpty { "?" }, 40.dp, cs.secondaryContainer, cs.onSecondaryContainer,
                Modifier.graphicsLayer { alpha = if (flip > 90f) 0f else 1f },
                imageUrl = icon,
            )
            // The back face, turned again so the tick doesn't read mirrored.
            Box(
                Modifier.fillMaxSize().graphicsLayer {
                    rotationY = 180f
                    alpha = if (flip > 90f) 1f else 0f
                }.background(cs.primary),
                contentAlignment = Alignment.Center,
            ) { Icon(Icons.Rounded.Check, null, tint = cs.onPrimary) }
        }
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.weight(1f)) {
                    Text(
                        subredditName(e.subreddit),
                        Modifier.clip(RoundedCornerShape(6.dp)).clickable(onClickLabel = "Open community", onClick = onSubreddit),
                        style = MaterialTheme.typography.labelLarge,
                        fontWeight = FontWeight.SemiBold,
                        color = cs.primary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                if (e.viewedAt > 0) Text(timeAgo(e.viewedAt), style = MaterialTheme.typography.labelMedium, color = cs.onSurfaceVariant)
            }
            Spacer(Modifier.height(2.dp))
            Text(e.title, style = MaterialTheme.typography.bodyLarge, maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
    }
}

/** A History day's header (#159): Today, Yesterday, the weekday within a week, then the date. */
internal fun historyDayLabel(day: LocalDate?, today: LocalDate, locale: Locale = Locale.getDefault()): String = when {
    day == null -> "Earlier"
    day == today -> "Today"
    day == today.minusDays(1) -> "Yesterday"
    day.isAfter(today.minusDays(7)) && !day.isAfter(today) -> day.format(DateTimeFormatter.ofPattern("EEEE", locale))
    day.year == today.year -> day.format(DateTimeFormatter.ofPattern("EEE, MMM d", locale))
    else -> day.format(DateTimeFormatter.ofPattern("MMM d, yyyy", locale))
}

private const val DAY = 24 * 60 * 60 * 1000L
