package com.bennybar.luli_for_reddit.feature.digest

import com.bennybar.luli_for_reddit.AppContainer
import com.bennybar.luli_for_reddit.core.net.RedditApiException
import com.bennybar.luli_for_reddit.data.PostSort
import com.bennybar.luli_for_reddit.data.TopTime
import com.bennybar.luli_for_reddit.model.Post
import com.bennybar.luli_for_reddit.state.UserScoped
import com.bennybar.luli_for_reddit.state.userScopedKey
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.time.LocalDate

/**
 * The Digest (docs/digest-spec.md): builds and refreshes today's digest from the top
 * posts of the day in the chosen communities, and keeps the last week of them.
 */
class DigestModule(private val c: AppContainer) : UserScoped {
    val store = DigestStore(c.context, c.repository::rawPost)

    private val _building = MutableStateFlow(false)

    /** A build or refresh is running. */
    val building: StateFlow<Boolean> = _building

    private var job: Deferred<Outcome>? = null
    private var user = ""
    private val _chosen = MutableStateFlow<List<String>?>(null)

    /** The communities picked in Settings (lowercase), or null to follow your favourites. */
    val chosen: StateFlow<List<String>?> = _chosen

    /** How a build or refresh went. */
    sealed interface Outcome {
        /** [added]: new posts today's digest gained (all of them on a first build). */
        data class Updated(val added: Int) : Outcome
        /** Refreshed moments ago: shown as it is. */
        data object UpToDate : Outcome
        data object NoCommunities : Outcome
        data object SignedOut : Outcome
        data class Failed(val error: Throwable) : Outcome
    }

    override fun onUserChanged(username: String) {
        job?.cancel()
        job = null
        user = username
        _chosen.value = c.prefs.getStringList(subsKey())
        store.onUserChanged(username)
    }

    private fun subsKey() = userScopedKey(c.prefs, user, "digestSubs")

    /** Sets the communities (lowercase names, at most [MAX_COMMUNITIES]); null follows your favourites again. */
    fun setCommunities(names: List<String>?) {
        val list = names?.map { it.lowercase() }?.distinct()?.take(MAX_COMMUNITIES)
        if (list == null) c.prefs.remove(subsKey()) else c.prefs.setStringList(subsKey(), list)
        _chosen.value = list
    }

    /** Your starred favourites, from the subscription list (cached; asked for once if it isn't). */
    suspend fun favourites(): List<String> {
        val subs = c.repository.loadedSubscriptions ?: c.repository.getSubscribedSubreddits()
        return subs.filter { it.userHasFavorited }.map { it.name.lowercase() }
    }

    /** The communities a digest is built from. */
    suspend fun communities(): List<String> = (_chosen.value ?: favourites()).take(MAX_COMMUNITIES)

    fun today(): String = LocalDate.now().toString()

    /**
     * Builds today's digest, or refreshes it: only posts not judged yet are judged
     * ([mergeDigest]). [manual]: the user asked (pull to refresh), so one within
     * [UP_TO_DATE_MS] of the last just shows what's there. [rebuild]: forget today's
     * and start over. One at a time: a second call while one runs gets its result.
     */
    suspend fun refresh(manual: Boolean, rebuild: Boolean = false): Outcome {
        job?.takeIf { it.isActive }?.let { return it.await() }
        val j = c.scope.async { build(manual, rebuild) }
        job = j
        return j.await()
    }

    /** Opening the Digest: builds today's when there is none, or it's more than [STALE_MS] old. */
    suspend fun refreshIfStale(): Outcome? {
        val d = store.today(today())
        if (d != null && System.currentTimeMillis() - d.refreshedAt < STALE_MS) return null
        return refresh(manual = false)
    }

    fun markSeen() = store.markSeen(today(), System.currentTimeMillis())

    private suspend fun build(manual: Boolean, rebuild: Boolean): Outcome {
        val session = c.session.session
        if (session == null || session.anonymous) return Outcome.SignedOut
        val day = today()
        val now = System.currentTimeMillis()
        val prev = if (rebuild) null else store.today(day)
        if (manual && prev != null && now - prev.refreshedAt < UP_TO_DATE_MS) return Outcome.UpToDate
        _building.value = true
        try {
            val subs = communities()
            if (subs.isEmpty()) return Outcome.NoCommunities
            val filters = c.contentFilters.value
            val hidden = c.hiddenPosts.ids.value
            val candidates = fetchCandidates(subs).filter { it.id !in hidden && !filters.hides(it) }
            val size = DigestSize.of(c.settings.value.digestSize)
            val merged = mergeDigest(prev, day, candidates, c.history.ids.value, size, now)
            if (c.session.username != session.username) return Outcome.Failed(CancellationException("Account changed"))
            store.put(merged)
            return Outcome.Updated(merged.items.size - (prev?.items?.size ?: 0))
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            return Outcome.Failed(e)
        } finally {
            _building.value = false
        }
    }

    /**
     * The day's top posts in [subs]: up to eight communities a request (/r/a+b+c/top),
     * then, for a community the combined listing barely reached (big ones crowd it),
     * one request of its own while the build stays within [MAX_REQUESTS].
     */
    private suspend fun fetchCandidates(subs: List<String>): List<Post> = coroutineScope {
        val groups = subs.chunked(8)
        var firstError: Exception? = null
        val lists = groups.map { g ->
            async {
                try {
                    group(g)
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    if (firstError == null) firstError = e
                    null
                }
            }
        }.awaitAll()
        if (lists.all { it == null }) throw firstError ?: IllegalStateException("Couldn't load the communities")
        val got = lists.filterNotNull().flatten()
        val counts = got.groupingBy { it.subreddit.lowercase() }.eachCount()
        val thin = subs.filter { (counts[it] ?: 0) < 3 }.take((MAX_REQUESTS - groups.size).coerceAtLeast(0))
        val more = thin.map { s ->
            async {
                try {
                    c.repository.getPosts(subreddit = s, sort = PostSort.TOP, time = TopTime.DAY, limit = 10).items
                } catch (e: CancellationException) {
                    throw e
                } catch (_: Exception) {
                    emptyList()
                }
            }
        }.awaitAll()
        (got + more.flatten()).distinctBy { it.id }
    }

    private suspend fun group(subs: List<String>): List<Post> = try {
        c.repository.getPosts(subreddit = subs.joinToString("+"), sort = PostSort.TOP, time = TopTime.DAY, limit = 100).items
    } catch (e: RedditApiException) {
        // Where Reddit refuses the combined listing (403), one community at a time.
        if (e.statusCode != 403 || subs.size < 2) throw e
        coroutineScope {
            subs.map { s ->
                async {
                    try {
                        c.repository.getPosts(subreddit = s, sort = PostSort.TOP, time = TopTime.DAY, limit = 10).items
                    } catch (e: CancellationException) {
                        throw e
                    } catch (_: Exception) {
                        emptyList()
                    }
                }
            }.awaitAll().flatten()
        }
    }

    companion object {
        const val MAX_COMMUNITIES = 15
        /** A build's Reddit requests: the combined listings, then top-ups up to this. */
        const val MAX_REQUESTS = 6
        const val UP_TO_DATE_MS = 2 * 60_000L
        const val STALE_MS = 12 * 60 * 60_000L
    }
}
