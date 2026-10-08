package com.bennybar.luli_for_reddit.feature.feed

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material.icons.rounded.ExpandLess
import androidx.compose.material.icons.rounded.ExpandMore
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import coil3.compose.AsyncImage
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.core.compactNumber
import com.bennybar.luli_for_reddit.model.Subreddit
import com.bennybar.luli_for_reddit.nav.LocalNavigator
import com.bennybar.luli_for_reddit.nav.Route
import com.bennybar.luli_for_reddit.ui.Overlays
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

/** A subreddit's about info (header + about sheet). */
class SubredditAboutViewModel(private val name: String) : ViewModel() {
    private val _about = MutableStateFlow<Async<Subreddit>>(Async.Loading)
    val about: StateFlow<Async<Subreddit>> = _about

    /** Optimistic subscribe state. */
    val subOverride = MutableStateFlow<Boolean?>(null)

    init {
        viewModelScope.launch {
            _about.value = try {
                Async.Data(app.repository.getSubredditAbout(name))
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Async.Error(e)
            }
        }
    }

    fun toggleSub(s: Subreddit, currentlySubscribed: Boolean) {
        val next = !currentlySubscribed
        subOverride.value = next
        app.scope.launch {
            try {
                app.repository.setSubscribed(s.name, next)
            } catch (e: Exception) {
                subOverride.value = currentlySubscribed
                app.navigatorOrNull?.showActionError(if (next) "join" else "leave", e)
            }
        }
    }
}

@Composable
fun SubredditScreen(name: String) {
    val nav = LocalNavigator.current
    val scope = rememberCoroutineScope()
    val vm = viewModel(key = "sr_$name") { SubredditAboutViewModel(name) }
    val about by vm.about.collectAsStateWithLifecycle()
    Scaffold(
        topBar = {
            BloomTopBar(
                "r/$name",
                actions = {
                    IconButton(onClick = { nav.push(Route.Search(subreddit = name)) }) { Icon(Icons.Rounded.Search, "Search") }
                    IconButton(onClick = { scope.launch { showAbout(name, (about as? Async.Data)?.value) } }) {
                        Icon(Icons.Outlined.Info, "About & rules")
                    }
                    IconButton(onClick = { nav.share("https://reddit.com/r/$name") }) { Icon(Icons.Outlined.Share, "Share") }
                },
            )
        },
        floatingActionButton = {
            FloatingActionButton(
                onClick = { nav.push(Route.Submit(name)) },
                shape = RoundedCornerShape(20.dp),
                containerColor = MaterialTheme.colorScheme.primaryContainer,
                contentColor = MaterialTheme.colorScheme.onPrimaryContainer,
            ) { Icon(Icons.Rounded.Edit, "New post") }
        },
        containerColor = MaterialTheme.colorScheme.surface,
    ) { padding ->
        PostListView(
            feedKey = name,
            modifier = Modifier.padding(top = padding.calculateTopPadding()),
            header = {
                when (val a = about) {
                    Async.Loading -> LinearProgressIndicator(Modifier.fillMaxWidth().height(4.dp))
                    is Async.Error -> {}
                    is Async.Data -> SubredditHeader(a.value, vm)
                }
            },
        )
    }
}

@Composable
private fun SubredditHeader(s: Subreddit, vm: SubredditAboutViewModel) {
    val cs = MaterialTheme.colorScheme
    val override by vm.subOverride.collectAsStateWithLifecycle()
    val subscribed = override ?: s.userIsSubscriber ?: false
    Column(Modifier.padding(start = 6.dp, top = 8.dp, end = 6.dp)) {
        if (s.bannerUrl != null) {
            AsyncImage(
                model = rememberSizedRequest(s.bannerUrl, feedDecodeWidth()),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxWidth().height(110.dp).clip(RoundedCornerShape(20.dp)),
            )
        }
        BloomCard(Modifier.padding(start = 4.dp, top = 10.dp, end = 4.dp, bottom = 4.dp).fillMaxWidth()) {
            Column(Modifier.padding(14.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    LetterAvatar(s.name, 52.dp, cs.secondaryContainer, cs.onSecondaryContainer, imageUrl = s.iconUrl)
                    Spacer(Modifier.width(14.dp))
                    Column(Modifier.weight(1f)) {
                        Text(s.namePrefixed, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.ExtraBold)
                        Text("${compactNumber(s.subscribers)} members", color = cs.onSurfaceVariant)
                    }
                    FilledTonalButton(onClick = { vm.toggleSub(s, subscribed) }) { Text(if (subscribed) "Joined" else "Join") }
                }
                if (s.description.isNotEmpty()) {
                    Spacer(Modifier.height(12.dp))
                    Text(s.description, color = cs.onSurfaceVariant)
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
private suspend fun showAbout(name: String, about: Subreddit?) {
    Overlays.show<Unit> { done ->
        val cs = MaterialTheme.colorScheme
        ModalBottomSheet(onDismissRequest = { done(null) }) {
            val rules by produceState<List<Pair<String, String>>?>(null) {
                value = runCatching { app.repository.getSubredditRules(name) }.getOrDefault(emptyList())
            }
            LazyColumn(Modifier.navigationBarsPadding().padding(start = 20.dp, top = 4.dp, end = 20.dp, bottom = 24.dp)) {
                item {
                    Text("r/$name", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.ExtraBold)
                    if (about != null && about.title.isNotEmpty()) {
                        Text(about.title, Modifier.padding(top = 2.dp), style = MaterialTheme.typography.bodyMedium)
                    }
                    if (about != null) {
                        Text("${compactNumber(about.subscribers)} members", Modifier.padding(top = 4.dp), color = cs.onSurfaceVariant)
                    }
                    if (about != null && about.description.isNotEmpty()) {
                        Spacer(Modifier.height(12.dp))
                        Text(about.description)
                    }
                    Spacer(Modifier.height(18.dp))
                    SectionHeader("Rules")
                    Spacer(Modifier.height(4.dp))
                }
                val r = rules
                when {
                    r == null -> item {
                        Box(Modifier.fillMaxWidth().padding(16.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
                    }
                    r.isEmpty() -> item { Text("No rules listed.") }
                    else -> items(r.size) { i -> RuleTile(i, r[i].first, r[i].second) }
                }
            }
        }
    }
}

/** An expandable rule (Flutter's ExpansionTile without dividers). */
@Composable
private fun RuleTile(index: Int, title: String, description: String) {
    var open by rememberSaveable { mutableStateOf(false) }
    Column {
        Row(
            Modifier.fillMaxWidth().clickable { open = !open }.padding(vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("${index + 1}. $title", Modifier.weight(1f), fontWeight = FontWeight.SemiBold)
            Icon(if (open) Icons.Rounded.ExpandLess else Icons.Rounded.ExpandMore, null)
        }
        AnimatedVisibility(open) {
            if (description.isNotEmpty()) Text(description, Modifier.padding(bottom = 12.dp))
        }
    }
}
