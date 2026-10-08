package com.bennybar.luli_for_reddit.feature.foryou

import com.bennybar.luli_for_reddit.AppContainer
import com.bennybar.luli_for_reddit.data.PostSort
import com.bennybar.luli_for_reddit.model.Listing
import com.bennybar.luli_for_reddit.model.Post
import com.bennybar.luli_for_reddit.model.Subreddit
import com.bennybar.luli_for_reddit.state.UserScoped
import com.bennybar.luli_for_reddit.state.userScopedKey
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject

/**
 * The on-device For You engine + its stores (interest, keywords, doc-freq,
 * impressions, sub stats, explicit prefs, muted subs, metrics, meta), the
 * learner and the experimental Reddit Home loader.
 */
class ForYouModule(private val c: AppContainer) : UserScoped {
    private val track: () -> Boolean = { c.settings.value.trackHistory }

    val interest = InterestStore(c.prefs, track)
    val muted = MutedSubsStore(c.prefs)
    val keywords = KeywordStore(c.prefs, track)
    val impressions = ImpressionStore(c.prefs, track, c.scope)
    val explicit = ExplicitPrefsStore(c.prefs)
    val subStats = SubStatsStore(c.prefs, track)
    val docFreq = DocFreqStore(c.prefs)
    val metrics = ForYouMetrics(c.prefs, track)

    /** Why each placed post is in the feed (not persisted; per session). */
    val meta = MutableStateFlow<Map<String, ForYouMeta>>(emptyMap())

    val learner = ForYouLearner(this)
    val engine = ForYouEngine(c, this)
    val redditHome = RedditHomeEngine(c, this)

    override fun onUserChanged(username: String) {
        interest.load(username)
        muted.load(username)
        keywords.load(username)
        impressions.load(username)
        explicit.load(username)
        subStats.load(username)
        docFreq.load(username)
        metrics.load(username)
        meta.value = emptyMap()
        learner.reset()
        engine.reset()
    }

    /** Re-reads every store for the current account (after a backup restore). */
    fun reload() = onUserChanged(c.session.username)
}

/**
 * The one place For You learns from what the user does. Every call site
 * used to bump the stores itself, with drift between them (the post-detail
 * vote never taught keywords; unsave reverted interest but not keywords;
 * re-voting kept adding up).
 *
 * Learned signals respect the history-tracking switch (inside each store);
 * explicit More/Less choices live in [ExplicitPrefs] and always apply.
 */
class ForYouLearner internal constructor(private val m: ForYouModule) {
    private val seen = HashSet<String>() // impressions counted this session
    private val engaged = HashSet<String>() // posts already counted as engaged

    internal fun reset() {
        synchronized(this) {
            seen.clear()
            engaged.clear()
        }
    }

    private fun group(p: Post): String {
        val meta = m.meta.value[p.id] ?: return "other"
        return if (meta.discovery) "discovery" else "primary"
    }

    private fun learn(p: Post, subDelta: Double, titleDelta: Double) {
        m.interest.bump(p.subreddit, subDelta)
        if (titleDelta != 0.0) m.keywords.bumpTitle(p.title, titleDelta)
    }

    /** Opened, read 30s+, or voted: counts once per post toward the subreddit's engagement rate. */
    private fun engage(p: Post, event: String) {
        m.metrics.count("$event.${group(p)}")
        if (synchronized(this) { engaged.add(p.id) }) m.subStats.engaged(p.subreddit)
    }

    /** A For You card that stayed >=60% on screen for 1s. */
    fun impression(p: Post) {
        m.impressions.record(p.id)
        if (!synchronized(this) { seen.add(p.id) }) return
        m.subStats.impression(p.subreddit)
        val meta = m.meta.value[p.id]
        m.metrics.count("impr.${group(p)}")
        if (meta != null) {
            m.metrics.count("src.${meta.source}")
            if (meta.position < 10) m.metrics.count("impr.top10")
        }
    }

    /**
     * A vote changed from [from] to [to] (-1, 0, +1). Learns only the change,
     * so up → none → up nets +1 vote, not +2, and switching up → down lands on
     * a plain downvote.
     */
    fun vote(p: Post, from: Int, to: Int) {
        if (from == to) return
        fun sub(d: Int) = if (d == 1) 2.0 else if (d == -1) -1.5 else 0.0
        fun kw(d: Int) = if (d == 1) 1.0 else if (d == -1) -0.8 else 0.0
        learn(p, sub(to) - sub(from), kw(to) - kw(from))
        if (to != 0) engage(p, "vote")
    }

    fun save(p: Post, saved: Boolean) = learn(p, if (saved) 3.0 else -3.0, if (saved) 1.5 else -1.5)

    fun open(p: Post) {
        learn(p, 0.5, 0.0)
        engage(p, "open")
    }

    fun viewMedia(p: Post) = learn(p, 1.0, 0.0)

    /** Commenting is the strongest engagement signal there is. */
    fun comment(p: Post) = learn(p, 2.5, 1.0)

    fun share(p: Post) = learn(p, 1.5, 0.75)

    /** Time in the thread: 30s+ ([long] = 2min+, on top of it). */
    fun read(p: Post, long: Boolean = false) {
        learn(p, if (long) 1.5 else 1.0, if (long) 1.0 else 0.5)
        if (!long) engage(p, "read30")
    }

    /** Backed out within 3 seconds. */
    fun bounce(p: Post) = learn(p, -0.5, 0.0)

    /** Explicit "More/Less from r/x" (+1 / -1 / 0 to clear). */
    fun subPreference(p: Post, value: Int) {
        m.explicit.setSub(p.subreddit, value)
        if (value != 0) m.metrics.count(if (value > 0) "more" else "less")
    }

    /** Explicit "More/Less about 'topic'". */
    fun topicPreference(topic: String, value: Int) {
        m.explicit.setTopic(topic, value)
        if (value != 0) m.metrics.count(if (value > 0) "more" else "less")
    }
}

/** One page of For You, plus what the next page and the UI need. */
class ForYouPage(
    val listing: Listing<Post>,
    val cursors: Map<String, String>,
    val leftovers: List<Candidate>,
    val meta: Map<String, ForYouMeta>,
    val candidateTitles: List<String>, // for word rarity (IDF)
)

/**
 * "For You (Beta)" — a transparent, client-side personalized feed.
 *
 * Reddit's real Home ranking is server-side ML and is NOT exposed to the
 * API, so this approximates it: fetch candidates from the sources that
 * matter to the user, then rank them on-device ([rankForYou]).
 */
class ForYouEngine internal constructor(private val c: AppContainer, private val m: ForYouModule) {
    // The previous page's unplaced candidates, and which candidate
    // communities to sample next (rotated each refresh).
    @Volatile private var leftovers: List<Candidate> = emptyList()
    private var communityTurn = 0

    private val _progress = MutableStateFlow(0)

    /** Candidate posts gathered so far while the first page loads (for the loading deck). */
    val progress: StateFlow<Int> = _progress

    internal fun reset() {
        leftovers = emptyList()
        communityTurn = 0
    }

    /**
     * First page when [after] is null, else the page after that cursor.
     * [loaded] = posts currently shown (excluded from later pages; a refresh
     * demotes the old top 10). Posts carry feedReason.
     */
    suspend fun page(after: String?, loaded: List<Post>): Listing<Post> {
        val firstPage = after == null
        if (firstPage) _progress.value = 0
        if (firstPage) seedIfNeeded()
        val page = getForYouFeed(
            inputs = rankInputs(firstPage, loaded),
            communities = if (firstPage) candidateCommunities() else emptyList(),
            cursors = after, // null = first page; else the encoded cursor bundle
            excludeIds = if (firstPage) emptySet() else loaded.mapTo(HashSet()) { it.id },
            carryOver = if (firstPage) emptyList() else leftovers,
        )
        leftovers = page.leftovers
        m.meta.value = if (firstPage) page.meta else m.meta.value + page.meta
        withContext(Dispatchers.Default) { m.docFreq.observe(page.candidateTitles) }
        for (p in page.listing.items) m.metrics.count("src.ranked.${page.meta[p.id]?.source ?: "other"}")
        val user = c.session.username
        if (firstPage && user.isNotEmpty()) {
            // In the background: the page is ready; saving it shouldn't hold it up.
            val items = page.listing.items
            c.scope.launch(Dispatchers.IO) { saveForYouPage(c.context, user, items, c.repository::rawPost) }
        }
        return page.listing
    }

    private fun subsSnapshotFile(user: String) = java.io.File(c.context.filesDir, "fy_subs_${user.lowercase()}.json")

    /** (favourites, subscribed), lowercase names, from the last fetched subscription list. */
    private suspend fun loadSubsSnapshot(user: String): Pair<Set<String>, Set<String>>? = withContext(Dispatchers.IO) {
        if (user.isEmpty()) return@withContext null
        runCatching {
            val o = com.bennybar.luli_for_reddit.core.AppJson.parseToJsonElement(subsSnapshotFile(user).readText()).jsonObject
            fun set(k: String) = (o[k] as kotlinx.serialization.json.JsonArray).mapTo(LinkedHashSet()) { (it as JsonPrimitive).content }
            set("fav") to set("sub")
        }.getOrNull()
    }

    private suspend fun saveSubsSnapshot(user: String, subs: List<Subreddit>) = withContext(Dispatchers.IO) {
        if (user.isEmpty()) return@withContext
        fun arr(names: List<String>) = kotlinx.serialization.json.JsonArray(names.map { JsonPrimitive(it) })
        val json = JsonObject(
            mapOf(
                "fav" to arr(subs.filter { it.userHasFavorited }.map { it.name.lowercase() }),
                "sub" to arr(subs.map { it.name.lowercase() }),
            ),
        )
        runCatching { subsSnapshotFile(user).writeText(json.toString()) }
    }

    /** The last saved first page minus posts opened since, to paint instantly. */
    suspend fun cachedFirstPage(): Listing<Post>? {
        val user = c.session.username
        if (user.isEmpty()) return null
        val opened = c.history.ids.value
        val posts = loadForYouPage(c.context, user, opened, "foryou") ?: return null
        return Listing(posts, after = null)
    }

    /** Snapshot of everything For You learned, for the ranker. */
    private fun rankInputs(firstPage: Boolean, loaded: List<Post>): RankInputs {
        val kw = m.keywords
        val df = m.docFreq
        return RankInputs(
            interest = m.interest.value,
            subStats = m.subStats.value,
            explicit = m.explicit.value,
            keywordScore = { t -> kw.scoreTitle(t, df::idf) },
            topKeyword = { t -> kw.topKeywordIn(t, df::idf) },
            muted = m.muted.value,
            openedAt = c.history.state.value.associate { it.id to it.viewedAt },
            impressions = m.impressions::count,
            // A refresh makes room: the old top 10 is demoted a little.
            previousTop = if (firstPage) loaded.take(10).mapTo(HashSet()) { it.id } else emptySet(),
            // Stories already shown on earlier pages count toward repeats.
            previousTitles = if (firstPage) emptyList() else loaded.asReversed().take(100).map { it.title },
            discoveryAppetite = m.metrics.discoveryAppetite(),
        )
    }

    /**
     * Communities you've dipped into but don't follow (0.5 ≤ interest < 2),
     * plus ones you asked for more of: three per refresh, rotating, as
     * personalised discovery instead of r/popular alone.
     */
    private fun candidateCommunities(): List<String> {
        val explicitMore = m.explicit.value.subs.filter { it.value > 0 }.keys
        val visited = m.interest.value.entries
            .filter { it.value >= 0.5 && it.value < K_ENGAGED_INTEREST }
            .sortedByDescending { it.value }
            .map { it.key }
        val all = LinkedHashSet<String>().apply { addAll(explicitMore); addAll(visited) }.toList()
        if (all.isEmpty()) return emptyList()
        val start = (communityTurn++ * 3) % all.size
        return (0 until minOf(3, all.size)).map { all[(start + it) % all.size] }
    }

    /**
     * Cold start: the first time For You runs for an account, seed its model
     * from the user's own Reddit activity (their upvoted and saved posts — data
     * Reddit already holds for them, nothing third-party) plus local history,
     * so day one already prefers what they actually like. Once per account,
     * and only while history tracking is on.
     */
    private suspend fun seedIfNeeded() {
        if (!c.settings.value.trackHistory) return
        val session = c.session.session ?: return
        if (session.anonymous || session.username.isEmpty()) return
        val key = userScopedKey(c.prefs, session.username, "fy_seeded")
        if (c.prefs.getBool(key) == true) return
        c.prefs.setBool(key, true) // don't retry every page on failure

        val repo = c.repository
        val user = session.username
        val (upvoted, saved) = coroutineScope {
            val up = async { orNull { repo.getUserPosts(user, where = "upvoted", limit = 100).items } ?: emptyList() }
            val sv = async { orNull { repo.getUserSaved(user, limit = 100).items.filterIsInstance<Post>() } ?: emptyList() }
            up.await() to sv.await()
        }

        val deltas = LinkedHashMap<String, Double>()
        fun add(sub: String, d: Double) {
            val k = sub.lowercase()
            deltas[k] = ((deltas[k] ?: 0.0) + d).coerceIn(0.0, 6.0)
        }
        for (p in upvoted) add(p.subreddit, 1.0)
        for (p in saved) add(p.subreddit, 2.0)
        for (e in c.history.state.value) add(e.subreddit, 0.3)
        m.interest.seed(deltas)
        m.keywords.seedTitles((upvoted + saved).map { it.title }, 0.3)
    }

    /**
     * Candidates: /best (subscriptions; paginated), rising and r/popular
     * (paginated), and on the first page hot posts from favourites, the most
     * engaged communities and a few [communities] the user has visited.
     * [carryOver] is the previous page's unplaced pool.
     */
    private suspend fun getForYouFeed(
        inputs: RankInputs,
        communities: List<String>,
        cursors: String?, // JSON cursor bundle from a previous page's `after`
        excludeIds: Set<String>,
        carryOver: List<Candidate>,
    ): ForYouPage {
        var prev: Map<String, String?> = emptyMap()
        if (!cursors.isNullOrEmpty()) {
            try {
                prev = com.bennybar.luli_for_reddit.core.AppJson.parseToJsonElement(cursors).jsonObject
                    .mapValues { (it.value as? JsonPrimitive)?.takeIf { p -> p.isString }?.content }
            } catch (_: Exception) {
            }
        }
        var page: ForYouPage? = null
        // An empty page (everything failed, or all muted/seen) retries the next
        // cursors once before ending the feed — it used to stop dead.
        for (attempt in 0 until 2) {
            val pg = forYouPage(inputs, communities, prev, excludeIds, if (attempt == 0) carryOver else emptyList())
            page = pg
            if (pg.listing.items.isNotEmpty() || pg.cursors.isEmpty()) break
            prev = pg.cursors
        }
        return page!!
    }

    private suspend fun forYouPage(
        inputs: RankInputs,
        communities: List<String>,
        prev: Map<String, String?>,
        excludeIds: Set<String>,
        carryOver: List<Candidate>,
    ): ForYouPage = coroutineScope {
        val repo = c.repository
        val firstPage = prev.isEmpty()
        val muted = inputs.muted

        // Subreddits you engage with most (learned on-device), even if not
        // favourited. Local data, so known before any request goes out.
        val topInterest = inputs.interest.entries
            .filter { it.value >= K_ENGAGED_INTEREST && it.key !in muted }
            .sortedByDescending { it.value }
            .take(5)
            .map { it.key }

        // Each source: its listing, or null if it failed / timed out. Secondary
        // sources get a short timeout so the slowest community doesn't decide how
        // long the page takes.
        // The first real failure (not a timeout), to report if nothing at all loads.
        var firstError: Exception? = null
        fun source(secondary: Boolean = true, f: suspend () -> Listing<Post>): Deferred<Listing<Post>?> = async {
            try {
                if (secondary) withTimeout(2500) { f() } else f()
            } catch (e: kotlinx.coroutines.TimeoutCancellationException) {
                null
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (firstError == null) firstError = e
                null
            }?.also { l -> if (firstPage) _progress.update { it + l.items.size } }
        }

        // A cursor of "" means "start this source from the top" (its first
        // fetch failed); a missing key means the source is exhausted.
        fun live(k: String) = firstPage || prev.containsKey(k)
        fun after(k: String): String? = prev[k]?.ifEmpty { null }
        val none = async<Listing<Post>?> { null }

        // Favourites and subscriptions: from the last snapshot when there is one,
        // so favourites go out with everything else instead of waiting ~2s for
        // the subscription list; the live list refreshes the snapshot for next time.
        val user = c.session.username
        val snapshot = loadSubsSnapshot(user)
        val subsF = if (snapshot == null) {
            async { orNull { repo.getSubscribedSubreddits() } ?: emptyList<Subreddit>() }
        } else {
            c.scope.launch(Dispatchers.IO) { orNull { repo.getSubscribedSubreddits() }?.let { saveSubsSnapshot(user, it) } }
            null
        }
        val bestF = if (live("best")) {
            source(secondary = false) {
                repo.getPosts(sort = PostSort.BEST, limit = if (firstPage) 100 else 50, after = after("best"))
            }
        } else none
        val risingF = if (live("rising")) {
            source { repo.getPosts(sort = PostSort.RISING, limit = 25, after = after("rising")) }
        } else none
        val popularF = if (live("popular")) {
            source {
                repo.getPosts(subreddit = "popular", sort = PostSort.HOT, limit = if (firstPage) 20 else 15, after = after("popular"))
            }
        } else none
        val interestF = if (firstPage) topInterest.map { s ->
            source { repo.getPosts(subreddit = s, sort = PostSort.HOT, limit = 8) }
        } else emptyList()
        val communityF = if (firstPage) communities.filter { it !in muted }.map { s ->
            source { repo.getPosts(subreddit = s, sort = PostSort.HOT, limit = 6) }
        } else emptyList()

        val (favourites, subscribed) = snapshot ?: run {
            val mySubs = subsF!!.await()
            if (mySubs.isNotEmpty()) saveSubsSnapshot(user, mySubs)
            mySubs.filter { it.userHasFavorited }.mapTo(LinkedHashSet()) { it.name.lowercase() } to
                mySubs.mapTo(HashSet()) { it.name.lowercase() }
        }
        // Favourites go out the moment the list is known, while the rest is still
        // in flight. One already fetched as a top interest isn't fetched twice.
        val favouriteF = if (firstPage) favourites.take(8)
            .filter { it !in topInterest && it !in muted }
            .map { f -> source { repo.getPosts(subreddit = f, sort = PostSort.HOT, limit = 10) } }
        else emptyList()

        val best = bestF.await()
        val rising = risingF.await()
        val popular = popularF.await()
        val ids = HashSet(excludeIds)
        val pool = ArrayList<Candidate>()
        fun add(l: Listing<Post>?, src: String) {
            for (p in l?.items ?: emptyList()) if (ids.add(p.id)) pool.add(Candidate(p, src))
        }

        for (cand in carryOver) if (ids.add(cand.post.id)) pool.add(Candidate(cand.post, "carry"))
        add(best, "best")
        add(rising, "rising")
        add(popular, "popular")
        for (l in favouriteF.awaitAll()) add(l, "favourite")
        for (l in interestF.awaitAll()) add(l, "interest")
        for (l in communityF.awaitAll()) add(l, "community")

        // Every source failed (offline, rate-limited…): say so, rather than
        // showing an empty feed that just ends.
        if (pool.isEmpty()) firstError?.let { throw it }
        val result = withContext(Dispatchers.Default) {
            rankForYou(pool, inputs.withSubscriptions(favourites, subscribed))
        }

        // Next cursors. A source that failed keeps its place (it used to be
        // dropped for the rest of the session — one timeout on /best and the
        // feed quietly became r/popular); an exhausted one is left out.
        val next = LinkedHashMap<String, String>()
        for ((key, listing) in listOf("best" to best, "rising" to rising, "popular" to popular)) {
            if (!live(key)) continue
            if (listing == null) {
                next[key] = prev[key] ?: ""
            } else if (!listing.after.isNullOrEmpty()) {
                next[key] = listing.after
            }
        }
        val hasMore = (result.ranked.isNotEmpty() || result.leftovers.isNotEmpty()) && next.isNotEmpty()
        ForYouPage(
            listing = Listing(
                result.ranked,
                after = if (hasMore) JsonObject(next.mapValues { JsonPrimitive(it.value) }).toString() else null,
            ),
            cursors = next,
            leftovers = result.leftovers,
            meta = result.meta,
            candidateTitles = pool.map { it.post.title },
        )
    }
}

/** Runs [block], returning null on failure (cancellation still propagates). */
internal suspend fun <T> orNull(block: suspend () -> T): T? =
    try {
        block()
    } catch (e: CancellationException) {
        // A secondary source's timeout is a TimeoutCancellationException: a failure, not a cancel.
        if (e is kotlinx.coroutines.TimeoutCancellationException) null else throw e
    } catch (e: Exception) {
        null
    }
