package com.bennybar.luli_for_reddit.feature.feed

import com.bennybar.luli_for_reddit.ui.ConnectedChoice
import com.bennybar.luli_for_reddit.ui.Loading
import androidx.compose.foundation.background
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.DynamicFeed
import androidx.compose.material.icons.rounded.Tune
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.feature.home.createMulti
import com.bennybar.luli_for_reddit.model.Multireddit
import com.bennybar.luli_for_reddit.nav.LocalNavigator
import com.bennybar.luli_for_reddit.nav.Route
import com.bennybar.luli_for_reddit.ui.Overlays
import com.bennybar.luli_for_reddit.ui.friendlyError
import kotlinx.coroutines.launch

/** Who owns a feed path (/user/<name>/m/<feed>), else the signed-in user. */
internal fun Multireddit.owner(): String =
    path.split('/').filter { it.isNotEmpty() }.let { if (it.size >= 4 && it[0] == "user") it[1] else app.session.username }

/** Every custom feed of yours, in one list (Explore's row gets long). */
@Composable
fun CustomFeedsScreen() {
    val nav = LocalNavigator.current
    val cs = MaterialTheme.colorScheme
    val scope = rememberCoroutineScope()
    val multis by app.feed.multireddits.collectAsStateWithLifecycle()
    LaunchedEffect(Unit) { app.feed.loadMultireddits(force = true) }
    Scaffold(
        topBar = {
            BloomTopBar("Custom feeds", actions = {
                IconButton(onClick = { scope.launch { createMulti(app.session.username) } }) { Icon(Icons.Rounded.Add, "New feed") }
            })
        },
        containerColor = cs.surface,
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(top = padding.calculateTopPadding())) {
            when (val m = multis) {
                Async.Loading -> Loading(Modifier.align(Alignment.Center))
                is Async.Error -> Text("Couldn't load your custom feeds: ${friendlyError(m.error)}", Modifier.align(Alignment.Center).padding(32.dp))
                is Async.Data -> if (m.value.isEmpty()) {
                    Column(Modifier.align(Alignment.Center).padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        Text("No custom feeds yet. A custom feed mixes the communities you pick into one feed.")
                        Spacer(Modifier.size(12.dp))
                        Button(onClick = { scope.launch { createMulti(app.session.username) } }) { Text("New feed") }
                    }
                } else {
                    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 32.dp)) {
                        items(m.value, key = { it.path.ifEmpty { it.name } }) { multi ->
                            Tile(
                                title = { Text(multi.displayName.ifEmpty { multi.name }) },
                                subtitle = {
                                    Text("${multi.subreddits.size} communities · ${if (multi.visibility == "public") "Public" else "Private"}")
                                },
                                leading = {
                                    Box(Modifier.size(40.dp).background(cs.tertiaryContainer, CircleShape), contentAlignment = Alignment.Center) {
                                        Icon(Icons.Rounded.DynamicFeed, null, Modifier.size(20.dp), tint = cs.onTertiaryContainer)
                                    }
                                },
                                trailing = {
                                    IconButton(onClick = { nav.push(Route.ManageMultireddit(multi.owner(), multi.name)) }) {
                                        Icon(Icons.Rounded.Tune, "Manage")
                                    }
                                },
                                onClick = { nav.push(Route.Multireddit(multi.owner(), multi.name)) },
                            )
                        }
                    }
                }
            }
        }
    }
}

class FeedEdit(val displayName: String, val description: String, val visibility: String)

/** Name, description and Public / Private for a custom feed ([title]: Edit / Copy). */
suspend fun editFeedDialog(title: String, confirm: String, name: String, description: String, visibility: String): FeedEdit? =
    Overlays.show<FeedEdit> { done ->
        var n by remember { mutableStateOf(name) }
        var d by remember { mutableStateOf(description) }
        var v by remember { mutableStateOf(visibility) }
        AlertDialog(
            onDismissRequest = { done(null) },
            title = { Text(title) },
            text = {
                Column {
                    OutlinedTextField(
                        n, { n = it }, label = { Text("Name") }, singleLine = true, shape = RoundedCornerShape(18.dp),
                        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Spacer(Modifier.size(10.dp))
                    OutlinedTextField(
                        d, { d = it }, label = { Text("Description (optional)") }, minLines = 2, shape = RoundedCornerShape(18.dp),
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Spacer(Modifier.size(10.dp))
                    ConnectedChoice(listOf("private" to "Private", "public" to "Public"), v, { v = it })
                    Text(
                        if (v == "public") "Anyone with the link can see it, follow it or copy it." else "Only you can see it.",
                        Modifier.padding(top = 6.dp),
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            },
            dismissButton = { TextButton(onClick = { done(null) }) { Text("Cancel") } },
            confirmButton = { Button(onClick = { done(FeedEdit(n.trim(), d.trim(), v)) }, enabled = n.isNotBlank()) { Text(confirm) } },
        )
    }
