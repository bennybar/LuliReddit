package com.bennybar.luli_for_reddit.feature.feed

import kotlinx.coroutines.launch
import androidx.compose.material.icons.rounded.BookmarkRemove
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
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ModeComment
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.core.compactNumber
import com.bennybar.luli_for_reddit.feature.markdown.RedditMarkdown
import com.bennybar.luli_for_reddit.model.Comment
import com.bennybar.luli_for_reddit.model.Post
import com.bennybar.luli_for_reddit.nav.LocalNavigator
import com.bennybar.luli_for_reddit.ui.friendlyError
import kotlinx.coroutines.flow.distinctUntilChanged

/**
 * A dedicated, searchable hub for the user's Saved items, with a type filter
 * (all / posts / comments) and live text search over what's loaded.
 */
@Composable
fun SavedScreen() {
    val cs = MaterialTheme.colorScheme
    val username = app.session.username
    val source = rememberPagedSource<Any>("saved_hub_$username") { a -> app.repository.getUserSaved(username, after = a) }
    val state by source.state.collectAsStateWithLifecycle()
    var query by rememberSaveable { mutableStateOf("") }
    var type by rememberSaveable { mutableStateOf("all") } // all | posts | comments

    // Unsaved here (swipe either way): gone from the list at once, Undo restores.
    var removed by remember { mutableStateOf(emptySet<String>()) }
    val unsaveColor = cs.tertiary
    fun unsave(fullname: String, post: Post?) {
        removed = removed + fullname
        post?.let { app.postOverrides.setSaved(it, false) }
        app.scope.launch {
            try {
                app.repository.setSaved(fullname, false)
                app.navigator.showSnackbar("Removed from Saved", actionLabel = "Undo") {
                    removed = removed - fullname
                    post?.let { app.postOverrides.setSaved(it, true) }
                    app.scope.launch { runCatching { app.repository.setSaved(fullname, true) } }
                }
            } catch (e: Exception) {
                removed = removed - fullname
                post?.let { app.postOverrides.setSaved(it, true) }
                app.navigator.showActionError("unsave", e)
            }
        }
    }

    val filtered = remember(state.items, query, type, removed) {
        val q = query.trim().lowercase()
        state.items.filter {
            (if (it is Post) it.fullname else (it as Comment).fullname) !in removed &&
            (type == "all" || (type == "posts" && it is Post) || (type == "comments" && it is Comment)) &&
                (q.isEmpty() || (it is Post && it.title.lowercase().contains(q)) || (it is Comment && it.body.lowercase().contains(q)))
        }.distinctBy { if (it is Post) it.fullname else (it as Comment).fullname }
    }

    Scaffold(topBar = { BloomTopBar("Saved") }, containerColor = cs.surface) { padding ->
        Column(Modifier.fillMaxSize().padding(top = padding.calculateTopPadding())) {
            PillTextField(
                value = query,
                onValueChange = { query = it },
                placeholder = "Search saved",
                modifier = Modifier.fillMaxWidth().padding(start = 12.dp, top = 10.dp, end = 12.dp, bottom = 4.dp),
            )
            LazyRow(contentPadding = PaddingValues(horizontal = 12.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                items(listOf("all" to "All", "posts" to "Posts", "comments" to "Comments"), key = { it.first }) { (k, label) ->
                    FilterChip(
                        selected = type == k,
                        onClick = { type = k },
                        label = { Text(label) },
                        shape = CircleShape,
                        border = null,
                        colors = FilterChipDefaults.filterChipColors(containerColor = cs.surfaceContainerHigh),
                    )
                }
            }
            Box(Modifier.weight(1f)) {
                when {
                    state.loading && state.items.isEmpty() -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator()
                    }
                    state.error != null -> Column(
                        Modifier.fillMaxSize().padding(32.dp),
                        verticalArrangement = Arrangement.Center,
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        Text("Could not load saved.\n${friendlyError(state.error)}", textAlign = TextAlign.Center)
                        Spacer(Modifier.height(12.dp))
                        Button(onClick = { source.load() }) { Text("Retry") }
                    }
                    filtered.isEmpty() -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Text(if (state.items.isEmpty() || (query.isBlank() && type == "all")) "Nothing saved" else "No matches")
                    }
                    else -> {
                        val listState = rememberLazyListState()
                        LaunchedEffect(listState, source) {
                            snapshotFlow {
                                val info = listState.layoutInfo
                                (info.visibleItemsInfo.lastOrNull()?.index ?: 0) >= info.totalItemsCount - 4
                            }.distinctUntilChanged().collect { if (it) source.loadMore() }
                        }
                        LazyColumn(
                            Modifier.fillMaxSize(),
                            state = listState,
                            contentPadding = PaddingValues(start = 10.dp, top = 8.dp, end = 10.dp, bottom = 32.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            items(
                                filtered,
                                key = { if (it is Post) it.fullname else (it as Comment).fullname },
                                contentType = { if (it is Post) "post" else "comment" },
                            ) { item ->
                                if (item is Post) {
                                    val spec = remember(item.fullname) { SwipeSpec(Icons.Rounded.BookmarkRemove, unsaveColor) { unsave(item.fullname, item) } }
                                    PostCard(item, swipeOverride = spec to spec)
                                } else {
                                    val c = item as Comment
                                    val spec = remember(c.fullname) { SwipeSpec(Icons.Rounded.BookmarkRemove, unsaveColor) { unsave(c.fullname, null) } }
                                    SwipeActions(start = spec, end = spec) { SavedComment(c) }
                                }
                            }
                            item(key = "__footer") {
                                if (state.loadingMore) {
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
    }
}

@Composable
private fun SavedComment(comment: Comment) {
    val cs = MaterialTheme.colorScheme
    val nav = LocalNavigator.current
    BloomCard(
        Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        onClick = { openPermalink(nav, comment.permalink) },
    ) {
        Column(Modifier.padding(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Outlined.ModeComment, null, Modifier.size(14.dp), tint = cs.primary)
                Spacer(Modifier.width(6.dp))
                Text(
                    "r/${comment.subreddit} · u/${comment.author} · ${compactNumber(comment.score)}",
                    Modifier.weight(1f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    fontSize = 12.sp,
                    color = cs.onSurfaceVariant,
                )
            }
            Spacer(Modifier.height(6.dp))
            RedditMarkdown(comment.body, onLinkClick = { nav.openLink(it) })
        }
    }
}
