package com.bennybar.luli_for_reddit.feature.post

import kotlinx.coroutines.launch
import com.bennybar.luli_for_reddit.feature.settings.confirmDialog
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.material3.Checkbox
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Checklist
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.activity.compose.BackHandler
import android.net.Uri
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.OpenInNew
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.ContentCopy
import androidx.compose.material.icons.rounded.DeleteOutline
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.core.routeForRedditUrl
import com.bennybar.luli_for_reddit.core.timeAgo
import com.bennybar.luli_for_reddit.feature.feed.BloomTopBar
import com.bennybar.luli_for_reddit.feature.feed.PillTextField
import com.bennybar.luli_for_reddit.feature.markdown.RedditMarkdown
import com.bennybar.luli_for_reddit.nav.LocalNavigator
import com.bennybar.luli_for_reddit.nav.Route
import com.bennybar.luli_for_reddit.state.SavedSummary

/**
 * Profile → Summaries: every post summarized with AI, newest first, with its
 * summary and a link back. Select (or long-press one) to delete several, or all.
 */
@Composable
fun SummariesScreen() {
    val cs = MaterialTheme.colorScheme
    val scope = rememberCoroutineScope()
    val items by app.summaries.items.collectAsStateWithLifecycle()
    var query by rememberSaveable { mutableStateOf("") }
    val shown = remember(items, query) {
        val q = query.trim().lowercase()
        if (q.isEmpty()) items
        else items.filter { q in it.title.lowercase() || q in it.subreddit.lowercase() || q in it.text.lowercase() }
    }
    // Selection mode: null = off; otherwise the selected post ids.
    var selected by rememberSaveable { mutableStateOf<List<String>?>(null) }
    val selecting = selected != null
    BackHandler(enabled = selecting) { selected = null }
    fun toggle(id: String) {
        val cur = selected.orEmpty()
        selected = if (id in cur) cur - id else cur + id
    }
    val allShown = shown.isNotEmpty() && shown.all { it.postId in selected.orEmpty() }

    Scaffold(
        topBar = {
            if (selecting) {
                BloomTopBar(
                    "",
                    showBack = false,
                    titleContent = {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            IconButton(onClick = { selected = null }) { Icon(Icons.Rounded.Close, "Cancel selection") }
                            Text("${selected.orEmpty().size} selected", style = MaterialTheme.typography.titleLarge)
                        }
                    },
                    actions = {
                        TextButton(onClick = { selected = if (allShown) emptyList() else shown.map { it.postId } }) {
                            Text(if (allShown) "Select none" else "Select all")
                        }
                        IconButton(
                            onClick = {
                                val ids = selected.orEmpty().toSet()
                                scope.launch {
                                    val n = ids.size
                                    if (confirmDialog(
                                            if (n == 1) "Delete this summary?" else "Delete $n summaries?",
                                            "They're removed from this device. The posts stay on Reddit.",
                                            "Delete",
                                        )
                                    ) {
                                        app.summaries.removeAll(ids)
                                        selected = null
                                    }
                                }
                            },
                            enabled = selected.orEmpty().isNotEmpty(),
                        ) { Icon(Icons.Rounded.DeleteOutline, "Delete selected") }
                    },
                )
            } else {
                BloomTopBar("Summaries", actions = {
                    if (items.isNotEmpty()) {
                        IconButton(onClick = { selected = emptyList() }) { Icon(Icons.Rounded.Checklist, "Select") }
                    }
                })
            }
        },
        containerColor = cs.surface,
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(top = padding.calculateTopPadding())) {
            if (items.size > 3) {
                PillTextField(
                    value = query,
                    onValueChange = { query = it },
                    placeholder = "Search summaries",
                    modifier = Modifier.fillMaxWidth().padding(start = 12.dp, top = 8.dp, end = 12.dp, bottom = 4.dp),
                )
            }
            when {
                items.isEmpty() -> Box(Modifier.fillMaxSize().padding(32.dp), contentAlignment = Alignment.Center) {
                    Text(
                        "No summaries yet. Summarize a thread with the ✦ button in a post and it's kept here.",
                        textAlign = TextAlign.Center,
                        color = cs.onSurfaceVariant,
                    )
                }
                shown.isEmpty() -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Text("No matches") }
                else -> LazyColumn(
                    Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(start = 12.dp, top = 8.dp, end = 12.dp, bottom = 32.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    items(shown, key = { it.postId }) { s ->
                        SummaryCard(
                            s,
                            selected = if (selecting) s.postId in selected.orEmpty() else null,
                            onToggle = { toggle(s.postId) },
                            onLongPress = { if (!selecting) selected = listOf(s.postId) },
                        )
                    }
                }
            }
        }
    }
}

/** [selected]: null outside selection mode; then a tap toggles the card ([onToggle]). */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun SummaryCard(s: SavedSummary, selected: Boolean?, onToggle: () -> Unit, onLongPress: () -> Unit) {
    val cs = MaterialTheme.colorScheme
    val nav = LocalNavigator.current
    var expanded by rememberSaveable(s.postId) { mutableStateOf(false) }
    fun open() {
        val route = if (s.permalink.isNotEmpty()) routeForRedditUrl(Uri.parse("https://reddit.com${s.permalink}"))
        else Route.Post(s.subreddit.ifEmpty { "_" }, s.postId)
        route?.let(nav::push)
    }
    Surface(
        Modifier.combinedClickable(onLongClick = onLongPress, onClick = { if (selected != null) onToggle() }),
        shape = RoundedCornerShape(28.dp),
        color = if (selected == true) cs.secondaryContainer else cs.surfaceContainerLow,
    ) {
        Column(Modifier.padding(start = 16.dp, top = 12.dp, end = 8.dp, bottom = 8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (selected != null) {
                    Checkbox(checked = selected, onCheckedChange = { onToggle() }, Modifier.size(32.dp))
                    Spacer(Modifier.width(6.dp))
                }
                Icon(Icons.Rounded.AutoAwesome, null, Modifier.size(14.dp), tint = cs.primary)
                Spacer(Modifier.width(6.dp))
                Text(
                    "r/${s.subreddit} · ${s.style} · ${timeAgo(s.createdAt)}",
                    Modifier.weight(1f),
                    fontSize = 12.sp,
                    color = cs.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                if (selected == null) {
                    IconButton(onClick = { copyToClipboard(s.text) }, Modifier.size(36.dp)) {
                        Icon(Icons.Rounded.ContentCopy, "Copy summary", Modifier.size(18.dp))
                    }
                    IconButton(onClick = { app.summaries.remove(s.postId) }, Modifier.size(36.dp)) {
                        Icon(Icons.Rounded.DeleteOutline, "Remove", Modifier.size(18.dp))
                    }
                }
            }
            Text(
                s.title,
                Modifier.padding(end = 8.dp, top = 2.dp).clickable(onClick = ::open),
                fontSize = 17.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 3,
                overflow = TextOverflow.Ellipsis,
            )
            RedditMarkdown(
                s.text,
                Modifier.padding(top = 8.dp, end = 8.dp).clickable { expanded = !expanded },
                fontSize = 14.sp,
                maxLines = if (expanded) Int.MAX_VALUE else 6,
                selectable = expanded,
            )
            Row(verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = { expanded = !expanded }) { Text(if (expanded) "Show less" else "Full summary") }
                Spacer(Modifier.weight(1f))
                TextButton(onClick = ::open) {
                    Text("Open post")
                    Spacer(Modifier.width(6.dp))
                    Icon(Icons.AutoMirrored.Rounded.OpenInNew, null, Modifier.size(16.dp))
                }
            }
        }
    }
}
