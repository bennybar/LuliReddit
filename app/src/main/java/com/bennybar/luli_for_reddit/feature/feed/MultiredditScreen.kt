package com.bennybar.luli_for_reddit.feature.feed

import kotlinx.coroutines.launch
import com.bennybar.luli_for_reddit.app
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material.icons.rounded.ContentCopy
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Tune
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bennybar.luli_for_reddit.nav.LocalNavigator
import com.bennybar.luli_for_reddit.nav.Route

/** A custom feed (multireddit): its posts, with a shortcut to manage it. */
@Composable
fun MultiredditScreen(username: String, name: String) {
    val nav = LocalNavigator.current
    val scope = rememberCoroutineScope()
    Scaffold(
        topBar = {
            BloomTopBar(
                name,
                actions = {
                    val mine = username.equals(app.session.username, ignoreCase = true)
                    if (mine) {
                        IconButton(onClick = { nav.push(Route.ManageMultireddit(username, name)) }) {
                            Icon(Icons.Rounded.Tune, "Manage")
                        }
                    } else if (!app.session.username.isEmpty()) {
                        // Someone's public feed: make your own copy of it (Reddit's "Copy custom feed").
                        IconButton(onClick = {
                            scope.launch {
                                val e = editFeedDialog("Copy to your feeds", "Copy", name.replace('_', ' '), "", "private") ?: return@launch
                                try {
                                    app.repository.copyMultireddit("/user/$username/m/$name", app.session.username, e.displayName)
                                    app.feed.loadMultireddits(force = true)
                                    nav.showSnackbar("Copied to your custom feeds")
                                } catch (ex: Exception) {
                                    nav.showActionError("copy the feed", ex)
                                }
                            }
                        }) { Icon(Icons.Rounded.ContentCopy, "Copy to your feeds") }
                    }
                    IconButton(onClick = { nav.share("https://www.reddit.com/user/$username/m/$name/") }) {
                        Icon(Icons.Outlined.Share, "Share link")
                    }
                },
            )
        },
        containerColor = MaterialTheme.colorScheme.surface,
    ) { padding ->
        PostListView(
            feedKey = "m::$username::$name",
            modifier = Modifier.padding(top = padding.calculateTopPadding()),
            header = {
                Text(
                    name,
                    Modifier.fillMaxWidth().padding(start = 16.dp, top = 12.dp, end = 16.dp),
                    style = MaterialTheme.typography.headlineMedium,
                    fontWeight = FontWeight.ExtraBold,
                )
            },
        )
    }
}
