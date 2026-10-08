package com.bennybar.luli_for_reddit.feature.feed

import com.bennybar.luli_for_reddit.AppContainer
import com.bennybar.luli_for_reddit.model.Multireddit
import com.bennybar.luli_for_reddit.state.UserScoped
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

/** An async value for a small shared list (loading / data / error). */
sealed interface Async<out T> {
    data object Loading : Async<Nothing>
    data class Data<T>(val value: T) : Async<T>
    data class Error(val error: Throwable) : Async<Nothing>
}

/**
 * Feed/home singletons: one [FeedController] per feed key (the frontpage
 * lives for the whole session; other feeds are kept in a small LRU so going
 * back repaints instantly), tab re-select signals, and the custom-feed list
 * shared by the Explore and Account tabs.
 */
class FeedModule(private val c: AppContainer) : UserScoped {
    private var frontpage: FeedController? = null
    private val feeds = object : LinkedHashMap<String, FeedController>(16, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, FeedController>?): Boolean {
            if (size <= MAX_FEEDS) return false
            eldest?.value?.dispose()
            return true
        }
    }

    /** Bumped on account change: screens re-fetch their controller. */
    private val _version = MutableStateFlow(0)
    val version: StateFlow<Int> = _version

    /** The controller for [key] ('' = frontpage, subreddit name, or `m::user::name`). */
    fun controller(key: String): FeedController {
        if (key.isEmpty()) return frontpage ?: FeedController("").also { frontpage = it }
        return feeds.getOrPut(key) { FeedController(key) }
    }

    /**
     * Bumped to ask the frontpage feed to scroll to top (or refresh if already
     * there) — e.g. when the Posts tab is tapped while already selected.
     */
    val frontpageScrollSignal = MutableStateFlow(0)

    private val reselect = HashMap<Int, MutableStateFlow<Int>>()

    /**
     * Bumped when a bottom-nav tab is re-tapped while already active, so that
     * tab's scrollable can scroll to top. Keyed by tab index (1 = Explore,
     * 2 = Inbox). (The Posts tab uses [frontpageScrollSignal], which also
     * refreshes when already at the top.)
     */
    fun tabReselect(tab: Int): MutableStateFlow<Int> = reselect.getOrPut(tab) { MutableStateFlow(0) }

    /** The update check + notifications suggestion run once per app start. */
    var startupChecksDone = false

    // --- Custom feeds (multireddits) ---

    private val _multis = MutableStateFlow<Async<List<Multireddit>>>(Async.Loading)
    val multireddits: StateFlow<Async<List<Multireddit>>> = _multis
    private var multisJob: Job? = null
    private var multisLoaded = false

    /** Loads the user's custom feeds once (or again with [force]). */
    fun loadMultireddits(force: Boolean = false) {
        if (!force && (multisLoaded || multisJob?.isActive == true)) return
        multisJob?.cancel()
        multisJob = c.scope.launch {
            if (_multis.value is Async.Error) _multis.value = Async.Loading
            try {
                _multis.value = Async.Data(c.repository.getMyMultireddits())
                multisLoaded = true
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _multis.value = Async.Error(e)
            }
        }
    }

    override fun onUserChanged(username: String) {
        frontpage?.dispose()
        frontpage = null
        feeds.values.forEach { it.dispose() }
        feeds.clear()
        multisJob?.cancel()
        multisLoaded = false
        _multis.value = Async.Loading
        _version.value++
    }

    companion object {
        private const val MAX_FEEDS = 12
    }
}
