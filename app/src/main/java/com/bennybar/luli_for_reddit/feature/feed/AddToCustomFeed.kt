package com.bennybar.luli_for_reddit.feature.feed

import androidx.compose.material3.LocalContentColor
import com.bennybar.luli_for_reddit.ui.Loading
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.DynamicFeed
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.feature.home.createMulti
import com.bennybar.luli_for_reddit.model.Multireddit
import com.bennybar.luli_for_reddit.ui.Overlays
import com.bennybar.luli_for_reddit.ui.friendlyError
import kotlinx.coroutines.launch

/**
 * Add r/[subreddit] to one of your custom feeds (or take it out): your feeds,
 * ticked where it's already in (so it can't be added twice), and New feed,
 * which starts one with it. From a post's ⋮ menu and a community's top bar.
 */
@OptIn(ExperimentalMaterial3Api::class)
suspend fun showAddToCustomFeed(subreddit: String) {
    Overlays.show<Unit> { done ->
        val cs = MaterialTheme.colorScheme
        val scope = rememberCoroutineScope()
        val multis by app.feed.multireddits.collectAsStateWithLifecycle()
        LaunchedEffect(Unit) { app.feed.loadMultireddits() }
        // The feed being changed right now (its row shows a spinner).
        var busy by remember { mutableStateOf<String?>(null) }

        fun contains(m: Multireddit) = m.subreddits.any { it.equals(subreddit, ignoreCase = true) }

        fun toggle(m: Multireddit) {
            if (busy != null) return
            busy = m.path
            val add = !contains(m)
            scope.launch {
                try {
                    if (add) app.repository.addSubredditToMulti(m.path.trimEnd('/'), subreddit)
                    else app.repository.removeSubredditFromMulti(m.path.trimEnd('/'), subreddit)
                    app.feed.loadMultireddits(force = true)
                    app.navigatorOrNull?.showSnackbar(
                        if (add) "Added r/$subreddit to ${m.displayName}" else "Removed r/$subreddit from ${m.displayName}",
                    )
                } catch (e: Exception) {
                    app.navigatorOrNull?.showSnackbar("Couldn't change ${m.displayName}: ${friendlyError(e)}")
                } finally {
                    busy = null
                }
            }
        }

        ModalBottomSheet(onDismissRequest = { done(null) }) {
            Column(Modifier.navigationBarsPadding().verticalScroll(rememberScrollState()).padding(bottom = 8.dp)) {
                Text(
                    "Add r/$subreddit to a custom feed",
                    Modifier.padding(start = 20.dp, top = 4.dp, end = 20.dp, bottom = 8.dp),
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Bold,
                )
                when (val m = multis) {
                    Async.Loading -> Box(Modifier.fillMaxWidth().padding(16.dp), contentAlignment = Alignment.Center) {
                        Loading()
                    }
                    is Async.Error -> Text(
                        "Couldn't load your custom feeds: ${friendlyError(m.error)}",
                        Modifier.padding(horizontal = 20.dp, vertical = 8.dp),
                    )
                    is Async.Data -> for (multi in m.value) {
                        val inIt = contains(multi)
                        Tile(
                            title = { Text(multi.displayName) },
                            subtitle = { Text(if (inIt) "Has r/$subreddit · tap to remove" else "${multi.subreddits.size} communities") },
                            leading = { Icon(Icons.Rounded.DynamicFeed, null, tint = cs.tertiary) },
                            trailing = {
                                when {
                                    busy == multi.path -> Loading(Modifier.size(24.dp), color = LocalContentColor.current)
                                    inIt -> Icon(Icons.Rounded.CheckCircle, "In this feed", tint = cs.primary)
                                }
                            },
                            onClick = { toggle(multi) },
                        )
                    }
                }
                Tile(
                    title = { Text("New feed") },
                    subtitle = { Text("Starts with r/$subreddit") },
                    leading = { Icon(Icons.Rounded.Add, null) },
                    onClick = {
                        scope.launch {
                            if (createMulti(app.session.username, listOf(subreddit))) {
                                app.navigatorOrNull?.showSnackbar("Created a feed with r/$subreddit")
                                done(null)
                            }
                        }
                    },
                )
            }
        }
    }
}
