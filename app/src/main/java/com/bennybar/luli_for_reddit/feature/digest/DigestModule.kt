package com.bennybar.luli_for_reddit.feature.digest

import com.bennybar.luli_for_reddit.AppContainer
import com.bennybar.luli_for_reddit.core.net.RedditApiException
import com.bennybar.luli_for_reddit.data.PostSort
import com.bennybar.luli_for_reddit.data.TopTime
import com.bennybar.luli_for_reddit.feature.post.AiService
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
import kotlinx.coroutines.flow.first
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
    private val _progress = MutableStateFlow<String?>(null)

    /** What the running build is doing ("Loading posts (4/15)…"), for the screen. */
    val progress: StateFlow<String?> = _progress

    /** Posts shows the Digest (its chip picked). Not a feed choice: not saved, so a launch opens the feed. */
    val onPosts = MutableStateFlow(false)

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
        onPosts.value = false
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
        store.loaded.first { it }
        val d = store.today(today())
        if (d != null && System.currentTimeMillis() - d.refreshedAt < STALE_MS) return null
        return refresh(manual = false)
    }

    fun markSeen() = store.markSeen(today(), System.currentTimeMillis())

    private suspend fun build(manual: Boolean, rebuild: Boolean): Outcome {
        val session = c.session.session
        if (session == null || session.anonymous) return Outcome.SignedOut
        store.loaded.first { it }
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
            val read = c.history.ids.value
            val s = c.settings.value
            // The AI step (spec section 6), when "Use AI" is on and there's a key, for the builds
            // it's chosen for (Settings: every build, or the day's first and Rebuild), and the
            // parts chosen: picking, the "why" lines, the overview (only on the day's first build).
            // Only posts not judged yet; an automatic build calls at most once in 12 hours.
            val first = prev == null
            val overview = s.digestOverview && first
            val key = if (s.digestAi && (first || s.digestAiBuilds == 0)) c.secureStore.openaiKey() else null
            val due = manual || first || now - prev.aiAt >= STALE_MS
            val useAi = !key.isNullOrEmpty() && due && (s.digestAiPick || s.digestAiWhy || overview)
            val baseUrl = if (s.aiUseCustomUrl) s.aiBaseUrl else "https://api.openai.com"
            val language = s.digestLanguage ?: s.aiSummaryLanguage
            suspend fun ask(posts: List<Post>, rate: Boolean): DigestAi? {
                _progress.value = if (rate) "Asking the AI about ${posts.size} posts…" else "The AI is writing about ${posts.size} posts…"
                val (system, user) = digestAiMessages(posts, interests(), size, overview, language, now, rate = rate, why = s.digestAiWhy)
                return try {
                    parseDigestAi(AiService.digest(baseUrl, key!!, s.aiModel, system, user), posts, rated = rate)
                } catch (e: CancellationException) {
                    throw e
                } catch (_: Exception) {
                    null // unreachable, refused or unreadable: by the numbers, and the screen says so
                }
            }
            val merged = if (useAi && s.digestAiPick) {
                // The AI picks, from the posts not judged yet.
                val pending = digestPending(prev, day, candidates, read, now)
                val ai = if (pending.isEmpty()) null else ask(pending, rate = true)
                mergeDigest(prev, day, candidates, read, size, now, ai, aiFailed = pending.isNotEmpty() && ai == null)
            } else {
                // The numbers pick; the AI, if wanted, only writes about the new picks.
                _progress.value = "Picking the notable posts…"
                val numbers = mergeDigest(prev, day, candidates, read, size, now)
                val added = numbers.items.filter { it.addedAt == now }.map { it.post }
                if (useAi && added.isNotEmpty() && (s.digestAiWhy || overview)) {
                    val ai = ask(added, rate = false)
                    if (ai == null) numbers.copy(aiFailed = true, aiAt = now) else explainDigest(numbers, ai, now)
                } else {
                    numbers
                }
            }
            if (c.session.username != session.username) return Outcome.Failed(CancellationException("Account changed"))
            store.put(merged)
            _progress.value = null
            return Outcome.Updated(merged.items.size - (prev?.items?.size ?: 0))
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            return Outcome.Failed(e)
        } finally {
            _building.value = false
            _progress.value = null
        }
    }

    /**
     * The day's top posts in [subs]: up to eight communities a request (/r/a+b+c/top),
     * then, for a community the combined listing barely reached (big ones crowd it),
     * one request of its own while the build stays within [MAX_REQUESTS].
     */
    private suspend fun fetchCandidates(subs: List<String>): List<Post> = coroutineScope {
        _progress.value = "Loading posts from ${subs.size} communities…"
        loaded.set(0)
        communitiesLoading = subs.size
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
        // (The website sign-in already asked each community on its own: nothing to top up.)
        val thin = if (c.client.isWebMode()) emptyList() else subs.filter { (counts[it] ?: 0) < 3 }.take((MAX_REQUESTS - groups.size).coerceAtLeast(0))
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

    private val loaded = java.util.concurrent.atomic.AtomicInteger()
    @Volatile private var communitiesLoading = 0

    private suspend fun group(subs: List<String>): List<Post> = try {
        // The website sign-in gets Reddit's web page for a combined listing, never the listing.
        if (c.client.isWebMode() && subs.size > 1) throw RedditApiException(403)
        c.repository.getPosts(subreddit = subs.joinToString("+"), sort = PostSort.TOP, time = TopTime.DAY, limit = 100).items
    } catch (e: RedditApiException) {
        // Where Reddit refuses the combined listing, one community at a time: a 403, or
        // its web page instead of the listing (a 200 that isn't JSON).
        if ((e.statusCode != 403 && e.statusCode != 200) || subs.size < 2) throw e
        coroutineScope {
            subs.map { s ->
                async {
                    try {
                        c.repository.getPosts(subreddit = s, sort = PostSort.TOP, time = TopTime.DAY, limit = 10).items
                    } catch (e: CancellationException) {
                        throw e
                    } catch (_: Exception) {
                        emptyList()
                    } finally {
                        // One community at a time: count them.
                        _progress.value = "Loading posts (${loaded.incrementAndGet()}/${communitiesLoading})…"
                    }
                }
            }.awaitAll().flatten()
        }
    }

    /** What the AI is told about you: For You's strongest words, and your More / Less choices. */
    private fun interests(): DigestInterests {
        val f = c.forYou
        val explicit = f.explicit.value
        return DigestInterests(
            keywords = f.keywords.value.entries.filter { it.value > 0 }.sortedByDescending { it.value }.take(15).map { it.key },
            moreTopics = explicit.topics.filter { it.value > 0 }.keys.toList(),
            lessTopics = explicit.topics.filter { it.value < 0 }.keys.toList(),
            moreCommunities = explicit.subs.filter { it.value > 0 }.keys.toList(),
            lessCommunities = explicit.subs.filter { it.value < 0 }.keys.toList(),
        )
    }

    companion object {
        const val MAX_COMMUNITIES = 15
        /** A build's Reddit requests: the combined listings, then top-ups up to this. */
        const val MAX_REQUESTS = 6
        const val UP_TO_DATE_MS = 2 * 60_000L
        const val STALE_MS = 12 * 60 * 60_000L
    }
}
