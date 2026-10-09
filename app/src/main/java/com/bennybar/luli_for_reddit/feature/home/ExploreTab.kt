package com.bennybar.luli_for_reddit.feature.home

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.Sort
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.DynamicFeed
import androidx.compose.material.icons.rounded.FilterList
import androidx.compose.material.icons.rounded.LocalFireDepartment
import androidx.compose.material.icons.rounded.Public
import androidx.compose.material.icons.rounded.Star
import androidx.compose.material.icons.rounded.StarBorder
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.auth.SessionState
import com.bennybar.luli_for_reddit.core.compactNumber
import com.bennybar.luli_for_reddit.feature.feed.Async
import com.bennybar.luli_for_reddit.feature.feed.LetterAvatar
import com.bennybar.luli_for_reddit.feature.feed.Tile
import com.bennybar.luli_for_reddit.feature.feed.PillTextField
import com.bennybar.luli_for_reddit.feature.feed.SearchPill
import com.bennybar.luli_for_reddit.feature.feed.SectionHeader
import com.bennybar.luli_for_reddit.model.Subreddit
import com.bennybar.luli_for_reddit.nav.LocalNavigator
import com.bennybar.luli_for_reddit.nav.Route
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.launch

/** The user's subscriptions (favourites first, then A–Z, from the repository). */
class SubscriptionsViewModel : ViewModel() {
    private val _subs = MutableStateFlow<Async<List<Subreddit>>>(Async.Loading)
    val subs: StateFlow<Async<List<Subreddit>>> = _subs
    private var job: Job? = null

    /** The account generation the list was loaded for (reload after a switch). */
    var loadedFor = app.feed.version.value

    init {
        load()
    }

    fun load(force: Boolean = false): Job {
        job?.cancel()
        return viewModelScope.launch {
            if (_subs.value !is Async.Data) _subs.value = Async.Loading
            try {
                _subs.value = Async.Data(app.repository.getSubscribedSubreddits(force))
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _subs.value = Async.Error(e)
            }
        }.also { job = it }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ExploreTab() {
    val cs = MaterialTheme.colorScheme
    val nav = LocalNavigator.current
    val vm = viewModel { SubscriptionsViewModel() }
    val subs by vm.subs.collectAsStateWithLifecycle()
    val history by app.history.state.collectAsStateWithLifecycle()
    val session by app.session.state.collectAsStateWithLifecycle()
    val anonymous = (session as? SessionState.LoggedIn)?.session?.anonymous == true
    val listState = rememberLazyListState()
    val scope = rememberCoroutineScope()
    var query by rememberSaveable { mutableStateOf("") }
    var favOnly by rememberSaveable { mutableStateOf(false) }
    var sort by rememberSaveable { mutableStateOf("default") } // default | name | subscribers
    var refreshing by remember { mutableStateOf(false) }

    // Re-tapping the Explore tab scrolls back to top.
    LaunchedEffect(listState) {
        app.feed.tabReselect(1).drop(1).collect { listState.animateScrollToItem(0) }
    }
    // After an account switch: that account's subscriptions and custom feeds.
    val version by app.feed.version.collectAsStateWithLifecycle()
    LaunchedEffect(version) {
        if (vm.loadedFor != version) {
            vm.loadedFor = version
            vm.load(force = true)
        }
        // Custom feeds row (shared with the You tab).
        app.feed.loadMultireddits()
    }
    val multis by app.feed.multireddits.collectAsStateWithLifecycle()

    // The star toggle: favouriting reorders the list, so reload it after.
    fun toggleFavorite(s: Subreddit) {
        scope.launch {
            try {
                app.repository.setSubredditFavorite(s.name, !s.userHasFavorited)
                vm.load()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                nav.showActionError(if (s.userHasFavorited) "unfavorite" else "favorite", e)
            }
        }
    }

    PullToRefreshBox(
        isRefreshing = refreshing,
        onRefresh = {
            scope.launch {
                refreshing = true
                try {
                    vm.load(force = true).join()
                } finally {
                    refreshing = false
                }
            }
        },
        modifier = Modifier.fillMaxSize(),
    ) {
        LazyColumn(Modifier.fillMaxSize(), state = listState, contentPadding = PaddingValues(bottom = 130.dp)) {
            // Search entry
            item(key = "search") {
                SearchPill(
                    "Search communities & posts",
                    onClick = { nav.push(Route.Search()) },
                    modifier = Modifier.padding(start = 16.dp, top = 12.dp, end = 16.dp, bottom = 4.dp),
                )
            }
            item(key = "popular") {
                Row(Modifier.padding(start = 12.dp, top = 8.dp, end = 12.dp)) {
                    OutlinedButton(
                        onClick = { nav.openSubreddit("popular") },
                        modifier = Modifier.weight(1f).defaultMinSize(minHeight = 52.dp),
                    ) {
                        Icon(Icons.Rounded.LocalFireDepartment, null, Modifier.size(18.dp))
                        Spacer(Modifier.width(8.dp))
                        Text("Popular")
                    }
                    Spacer(Modifier.width(8.dp))
                    OutlinedButton(
                        onClick = { nav.openSubreddit("all") },
                        modifier = Modifier.weight(1f).defaultMinSize(minHeight = 52.dp),
                    ) {
                        Icon(Icons.Rounded.Public, null, Modifier.size(18.dp))
                        Spacer(Modifier.width(8.dp))
                        Text("All")
                    }
                }
            }
            // Custom feeds (multireddits) — hidden when the user has none.
            val multiList = (multis as? Async.Data)?.value.orEmpty()
            if (multiList.isNotEmpty()) {
                item(key = "multis") {
                    Column {
                        SectionHeader("Custom feeds", Modifier.padding(start = 16.dp, top = 14.dp, end = 16.dp, bottom = 2.dp))
                        LazyRow(
                            Modifier.height(48.dp),
                            contentPadding = PaddingValues(horizontal = 12.dp),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            items(multiList, key = { it.path.ifEmpty { it.name } }) { m ->
                                AssistChip(
                                    onClick = {
                                        val parts = m.path.split('/').filter { it.isNotEmpty() }
                                        val user = if (parts.size >= 4) parts[1] else currentUser()
                                        nav.push(Route.Multireddit(user, m.name))
                                    },
                                    label = { Text(m.displayName.ifEmpty { m.name }) },
                                    leadingIcon = {
                                        Icon(Icons.Rounded.DynamicFeed, null, Modifier.size(18.dp), tint = cs.onSecondaryContainer)
                                    },
                                    shape = CircleShape,
                                    border = null,
                                    colors = AssistChipDefaults.assistChipColors(containerColor = cs.surfaceContainerHigh),
                                )
                            }
                        }
                    }
                }
            }
            item(key = "title") {
                Text(
                    "Explore",
                    Modifier.padding(start = 16.dp, top = 8.dp, end = 16.dp),
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.ExtraBold,
                )
            }
            item(key = "filter") {
                Row(Modifier.padding(start = 16.dp, top = 8.dp, end = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    PillTextField(
                        value = query,
                        onValueChange = { query = it },
                        placeholder = "Filter your communities",
                        leading = Icons.Rounded.FilterList,
                        modifier = Modifier.weight(1f),
                    )
                    IconButton(onClick = { favOnly = !favOnly }) {
                        Icon(
                            if (favOnly) Icons.Rounded.Star else Icons.Rounded.StarBorder,
                            if (favOnly) "Showing favorites" else "Favorites only",
                            tint = if (favOnly) cs.primary else cs.onSurfaceVariant,
                        )
                    }
                    SortMenu(sort) { sort = it }
                }
            }
            when (val s = subs) {
                Async.Loading -> item(key = "loading") {
                    Box(Modifier.fillMaxWidth().padding(40.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
                }
                is Async.Error -> item(key = "error") {
                    if (anonymous) {
                        SignInPrompt(
                            "Sign in to see the communities you've joined. You can still search and open any subreddit.",
                        )
                    } else {
                        Column(Modifier.fillMaxWidth().padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                            Text("Couldn't load your communities.", textAlign = TextAlign.Center)
                            Spacer(Modifier.height(12.dp))
                            Button(onClick = { vm.load() }) { Text("Retry") }
                        }
                    }
                }
                is Async.Data -> subscriptionSections(
                    list = s.value,
                    query = query,
                    favOnly = favOnly,
                    sort = sort,
                    recentFromHistory = history.map { it.subreddit },
                    onOpen = { nav.openSubreddit(it.name) },
                    onStar = ::toggleFavorite,
                )
            }
        }
    }
}

private fun currentUser(): String = app.session.username

private fun LazyListScope.subscriptionSections(
    list: List<Subreddit>,
    query: String,
    favOnly: Boolean,
    sort: String,
    recentFromHistory: List<String>,
    onOpen: (Subreddit) -> Unit,
    onStar: (Subreddit) -> Unit,
) {
    val q = query.trim().lowercase()
    val active = q.isNotEmpty() || favOnly || sort != "default"
    fun header(key: String, title: String) = item(key = "h_$key") {
        SectionHeader(title, Modifier.padding(start = 16.dp, top = 18.dp, end = 16.dp, bottom = 6.dp))
    }
    fun rows(section: String, subs: List<Subreddit>) =
        items(subs, key = { "${section}_${it.name}" }, contentType = { "sub" }) { SubredditRow(it, onOpen, onStar) }

    if (active) {
        // Filtered/sorted flat view.
        var working = list.filter { (q.isEmpty() || it.name.lowercase().contains(q)) && (!favOnly || it.userHasFavorited) }
        if (sort == "name") working = working.sortedBy { it.name.lowercase() }
        else if (sort == "subscribers") working = working.sortedByDescending { it.subscribers }
        header("count", "${working.size} communities")
        if (working.isEmpty()) {
            item(key = "nomatch") { Box(Modifier.fillMaxWidth().padding(32.dp), contentAlignment = Alignment.Center) { Text("No matches") } }
        } else {
            rows("all", working)
        }
        return
    }

    // Default view: recently visited + favorites + the rest.
    val byName = list.associateBy { it.name.lowercase() }
    val seen = HashSet<String>()
    val recent = ArrayList<Subreddit>()
    for (sub in recentFromHistory) {
        val s = byName[sub.lowercase()]
        if (s != null && seen.add(s.name)) recent.add(s)
        if (recent.size >= 5) break
    }
    val favs = list.filter { it.userHasFavorited }
    val rest = list.filter { !it.userHasFavorited }
    if (recent.isNotEmpty()) {
        header("recent", "Recently visited")
        rows("recent", recent)
    }
    if (favs.isNotEmpty()) {
        header("favs", "Favorites")
        rows("fav", favs)
    }
    header("subs", if (favs.isEmpty()) "Subscriptions" else "Communities")
    if (rest.isEmpty() && favs.isEmpty()) {
        item(key = "none") {
            Box(Modifier.fillMaxWidth().padding(32.dp), contentAlignment = Alignment.Center) { Text("You have no subscriptions yet") }
        }
    } else {
        rows("rest", rest)
    }
}

@Composable
private fun SortMenu(sort: String, onPick: (String) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        IconButton(onClick = { open = true }) { Icon(Icons.AutoMirrored.Rounded.Sort, "Sort") }
        DropdownMenu(open, onDismissRequest = { open = false }) {
            for ((value, label) in listOf("default" to "Default", "name" to "Name A–Z", "subscribers" to "Most subscribers")) {
                DropdownMenuItem(
                    text = { Text(label) },
                    trailingIcon = if (value == sort) ({ Icon(Icons.Rounded.Check, null, Modifier.size(18.dp)) }) else null,
                    onClick = {
                        open = false
                        onPick(value)
                    },
                )
            }
        }
    }
}

@Composable
internal fun SubredditRow(s: Subreddit, onOpen: (Subreddit) -> Unit, onStar: ((Subreddit) -> Unit)? = null) {
    val cs = MaterialTheme.colorScheme
    Tile(
        title = { Text(s.namePrefixed) },
        subtitle = { Text("${compactNumber(s.subscribers)} members") },
        leading = {
            LetterAvatar(s.name, 40.dp, cs.secondaryContainer, cs.onSecondaryContainer, imageUrl = s.iconUrl)
        },
        trailing = onStar?.let {
            {
                IconButton(onClick = { it(s) }) {
                    Icon(
                        if (s.userHasFavorited) Icons.Rounded.Star else Icons.Rounded.StarBorder,
                        if (s.userHasFavorited) "Unfavorite" else "Favorite",
                        tint = if (s.userHasFavorited) cs.primary else cs.onSurfaceVariant,
                    )
                }
            }
        },
        onClick = { onOpen(s) },
    )
}
