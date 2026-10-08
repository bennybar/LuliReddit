package com.bennybar.luli_for_reddit.feature.feed

import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
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
import androidx.compose.material3.Scaffold
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

    val subs = remember(history) { history.map { it.subreddit }.toSortedSet().toList() }
    // Keep the chosen filter valid if its subreddit dropped out of history.
    val subFilter = subFilterRaw?.takeIf { it in subs }
    val filtered = remember(history, query, subFilter) {
        val q = query.trim().lowercase()
        history.filter {
            (subFilter == null || it.subreddit == subFilter) &&
                (q.isEmpty() || it.title.lowercase().contains(q) || it.subreddit.lowercase().contains(q))
        }
    }

    Scaffold(
        topBar = {
            BloomTopBar(
                "History",
                actions = {
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
                                    DropdownMenuItem(text = { Text("r/$s") }, onClick = {
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
                                })
                                DropdownMenuItem(text = { Text("Clear older than 30 days") }, onClick = {
                                    clearOpen = false
                                    app.history.clearOlderThan(30 * DAY)
                                })
                                DropdownMenuItem(text = { Text("Clear all history") }, onClick = {
                                    clearOpen = false
                                    app.history.clear()
                                    app.threadVisits.clear()
                                })
                            }
                        }
                    }
                },
            )
        },
        containerColor = cs.surface,
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(top = padding.calculateTopPadding())) {
            Text(
                "Recently viewed posts are stored only on this device — Reddit does not sync viewing history to third-party apps.",
                Modifier.fillMaxWidth().background(cs.surfaceContainerHigh).padding(12.dp),
                fontSize = 12.sp,
                color = cs.onSurfaceVariant,
            )
            if (history.isNotEmpty()) {
                PillTextField(
                    value = query,
                    onValueChange = { query = it },
                    placeholder = "Search history",
                    modifier = Modifier.fillMaxWidth().padding(start = 12.dp, top = 10.dp, end = 12.dp, bottom = 4.dp),
                )
            }
            when {
                history.isEmpty() -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Text("No history yet") }
                filtered.isEmpty() -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Text("No matches") }
                else -> LazyColumn(Modifier.fillMaxSize()) {
                    items(filtered, key = { it.id }) { e ->
                        Tile(
                            title = { Text(e.title, maxLines = 2, overflow = TextOverflow.Ellipsis) },
                            subtitle = { Text("r/${e.subreddit}") },
                            trailing = {
                                IconButton(onClick = { app.history.removeViewed(e.id) }) {
                                    Icon(Icons.Rounded.Close, "Remove", Modifier.size(18.dp))
                                }
                            },
                            modifier = Modifier.clickable {
                                val route = if (e.permalink.isNotEmpty()) {
                                    routeForRedditUrl(Uri.parse("https://reddit.com${e.permalink}"))
                                } else {
                                    Route.Post(e.subreddit.ifEmpty { "_" }, e.id)
                                }
                                route?.let(nav::push)
                            },
                        )
                    }
                }
            }
        }
    }
}

private const val DAY = 24 * 60 * 60 * 1000L
