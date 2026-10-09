package com.bennybar.luli_for_reddit.feature.post

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

/** You → Summaries: every post summarized with AI, newest first, with its summary and a link back. */
@Composable
fun SummariesScreen() {
    val cs = MaterialTheme.colorScheme
    val items by app.summaries.items.collectAsStateWithLifecycle()
    var query by rememberSaveable { mutableStateOf("") }
    val shown = remember(items, query) {
        val q = query.trim().lowercase()
        if (q.isEmpty()) items
        else items.filter { q in it.title.lowercase() || q in it.subreddit.lowercase() || q in it.text.lowercase() }
    }

    Scaffold(topBar = { BloomTopBar("Summaries") }, containerColor = cs.surface) { padding ->
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
                    items(shown, key = { it.postId }) { SummaryCard(it) }
                }
            }
        }
    }
}

@Composable
private fun SummaryCard(s: SavedSummary) {
    val cs = MaterialTheme.colorScheme
    val nav = LocalNavigator.current
    var expanded by rememberSaveable(s.postId) { mutableStateOf(false) }
    fun open() {
        val route = if (s.permalink.isNotEmpty()) routeForRedditUrl(Uri.parse("https://reddit.com${s.permalink}"))
        else Route.Post(s.subreddit.ifEmpty { "_" }, s.postId)
        route?.let(nav::push)
    }
    Surface(shape = RoundedCornerShape(28.dp), color = cs.surfaceContainerLow) {
        Column(Modifier.padding(start = 16.dp, top = 12.dp, end = 8.dp, bottom = 8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
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
                IconButton(onClick = { copyToClipboard(s.text) }, Modifier.size(36.dp)) {
                    Icon(Icons.Rounded.ContentCopy, "Copy summary", Modifier.size(18.dp))
                }
                IconButton(onClick = { app.summaries.remove(s.postId) }, Modifier.size(36.dp)) {
                    Icon(Icons.Rounded.DeleteOutline, "Remove", Modifier.size(18.dp))
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
