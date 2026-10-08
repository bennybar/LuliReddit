package com.bennybar.luli_for_reddit.feature.feed

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.bennybar.luli_for_reddit.model.Listing
import com.bennybar.luli_for_reddit.ui.friendlyError
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** State of a [PagedSource]. */
data class PagedState<T>(
    val items: List<T> = emptyList(),
    val after: String? = null,
    val loading: Boolean = true,
    val loadingMore: Boolean = false,
    val error: Throwable? = null,
) {
    val hasMore: Boolean get() = !after.isNullOrEmpty()
}

/**
 * An infinite list backed by a `fetch(after)` callback. A ViewModel, so it
 * survives navigating to a post and back (and rotation).
 */
class PagedSource<T>(private val fetch: suspend (String?) -> Listing<T>) : ViewModel() {
    private val _state = MutableStateFlow(PagedState<T>())
    val state: StateFlow<PagedState<T>> = _state
    private var lastLoaded = 0L
    private var loadJob: Job? = null
    private var started = false

    fun start() {
        if (started) return
        started = true
        load()
    }

    /** (Re)loads the first page. [silent] keeps the list (and position) on screen. */
    fun load(silent: Boolean = false): Job {
        loadJob?.cancel()
        if (!silent) _state.update { it.copy(loading = true, error = null) }
        return viewModelScope.launch {
            try {
                val listing = fetch(null)
                _state.value = PagedState(listing.items, listing.after, loading = false)
                lastLoaded = System.currentTimeMillis()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // A silent (stale) refresh failing shouldn't blow away the list.
                if (!silent) _state.update { it.copy(error = e, loading = false) }
            }
        }.also { loadJob = it }
    }

    /**
     * Returning to this list after a pushed route is popped: silently refresh
     * if the data has gone stale (no full-screen spinner, keeps the place).
     */
    fun refreshIfStale() {
        if (!_state.value.loading && System.currentTimeMillis() - lastLoaded > 5 * 60_000L) load(silent = true)
    }

    fun loadMore() {
        val s = _state.value
        if (s.loading || s.loadingMore || !s.hasMore) return
        _state.update { it.copy(loadingMore = true) }
        viewModelScope.launch {
            try {
                val listing = fetch(s.after)
                _state.update { it.copy(items = it.items + listing.items, after = listing.after, loadingMore = false) }
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                _state.update { it.copy(loadingMore = false) }
            }
        }
    }
}

/** A [PagedSource] for [key], scoped to the current screen. */
@Composable
fun <T> rememberPagedSource(key: String, fetch: suspend (String?) -> Listing<T>): PagedSource<T> {
    val source = viewModel(key = key) { PagedSource(fetch) }
    LaunchedEffect(source) { source.start() }
    return source
}

/** Generic infinite-scroll list with pull-to-refresh. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun <T> PagedList(
    source: PagedSource<T>,
    itemKey: (T) -> Any,
    modifier: Modifier = Modifier,
    contentPadding: PaddingValues = PaddingValues(start = 10.dp, top = 8.dp, end = 10.dp, bottom = 130.dp),
    emptyLabel: String = "Nothing here",
    contentType: (T) -> Any? = { null },
    itemContent: @Composable (T) -> Unit,
) {
    val state by source.state.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    var refreshing by remember { mutableStateOf(false) }
    var resumedOnce by rememberSaveable { mutableStateOf(false) }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) {
        if (resumedOnce) source.refreshIfStale() else resumedOnce = true
    }
    fun refresh() {
        scope.launch {
            refreshing = true
            try {
                source.load().join()
            } finally {
                refreshing = false
            }
        }
    }

    when {
        state.loading && state.items.isEmpty() -> Box(modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            CircularProgressIndicator()
        }
        state.error != null -> LazyColumn(modifier.fillMaxSize()) {
            item {
                Column(Modifier.fillMaxWidth().padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("Could not load.\n${friendlyError(state.error)}", textAlign = TextAlign.Center)
                    Spacer(Modifier.height(12.dp))
                    Button(onClick = { source.load() }) { Text("Retry") }
                }
            }
        }
        state.items.isEmpty() -> PullToRefreshBox(refreshing, onRefresh = ::refresh, modifier = modifier.fillMaxSize()) {
            LazyColumn(Modifier.fillMaxSize()) {
                item {
                    Spacer(Modifier.height(120.dp))
                    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { Text(emptyLabel) }
                }
            }
        }
        else -> PullToRefreshBox(refreshing, onRefresh = ::refresh, modifier = modifier.fillMaxSize()) {
            val listState = rememberLazyListState()
            LaunchedEffect(listState, source) {
                snapshotFlow {
                    val info = listState.layoutInfo
                    (info.visibleItemsInfo.lastOrNull()?.index ?: 0) >= info.totalItemsCount - 4
                }.distinctUntilChanged().collect { nearEnd -> if (nearEnd) source.loadMore() }
            }
            val items = remember(state.items) { state.items.distinctBy(itemKey) }
            LazyColumn(
                Modifier.fillMaxSize(),
                state = listState,
                contentPadding = contentPadding,
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(items, key = itemKey, contentType = contentType) { itemContent(it) }
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
