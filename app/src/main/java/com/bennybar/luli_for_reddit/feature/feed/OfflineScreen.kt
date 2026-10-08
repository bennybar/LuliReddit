package com.bennybar.luli_for_reddit.feature.feed

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.DeleteOutline
import androidx.compose.material.icons.rounded.OfflinePin
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.core.timeAgo
import com.bennybar.luli_for_reddit.nav.LocalNavigator
import com.bennybar.luli_for_reddit.nav.Route
import com.bennybar.luli_for_reddit.state.OfflineThread
import kotlinx.coroutines.launch

/**
 * "Read later": threads saved for offline reading. Opening one loads it live
 * when online and from the saved copy when not. Swipe to remove.
 */
@Composable
fun OfflineScreen() {
    val cs = MaterialTheme.colorScheme
    val threads by app.offline.state.collectAsStateWithLifecycle()
    Scaffold(topBar = { BloomTopBar("Read later") }, containerColor = cs.surface) { padding ->
        Box(Modifier.fillMaxSize().padding(top = padding.calculateTopPadding())) {
            if (threads.isEmpty()) {
                Box(Modifier.fillMaxSize().padding(32.dp), contentAlignment = Alignment.Center) {
                    Text(
                        "Nothing saved yet. Use \"Save for offline\" in a post's ⋯ menu to keep it, with its comments, " +
                            "for reading without a connection.",
                        textAlign = TextAlign.Center,
                        color = cs.onSurfaceVariant,
                    )
                }
            } else {
                LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 130.dp)) {
                    items(threads, key = { it.id }) { t -> OfflineRow(t) }
                }
            }
        }
    }
}

@Composable
private fun OfflineRow(t: OfflineThread) {
    val cs = MaterialTheme.colorScheme
    val nav = LocalNavigator.current
    val scope = rememberCoroutineScope()
    val dismiss = rememberSwipeToDismissBoxState()
    SwipeToDismissBox(
        state = dismiss,
        enableDismissFromStartToEnd = false,
        onDismiss = { value ->
            if (value == SwipeToDismissBoxValue.EndToStart) scope.launch { app.offline.remove(t.id) }
        },
        backgroundContent = {
            Box(
                Modifier.fillMaxSize().background(cs.errorContainer).padding(horizontal = 24.dp),
                contentAlignment = Alignment.CenterEnd,
            ) { Icon(Icons.Rounded.DeleteOutline, "Remove", tint = cs.onErrorContainer) }
        },
    ) {
        Tile(
            title = { Text(t.title, maxLines = 2, overflow = TextOverflow.Ellipsis) },
            subtitle = { Text("r/${t.subreddit} · saved ${timeAgo(t.savedAt)}") },
            leading = { Icon(Icons.Rounded.OfflinePin, null) },
            modifier = Modifier.background(cs.surface),
            onClick = { nav.push(Route.Post(t.subreddit.ifEmpty { "_" }, t.id)) },
        )
    }
}
