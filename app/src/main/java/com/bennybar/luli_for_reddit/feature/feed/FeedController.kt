package com.bennybar.luli_for_reddit.feature.feed

import androidx.compose.runtime.Immutable
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.data.PostSort
import com.bennybar.luli_for_reddit.data.TopTime
import com.bennybar.luli_for_reddit.model.Listing
import com.bennybar.luli_for_reddit.model.Post
import com.bennybar.luli_for_reddit.ui.friendlyError
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

@Immutable
data class FeedState(
    val posts: List<Post>,
    val sort: PostSort,
    val time: TopTime,
    val after: String? = null,
    val loadingMore: Boolean = false,
    val hasPending: Boolean = false, // a fresh page is staged behind a "New posts" pill
) {
    val hasMore: Boolean get() = !after.isNullOrEmpty()
}

/** The feed's async state (Riverpod's AsyncValue<FeedState>). */
sealed interface FeedUi {
    data object Loading : FeedUi
    data class Error(val error: Throwable) : FeedUi
    data class Data(val state: FeedState) : FeedUi
}

/**
 * Feed for the frontpage (key == ""), a subreddit (key == name) or a
 * multireddit (key == "m::username::multiname"). Owned by [FeedModule], so it
 * outlives the screen (back navigation repaints instantly).
 */
class FeedController(val key: String) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val _ui = MutableStateFlow<FeedUi>(FeedUi.Loading)
    val ui: StateFlow<FeedUi> = _ui

    private val subreddit: String? get() = key.ifEmpty { null }
    private val repo get() = app.repository

    private var sort: PostSort = app.settings.value.defaultSort
    private var time: TopTime = TopTime.DAY
    private var started = false
    private var cacheConsulted = false
    private var showingCache = false // a cached page is on screen, fresh one in flight

    // Bumped whenever the list is replaced (load, refresh, sort, "New posts"),
    // so a page that was in flight for the old list is dropped, not appended.
    private var generation = 0
    private var lastLoaded = 0L
    private var buildJob: Job? = null

    /** A multireddit feed key looks like `m::username::multiname`. */
    private val multi: Pair<String, String>? = run {
        if (!key.startsWith("m::")) return@run null
        val parts = key.split("::")
        if (parts.size != 3) null else parts[1] to parts[2]
    }

    private val isFrontpage get() = key.isEmpty()

    /** How long a loaded frontpage is kept before returning to it loads a new one (Settings → Keep feed for). */
    private val keepMillis get() = app.settings.value.feedKeepMinutes * 60_000L
    private val forYou get() = isFrontpage && app.settings.value.forYouFeed

    /** Experimental Reddit Home (opt-in after a risk warning in Settings). */
    private val redditHome: Boolean
        get() {
            val s = app.settings.value
            return isFrontpage && s.redditHomeAllowed && s.redditHomeFeed
        }

    private val current: FeedState? get() = (_ui.value as? FeedUi.Data)?.state

    /**
     * Home and For You open with the shuffling deck and deal their cards in,
     * rather than painting the last saved page and then swapping it out.
     */
    val deckMode: Boolean get() = redditHome || forYou

    /** First use: builds the feed (Riverpod builds a provider on first watch). */
    fun start() {
        if (started) return
        started = true
        if (app.restoredProcess && deckMode) restoreOrBuild() else rebuild(showLoading = deckMode)
    }

    /**
     * Back after Android killed the app in the background: Home / For You show
     * the page saved with the last load if it's younger than the "Keep feed for" time,
     * exactly as if the app had stayed open; otherwise they load as usual.
     */
    private fun restoreOrBuild() {
        _ui.value = FeedUi.Loading
        buildJob = scope.launch {
            val savedAt = runCatching {
                if (redditHome) app.forYou.redditHome.cachedFirstPageTime() else app.forYou.engine.cachedFirstPageTime()
            }.getOrNull()
            val page = if (savedAt != null && System.currentTimeMillis() - savedAt < keepMillis) cachedFirstPage() else null
            if (page != null) {
                lastLoaded = savedAt!!
                _ui.value = FeedUi.Data(FeedState(page.items, sort, time, page.after))
            } else {
                rebuild(showLoading = true)
            }
        }
    }

    /**
     * Returning to the frontpage (from a post, or the app from the
     * background): it keeps its posts for the "Keep feed for" time; after that it loads
     * anew, as on a fresh launch. Pull-to-refresh is the way to replace it
     * sooner.
     */
    fun refreshIfExpired() {
        if (isBuilding || current == null) return
        if (System.currentTimeMillis() - lastLoaded < keepMillis) return
        rebuild(showLoading = deckMode)
    }

    fun dispose() {
        if (isFrontpage) app.forYou.redditHome.dispose()
        scope.cancel()
    }

    /**
     * "Hide read posts": drops posts already in history as each page arrives.
     * Filtering when fetched rather than live keeps a post you've just read
     * (or scrolled past) from vanishing under you; the next load skips it.
     * For You has its own live auto-hide option.
     */
    private fun dropRead(listing: Listing<Post>): Listing<Post> {
        if (forYou || !app.settings.value.hideReadPosts) return listing
        val read = app.history.ids.value
        if (read.isEmpty()) return listing
        return Listing(listing.items.filter { it.id !in read }, listing.after, listing.fromCache)
    }

    private suspend fun fetch(after: String? = null): Listing<Post> = dropRead(fetchRaw(after))

    private suspend fun fetchRaw(after: String?): Listing<Post> {
        val loaded = current?.posts ?: emptyList()
        // Reddit Home (falls back to For You itself, with a notice) and For
        // You are ranked/loaded by the For You module.
        if (redditHome) return app.forYou.redditHome.page(after, loaded)
        if (forYou) return app.forYou.engine.page(after, loaded)
        val m = multi
        if (m != null) return repo.getMultiPosts(m.first, m.second, sort = sort, time = time, after = after)
        return repo.getPosts(subreddit = subreddit, sort = sort, time = time, after = after)
    }

    private suspend fun cachedFirstPage(): Listing<Post>? {
        // The last Home / For You page, minus posts opened since, while the
        // fresh one loads.
        if (redditHome) return runCatching { app.forYou.redditHome.cachedFirstPage() }.getOrNull()
        if (forYou) return runCatching { app.forYou.engine.cachedFirstPage() }.getOrNull()
        if (multi != null) return null
        return try {
            repo.cachedPosts(subreddit = subreddit, sort = sort, time = time)?.let(::dropRead)
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            null
        }
    }

    private suspend fun build(): FeedState {
        generation++
        // Paint the last cached page straight away on a cold open, before the
        // network answers: parsing a page costs milliseconds, the request costs
        // hundreds. Only once per feed — a refresh or sort change already has
        // intent behind it and shouldn't flash an older page.
        var cached: Listing<Post>? = null
        // In deck mode the saved page is only a fallback for a failed load, so
        // it's read only then (it used to delay every load by a disk read).
        if (!cacheConsulted && !deckMode) {
            cacheConsulted = true
            cached = cachedFirstPage()
            if (cached != null) {
                showingCache = true
                _ui.value = FeedUi.Data(FeedState(cached.items, sort, time, cached.after))
            }
        }
        // Retry once: a cold-start request can fail while the token is being
        // refreshed for the first time.
        val listing = try {
            try {
                fetch()
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                fetch()
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // Keep the cached page rather than replacing it with an error: it's
            // still the most useful thing to show, and pull-to-refresh retries.
            if (cached == null && deckMode) cached = cachedFirstPage()
            if (cached == null) throw e
            showingCache = false
            return FeedState(cached.items, sort, time, cached.after)
        }
        showingCache = false
        lastLoaded = System.currentTimeMillis()
        return FeedState(listing.items, sort, time, listing.after)
    }

    /**
     * (Re)builds the feed. A newer build cancels an older one still in
     * flight (e.g. a quick second sort change), so a slow stale page can't
     * land on top of the newer list.
     */
    private fun rebuild(showLoading: Boolean): Job {
        buildJob?.cancel()
        val hadData = current != null
        if (showLoading) _ui.value = FeedUi.Loading
        val job = scope.launch {
            try {
                _ui.value = FeedUi.Data(build())
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // A failed pull-to-refresh keeps the posts on screen and says why.
                if (!showLoading && hadData && current != null) {
                    app.navigatorOrNull?.showSnackbar(friendlyError(e))
                } else {
                    _ui.value = FeedUi.Error(e)
                }
            }
        }
        buildJob = job
        return job
    }

    val isBuilding: Boolean get() = buildJob?.isActive == true

    fun changeSort(sort: PostSort, time: TopTime? = null) {
        this.sort = sort
        if (time != null) this.time = time
        // Persist the frontpage sort + turn off the For You / Home feeds.
        if (isFrontpage) {
            val s = app.settings
            s.setDefaultSort(sort)
            s.setForYouFeed(false)
            s.setRedditHomeFeed(false)
        }
        rebuild(showLoading = true)
    }

    /** Switches the frontpage to the "For You (Beta)" feed (persisted). */
    fun selectForYou() {
        app.settings.setForYouFeed(true)
        rebuild(showLoading = true)
    }

    /** Switches the frontpage to the experimental Reddit Home (persisted). */
    fun selectRedditHome() {
        app.settings.setRedditHomeFeed(true)
        rebuild(showLoading = true)
    }

    /** Pull-to-refresh: reloads with the current list kept on screen. Returns when done. */
    suspend fun refresh() {
        started = true
        rebuild(showLoading = deckMode || (current == null && _ui.value !is FeedUi.Error)).join()
    }

    /** Retry from the error view. */
    fun retry() {
        rebuild(showLoading = true)
    }

    // A freshly-fetched first page staged behind the "New posts" pill.
    private var pending: List<Post>? = null
    private var pendingAfter: String? = null

    /**
     * When returning to a stale feed, quietly fetch the first page. If it has
     * posts we're not already showing, stage them behind a "New posts" pill
     * instead of yanking the list out from under the user.
     */
    fun refreshIfStale(maxAgeMillis: Long = 5 * 60_000L) {
        if (isBuilding) return
        val cur = current ?: return
        if (cur.hasPending) return // already staged
        if (System.currentTimeMillis() - lastLoaded < maxAgeMillis) return
        val gen = generation
        scope.launch {
            try {
                val listing = fetch()
                lastLoaded = System.currentTimeMillis()
                if (gen != generation) return@launch
                val latest = current ?: return@launch
                val currentIds = latest.posts.mapTo(HashSet()) { it.id }
                // For You re-ranks rising posts every time, so "anything new" was
                // almost always true; it needs 3 new posts in the new top 10.
                val hasNew = if (forYou) {
                    listing.items.take(10).count { it.id !in currentIds } >= 3
                } else {
                    listing.items.any { it.id !in currentIds }
                }
                if (hasNew) {
                    pending = listing.items
                    pendingAfter = listing.after
                    _ui.value = FeedUi.Data(latest.copy(hasPending = true))
                }
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) { /* leave the current feed in place */ }
        }
    }

    /** Swaps the staged "New posts" page in (called when the pill is tapped). */
    fun applyPending() {
        val cur = current ?: return
        val p = pending ?: return
        generation++
        // (A page that was loading for the old list is dropped, so clear its spinner.)
        _ui.value = FeedUi.Data(cur.copy(posts = p, after = pendingAfter, hasPending = false, loadingMore = false))
        pending = null
        pendingAfter = null
    }

    fun loadMore() {
        val cur = current ?: return
        if (!cur.hasMore || cur.loadingMore) return
        // Paging off a cached page would be overwritten by the fresh one.
        if (showingCache) return
        val gen = generation
        _ui.value = FeedUi.Data(cur.copy(loadingMore = true))
        scope.launch {
            try {
                val listing = fetch(after = cur.after)
                if (gen != generation) return@launch // the list was replaced meanwhile
                // Append to the latest state, which may carry a staged "New posts" page.
                val latest = current ?: cur
                _ui.value = FeedUi.Data(latest.copy(posts = latest.posts + listing.items, after = listing.after, loadingMore = false))
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                if (gen != generation) return@launch
                val latest = current ?: cur
                _ui.value = FeedUi.Data(latest.copy(loadingMore = false))
            }
        }
    }
}
