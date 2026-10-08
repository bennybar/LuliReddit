package com.bennybar.luli_for_reddit.feature.feed

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.SubdirectoryArrowRight
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.DeleteOutline
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalButton
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
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.model.Multireddit
import com.bennybar.luli_for_reddit.nav.LocalNavigator
import com.bennybar.luli_for_reddit.ui.Overlays
import com.bennybar.luli_for_reddit.ui.friendlyError
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

/** Looks up a single multireddit by name from the user's list. */
class MultiredditByNameViewModel(private val name: String) : ViewModel() {
    private val _multi = MutableStateFlow<Async<Multireddit?>>(Async.Loading)
    val multi: StateFlow<Async<Multireddit?>> = _multi

    init {
        reload()
    }

    fun reload() {
        viewModelScope.launch {
            _multi.value = try {
                Async.Data(app.repository.getMyMultireddits().firstOrNull { it.name == name })
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Async.Error(e)
            }
        }
    }
}

@Composable
fun ManageMultiredditScreen(username: String, name: String) {
    val nav = LocalNavigator.current
    val scope = rememberCoroutineScope()
    val vm = viewModel(key = "manage_${username}_$name") { MultiredditByNameViewModel(name) }
    val async by vm.multi.collectAsStateWithLifecycle()
    val repo = app.repository

    Scaffold(
        topBar = {
            BloomTopBar(
                name,
                actions = {
                    IconButton(onClick = {
                        val multi = (async as? Async.Data)?.value ?: return@IconButton
                        scope.launch {
                            val ok = Overlays.show<Boolean> { done ->
                                AlertDialog(
                                    onDismissRequest = { done(null) },
                                    title = { Text("Delete \"$name\"?") },
                                    text = { Text("This custom feed will be removed.") },
                                    dismissButton = { TextButton(onClick = { done(false) }) { Text("Cancel") } },
                                    confirmButton = { Button(onClick = { done(true) }) { Text("Delete") } },
                                )
                            }
                            if (ok == true) {
                                try {
                                    repo.deleteMultireddit(multi.path)
                                    app.feed.loadMultireddits(force = true)
                                    nav.pop()
                                } catch (e: Exception) {
                                    nav.showActionError("delete the feed", e)
                                }
                            }
                        }
                    }) { Icon(Icons.Rounded.DeleteOutline, "Delete feed") }
                },
            )
        },
        containerColor = MaterialTheme.colorScheme.surface,
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(top = padding.calculateTopPadding())) {
            when (val a = async) {
                Async.Loading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
                is Async.Error -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text("Could not load feed: ${friendlyError(a.error)}")
                }
                is Async.Data -> {
                    val multi = a.value
                    if (multi == null) {
                        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Text("Feed not found") }
                    } else {
                        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 32.dp)) {
                            item {
                                FilledTonalButton(
                                    onClick = {
                                        scope.launch {
                                            val sr = askSubreddit() ?: return@launch
                                            try {
                                                repo.addSubredditToMulti(multi.path, sr)
                                            } catch (e: Exception) {
                                                nav.showActionError("add r/$sr", e)
                                            }
                                            vm.reload()
                                            app.feed.loadMultireddits(force = true)
                                        }
                                    },
                                    modifier = Modifier.padding(16.dp),
                                ) {
                                    Icon(Icons.Rounded.Add, null)
                                    Spacer(Modifier.width(8.dp))
                                    Text("Add subreddit")
                                }
                            }
                            items(multi.subreddits, key = { it }) { sr ->
                                Tile(
                                    title = { Text("r/$sr") },
                                    leading = { Icon(Icons.Rounded.SubdirectoryArrowRight, null) },
                                    trailing = {
                                        IconButton(onClick = {
                                            scope.launch {
                                                try {
                                                    repo.removeSubredditFromMulti(multi.path, sr)
                                                } catch (e: Exception) {
                                                    nav.showActionError("remove r/$sr", e)
                                                }
                                                vm.reload()
                                                app.feed.loadMultireddits(force = true)
                                            }
                                        }) { Icon(Icons.Rounded.Close, "Remove") }
                                    },
                                )
                            }
                            if (multi.subreddits.isEmpty()) {
                                item {
                                    Box(Modifier.fillMaxWidth().padding(32.dp), contentAlignment = Alignment.Center) {
                                        Text("No subreddits yet")
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

private suspend fun askSubreddit(): String? = Overlays.show<String> { done ->
    var text by remember { mutableStateOf("") }
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { focus.requestFocus() }
    AlertDialog(
        onDismissRequest = { done(null) },
        title = { Text("Add subreddit") },
        text = {
            OutlinedTextField(
                value = text,
                onValueChange = { text = it },
                label = { Text("Name") },
                prefix = { Text("r/") },
                singleLine = true,
                shape = RoundedCornerShape(18.dp),
                keyboardOptions = KeyboardOptions(autoCorrectEnabled = false, capitalization = KeyboardCapitalization.None),
                keyboardActions = KeyboardActions(onDone = { done(text.trim()) }),
                modifier = Modifier.focusRequester(focus),
            )
        },
        dismissButton = { TextButton(onClick = { done(null) }) { Text("Cancel") } },
        confirmButton = { Button(onClick = { done(text.trim()) }) { Text("Add") } },
    )
}?.takeIf { it.isNotEmpty() }
