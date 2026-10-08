package com.bennybar.luli_for_reddit.feature.feed

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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Clear
import androidx.compose.material.icons.rounded.History
import androidx.compose.material.icons.rounded.NorthWest
import androidx.compose.material.icons.rounded.Schedule
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.PrimaryTabRow
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.core.compactNumber
import com.bennybar.luli_for_reddit.model.Post
import com.bennybar.luli_for_reddit.model.RedditUser
import com.bennybar.luli_for_reddit.model.Subreddit
import com.bennybar.luli_for_reddit.nav.LocalNavigator
import com.bennybar.luli_for_reddit.ui.ErrorView
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

private val SEARCH_SORTS = linkedMapOf(
    "relevance" to "Relevance",
    "hot" to "Hot",
    "top" to "Top",
    "new" to "New",
    "comments" to "Comments",
)
private val SEARCH_TIMES = linkedMapOf(
    "hour" to "Hour",
    "day" to "Day",
    "week" to "Week",
    "month" to "Month",
    "year" to "Year",
    "all" to "All time",
)

data class SearchState(
    val loading: Boolean = false,
    val query: String = "",
    val sort: String = "relevance",
    val time: String = "all",
    val posts: List<Post> = emptyList(),
    val subs: List<Subreddit> = emptyList(),
    val users: List<RedditUser> = emptyList(),
    val recent: List<String> = emptyList(),
    val error: Throwable? = null,
    val postsAfter: String? = null, // next page of post results
    val loadingMore: Boolean = false,
)

class SearchViewModel(private val subreddit: String?) : ViewModel() {
    private val _state = MutableStateFlow(SearchState())
    val state: StateFlow<SearchState> = _state

    // Bumped per search: a slow earlier search (e.g. before a sort change) must
    // not overwrite the results of a newer one.
    private var request = 0
    private var job: Job? = null

    // Per account, like the rest of the on-device history.
    private val recentKey: String = run {
        val prefs = app.prefs
        val user = app.session.username.lowercase()
        val key = if (user.isEmpty()) LEGACY_RECENT_KEY else "${LEGACY_RECENT_KEY}_$user"
        if (key != LEGACY_RECENT_KEY && !prefs.contains(key) && prefs.contains(LEGACY_RECENT_KEY)) {
            prefs.setStringList(key, prefs.getStringList(LEGACY_RECENT_KEY) ?: emptyList())
            prefs.remove(LEGACY_RECENT_KEY)
        }
        key
    }

    init {
        _state.update { it.copy(recent = app.prefs.getStringList(recentKey) ?: emptyList()) }
    }

    private fun saveRecent(q: String) {
        // Recent searches are history: none kept while tracking is off.
        if (!app.settings.value.trackHistory) return
        val list = (listOf(q) + _state.value.recent.filter { it != q }).take(12)
        app.prefs.setStringList(recentKey, list)
        _state.update { it.copy(recent = list) }
    }

    fun clearRecent() {
        app.prefs.remove(recentKey)
        _state.update { it.copy(recent = emptyList()) }
    }

    fun clear() {
        request++
        job?.cancel()
        _state.update { it.copy(query = "", error = null, posts = emptyList(), subs = emptyList(), users = emptyList(), loading = false) }
    }

    fun setSort(sort: String) {
        _state.update { it.copy(sort = sort) }
        search(_state.value.query, saveRecent = false)
    }

    fun setTime(time: String) {
        _state.update { it.copy(time = time) }
        search(_state.value.query, saveRecent = false)
    }

    fun search(raw: String, saveRecent: Boolean = true): Job? {
        val q = raw.trim()
        if (q.isEmpty()) return null
        if (saveRecent) saveRecent(q)
        val req = ++request
        _state.update { it.copy(loading = true, error = null, query = q) }
        val s = _state.value
        val repo = app.repository
        job = viewModelScope.launch {
            try {
                val posts = async { repo.searchPosts(q, subreddit = subreddit, sort = s.sort, time = s.time) }
                val subs = async { if (subreddit == null) repo.searchSubreddits(q) else emptyList() }
                val users = async { if (subreddit == null) repo.searchUsers(q) else emptyList() }
                val p = posts.await()
                val sr = subs.await()
                val us = users.await()
                if (req != request) return@launch
                _state.update {
                    it.copy(posts = p.items, postsAfter = p.after, subs = sr, users = us, loading = false)
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (req != request) return@launch
                _state.update { it.copy(loading = false, error = e) } // shown instead of a misleading "No results"
            }
        }
        return job
    }

    fun loadMorePosts() {
        val s = _state.value
        val after = s.postsAfter
        if (after.isNullOrEmpty() || s.loadingMore) return
        val req = request
        _state.update { it.copy(loadingMore = true) }
        viewModelScope.launch {
            try {
                val page = app.repository.searchPosts(s.query, subreddit = subreddit, sort = s.sort, time = s.time, after = after)
                if (req != request) return@launch
                _state.update { cur ->
                    val seen = cur.posts.mapTo(HashSet()) { it.id }
                    cur.copy(posts = cur.posts + page.items.filter { it.id !in seen }, postsAfter = page.after)
                }
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                // Keep the cursor: scrolling to the end again retries.
            } finally {
                if (req == request) _state.update { it.copy(loadingMore = false) }
            }
        }
    }

    companion object {
        private const val LEGACY_RECENT_KEY = "recent_searches"
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SearchScreen(subreddit: String?, query: String?) {
    val cs = MaterialTheme.colorScheme
    val vm = viewModel(key = "search_${subreddit ?: ""}") { SearchViewModel(subreddit) }
    val state by vm.state.collectAsStateWithLifecycle()
    val focusManager = LocalFocusManager.current
    val nav = LocalNavigator.current
    val restricted = subreddit != null
    val initial = query?.trim().orEmpty()
    var text by rememberSaveable { mutableStateOf(state.query.ifEmpty { initial }) }
    val focus = remember { FocusRequester() }
    val scope = rememberCoroutineScope()

    fun doSearch(q: String, save: Boolean = true) {
        val t = q.trim()
        if (t.isEmpty()) return
        if (text != t) text = t
        focusManager.clearFocus()
        vm.search(t, saveRecent = save)
    }

    LaunchedEffect(Unit) {
        if (state.query.isEmpty()) {
            if (initial.isNotEmpty()) doSearch(initial) else focus.requestFocus()
        }
    }

    val tabs = if (restricted) listOf("Posts") else listOf("Posts", "Subreddits", "Users")
    val pager = rememberPagerState { tabs.size }

    Scaffold(
        topBar = {
            Column {
                BloomTopBar(
                    "",
                    titleContent = {
                        PillTextField(
                            value = text,
                            onValueChange = { text = it },
                            placeholder = if (restricted) "Search in r/$subreddit" else "Search Reddit",
                            radius = 28.dp,
                            modifier = Modifier.fillMaxWidth().padding(end = 8.dp).focusRequester(focus),
                            onSearch = { doSearch(it) },
                            trailing = if (text.isEmpty()) null else ({
                                IconButton(onClick = {
                                    text = ""
                                    vm.clear()
                                }) { Icon(Icons.Rounded.Clear, "Clear") }
                            }),
                        )
                    },
                )
                if (!restricted) {
                    PrimaryTabRow(selectedTabIndex = pager.currentPage, containerColor = cs.surface) {
                        tabs.forEachIndexed { i, t ->
                            Tab(
                                selected = pager.currentPage == i,
                                onClick = { scope.launch { pager.animateScrollToPage(i) } },
                                text = { Text(t) },
                            )
                        }
                    }
                }
            }
        },
        containerColor = cs.surface,
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(top = padding.calculateTopPadding())) {
            when {
                state.loading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
                state.error != null -> ErrorView(state.error, onRetry = { vm.search(state.query, saveRecent = false) })
                state.query.isEmpty() -> EmptySearch(
                    recent = state.recent,
                    onClear = vm::clearRecent,
                    onPick = { doSearch(it) },
                    onRerun = { doSearch(it, save = false) },
                )
                else -> HorizontalPager(pager, Modifier.fillMaxSize(), key = { tabs[it] }) { page ->
                    when (tabs[page]) {
                        "Posts" -> PostsTab(state, vm)
                        "Subreddits" -> RefreshableResults(state.subs.isEmpty(), "No subreddits found", vm, state.query) {
                            items(state.subs, key = { it.name }) { s ->
                                ResultTile(
                                    s.name,
                                    s.namePrefixed,
                                    "${compactNumber(s.subscribers)} members",
                                ) { nav.openSubreddit(s.name) }
                            }
                        }
                        else -> RefreshableResults(state.users.isEmpty(), "No users found", vm, state.query) {
                            items(state.users, key = { it.name }) { u ->
                                ResultTile(
                                    u.name,
                                    "u/${u.name}",
                                    "${compactNumber(u.linkKarma + u.commentKarma)} karma",
                                ) { nav.openUser(u.name) }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun EmptySearch(recent: List<String>, onClear: () -> Unit, onPick: (String) -> Unit, onRerun: (String) -> Unit) {
    val cs = MaterialTheme.colorScheme
    if (recent.isEmpty()) {
        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(Icons.Rounded.Search, null, Modifier.size(56.dp), tint = cs.onSurfaceVariant)
            Spacer(Modifier.height(12.dp))
            Text("Search posts, subreddits and users", color = cs.onSurfaceVariant)
        }
        return
    }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(top = 8.dp, bottom = 130.dp)) {
        item {
            Row(Modifier.padding(start = 16.dp, top = 8.dp, end = 8.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Recent", Modifier.weight(1f), color = cs.onSurfaceVariant, fontWeight = FontWeight.SemiBold)
                TextButton(onClick = onClear) { Text("Clear") }
            }
        }
        items(recent, key = { it }) { q ->
            Tile(
                title = { Text(q) },
                leading = { Icon(Icons.Rounded.History, null) },
                trailing = {
                    IconButton(onClick = { onRerun(q) }) { Icon(Icons.Rounded.NorthWest, null, Modifier.size(18.dp)) }
                },
                onClick = { onPick(q) },
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun RefreshableResults(
    empty: Boolean,
    emptyLabel: String,
    vm: SearchViewModel,
    query: String,
    content: androidx.compose.foundation.lazy.LazyListScope.() -> Unit,
) {
    var refreshing by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    PullToRefreshBox(
        refreshing,
        onRefresh = {
            scope.launch {
                refreshing = true
                try {
                    vm.search(query, saveRecent = false)?.join()
                } finally {
                    refreshing = false
                }
            }
        },
        modifier = Modifier.fillMaxSize(),
    ) {
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 130.dp)) {
            if (empty) {
                item {
                    Spacer(Modifier.height(120.dp))
                    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { Text(emptyLabel) }
                }
            } else {
                content()
            }
        }
    }
}

@Composable
private fun ResultTile(name: String, title: String, subtitle: String, onClick: () -> Unit) {
    val cs = MaterialTheme.colorScheme
    Tile(
        title = { Text(title) },
        subtitle = { Text(subtitle) },
        leading = { LetterAvatar(name, 40.dp, cs.secondaryContainer, cs.onSecondaryContainer) },
        onClick = onClick,
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PostsTab(state: SearchState, vm: SearchViewModel) {
    var refreshing by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    Column(Modifier.fillMaxSize()) {
        FilterBar(state, vm)
        PullToRefreshBox(
            refreshing,
            onRefresh = {
                scope.launch {
                    refreshing = true
                    try {
                        vm.search(state.query, saveRecent = false)?.join()
                    } finally {
                        refreshing = false
                    }
                }
            },
            modifier = Modifier.weight(1f),
        ) {
            val listState = rememberLazyListState()
            // Page in more results 5 cards from the end.
            LoadMoreNearEnd(listState, fromEnd = 5, page = state.posts.size to state.postsAfter, onLoadMore = vm::loadMorePosts)
            LazyColumn(
                Modifier.fillMaxSize(),
                state = listState,
                contentPadding = PaddingValues(start = 10.dp, top = 6.dp, end = 10.dp, bottom = 130.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                if (state.posts.isEmpty()) {
                    item {
                        Spacer(Modifier.height(120.dp))
                        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { Text("No posts found") }
                    }
                } else {
                    items(state.posts, key = { it.id }, contentType = { "post_${it.type}" }) { PostCard(it) }
                    if (state.loadingMore) {
                        item(key = "__more") {
                            Box(Modifier.fillMaxWidth().padding(16.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun FilterBar(state: SearchState, vm: SearchViewModel) {
    val cs = MaterialTheme.colorScheme
    var timeOpen by remember { mutableStateOf(false) }
    LazyRow(
        contentPadding = PaddingValues(start = 10.dp, top = 8.dp, end = 10.dp, bottom = 2.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        items(SEARCH_SORTS.entries.toList(), key = { it.key }) { e ->
            FilterChip(
                selected = state.sort == e.key,
                onClick = { vm.setSort(e.key) },
                label = { Text(e.value) },
                shape = CircleShape,
                border = null,
                colors = FilterChipDefaults.filterChipColors(containerColor = cs.surfaceContainerHigh),
            )
        }
        if (state.sort == "top") {
            item(key = "time") {
                Box(Modifier.padding(start = 6.dp)) {
                    AssistChip(
                        onClick = { timeOpen = true },
                        label = { Text(SEARCH_TIMES[state.time] ?: "All time") },
                        leadingIcon = { Icon(Icons.Rounded.Schedule, null, Modifier.size(16.dp)) },
                        shape = CircleShape,
                        border = null,
                        colors = AssistChipDefaults.assistChipColors(containerColor = cs.surfaceContainerHigh),
                    )
                    DropdownMenu(timeOpen, onDismissRequest = { timeOpen = false }) {
                        for ((k, label) in SEARCH_TIMES) {
                            DropdownMenuItem(
                                text = { Text(label) },
                                trailingIcon = if (k == state.time) ({ Icon(Icons.Rounded.Check, null, Modifier.size(18.dp)) }) else null,
                                onClick = {
                                    timeOpen = false
                                    vm.setTime(k)
                                },
                            )
                        }
                    }
                }
            }
        }
    }
}
