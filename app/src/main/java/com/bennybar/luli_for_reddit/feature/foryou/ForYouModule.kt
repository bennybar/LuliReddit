package com.bennybar.luli_for_reddit.feature.foryou

import com.bennybar.luli_for_reddit.AppContainer
import com.bennybar.luli_for_reddit.data.PostSort
import com.bennybar.luli_for_reddit.data.TopTime
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
import kotlinx.coroutines.withTimeoutOrNull
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
    /** The same per post type ("image", "video", "text", "link"): which kinds you open. */
    val typeStats = SubStatsStore(c.prefs, track, "fy_typestats")
    val docFreq = DocFreqStore(c.prefs)
    val metrics = ForYouMetrics(c.prefs, track)

    /** Why each placed post is in the feed (not persisted; per session). */
    val meta = MutableStateFlow<Map<String, ForYouMeta>>(emptyMap())

    val learner = ForYouLearner(this)
    val engine = ForYouEngine(c, this)
    val redditHome = RedditHomeEngine(c, this)

    /**
     * Explore's "Recommended for you" (#157): communities you asked For You for more
     * of, then the ones you engage with most, that you haven't joined, muted or
     * asked for less of. Built on the phone from what For You learned.
     */
    fun recommendedCommunities(subscribed: Set<String>, limit: Int = 5): List<String> {
        val asked = explicit.value.subs
        val engaged = interest.value.entries.filter { it.value >= 0.5 }.sortedByDescending { it.value }.map { it.key }
        val skip = muted.value
        return LinkedHashSet<String>().apply {
            addAll(asked.filter { it.value > 0 }.keys)
            addAll(engaged)
        }.filter { name ->
            name !in subscribed && name !in skip && (asked[name] ?: 0) >= 0 &&
                !name.startsWith("u_") && name != "all" && name != "popular"
        }.take(limit)
    }

    override fun onUserChanged(username: String) {
        interest.load(username)
        muted.load(username)
        keywords.load(username)
        impressions.load(username)
        explicit.load(username)
        subStats.load(username)
        typeStats.load(username)
        docFreq.load(username)
        metrics.load(username)
        meta.value = emptyMap()
        learner.reset()
        engine.reset()
        redditHome.cancelBlend() // the other account's Home reads
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
    private val passive = HashSet<String>() // "signal:postId" already learned this session

    /**
     * Passive signals (open, media, reading time, bounce) count once per post
     * per session: reopening the same thread kept adding interest. Votes,
     * saves, comments and shares are deliberate and always count.
     */
    private fun once(p: Post, signal: String) = synchronized(this) { passive.add("$signal:${p.id}") }

    internal fun reset() {
        synchronized(this) {
            seen.clear()
            engaged.clear()
            passive.clear()
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

    /**
     * Counts [event] per source and per feed slot (0–9, 10–29, 30+) for a post
     * For You placed (local metrics only): which sources and depths work.
     */
    private fun tally(p: Post, event: String) {
        val meta = m.meta.value[p.id] ?: return
        m.metrics.count("$event.src.${meta.source}")
        m.metrics.count("$event.slot.${if (meta.position < 10) "0-9" else if (meta.position < 30) "10-29" else "30+"}")
    }

    /**
     * Real engagement — 3s+ in the thread, the media viewed, an upvote, a
     * comment upvote: counts once per post toward the subreddit's and the post
     * type's engagement rate — only for a post For You showed this session, so
     * the rate is "liked what For You showed" (engagement from other feeds,
     * with no matching impression, used to inflate it). Opening alone used to
     * count before a bounce was known, and viewing media never did, so image
     * and video posts looked "seen, not engaged".
     */
    private fun engage(p: Post, event: String) {
        m.metrics.count("$event.${group(p)}")
        if (synchronized(this) { p.id in seen && engaged.add(p.id) }) {
            m.subStats.engaged(p.subreddit)
            m.typeStats.engaged(postTypeKey(p))
            tally(p, "eng")
        }
    }

    /**
     * A For You card that stayed >=60% on screen for 1s. Only posts For You
     * placed (they have meta): a Reddit Home card carries a reason too, and
     * used to count as a For You impression.
     */
    fun impression(p: Post) {
        if (m.meta.value[p.id] == null) return
        m.impressions.record(p.id)
        if (!synchronized(this) { seen.add(p.id) }) return
        m.subStats.impression(p.subreddit)
        m.typeStats.impression(postTypeKey(p))
        val meta = m.meta.value[p.id]
        m.metrics.count("impr.${group(p)}")
        if (meta != null) {
            m.metrics.count("src.${meta.source}")
            if (meta.position < 10) m.metrics.count("impr.top10")
        }
        tally(p, "imp")
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
        // A downvote isn't engagement (it counted as liking the subreddit).
        if (to == 1) engage(p, "vote")
    }

    fun save(p: Post, saved: Boolean) = learn(p, if (saved) 3.0 else -3.0, if (saved) 1.5 else -1.5)

    /** Opened: the open rate, not engagement yet ([dwell] decides that). */
    fun open(p: Post) {
        if (!once(p, "open")) return
        learn(p, 0.5, 0.0)
        m.metrics.count("open.${group(p)}")
        tally(p, "open")
    }

    /** 3 seconds or more in the thread: the open wasn't a bounce. */
    fun dwell(p: Post) = engage(p, "dwell")

    fun viewMedia(p: Post) {
        if (once(p, "media")) learn(p, 1.0, 0.0)
        engage(p, "media")
    }

    /** Commenting is the strongest engagement signal there is. */
    fun comment(p: Post) = learn(p, 2.5, 1.0)

    fun share(p: Post) = learn(p, 1.5, 0.75)

    /** Time in the thread: 30s+ ([long] = 2min+, on top of it). */
    fun read(p: Post, long: Boolean = false) {
        if (once(p, if (long) "read2m" else "read30")) {
            learn(p, if (long) 1.5 else 1.0, if (long) 1.0 else 0.5)
            if (!long) tally(p, "read30")
        }
        if (!long) engage(p, "read30")
    }

    /**
     * The "no" signals: hiding a post, the Dismiss swipe, hiding its subreddit
     * for 7 days, filtering it out. They used to only remove things from view.
     * [undo] reverses one (its snackbar's Undo). Each counts as a hide in
     * the per-source metrics.
     */
    fun hidePost(p: Post, undo: Boolean = false) {
        learn(p, if (undo) 2.0 else -2.0, if (undo) 0.8 else -0.8)
        if (!undo) tally(p, "hide")
    }

    fun dismiss(p: Post, undo: Boolean = false) {
        learn(p, if (undo) 1.0 else -1.0, if (undo) 0.4 else -0.4)
        if (!undo) tally(p, "hide")
    }

    fun hideSubreddit(p: Post, undo: Boolean = false) {
        learn(p, if (undo) 3.0 else -3.0, 0.0)
        if (!undo) tally(p, "hide")
    }

    fun filterOutSubreddit(p: Post, undo: Boolean = false) {
        learn(p, if (undo) 4.0 else -4.0, 0.0)
        if (!undo) tally(p, "hide")
    }

    /** Upvoted a comment in [p]'s thread: interest in the thread's subreddit (once per post per session). */
    fun commentUpvote(p: Post) {
        if (once(p, "commentvote")) learn(p, 0.75, 0.0)
        engage(p, "commentvote")
    }

    /** Backed out within 3 seconds (the open's +0.5 is taken back; it never counted as engaged). */
    fun bounce(p: Post) {
        if (once(p, "bounce")) learn(p, -0.5, 0.0)
    }

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
    val sourceFailed: Boolean = false, // a source failed or timed out
)

/**
 * "For You" — a transparent, client-side personalized feed.
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
        blendPlaced = 0
        knownSubs = null
        synchronized(listingCache) { listingCache.clear() }
        seedJob?.cancel()
        seedJob = null
    }

    @Volatile private var blendPlaced = 0 // Blend: Reddit Home posts placed in this feed
    // Favourites and subscriptions as the first page knew them (later pages don't ask again).
    @Volatile private var knownSubs: Pair<Set<String>, Set<String>>? = null
    // Community listings by request ("a+b+c", "all/top/day"), kept a few minutes.
    private val listingCache = HashMap<String, Pair<Long, Listing<Post>>>()
    @Volatile private var seedJob: Deferred<Unit>? = null // the cold-start seed, while it runs

    /**
     * First page when [after] is null, else the page after that cursor.
     * [loaded] = posts currently shown (excluded from later pages; a refresh
     * demotes the old top 10). Posts carry feedReason.
     */
    suspend fun page(after: String?, loaded: List<Post>): Listing<Post> {
        val firstPage = after == null
        if (firstPage) {
            _progress.value = 0
            m.impressions.newFeed() // a post seen again in this build counts again
        }
        // Cold start's seed runs alongside the sources (it used to hold them up);
        // the ranking waits for it. One at a time: a refresh meanwhile shares it.
        val user = c.session.username
        val session = c.session.session
        val seeding = if (firstPage && c.settings.value.trackHistory && session != null && !session.anonymous && user.isNotEmpty()) {
            synchronized(this) {
                seedJob?.takeIf { it.isActive } ?: c.scope.async { seedIfNeeded(user) }.also { seedJob = it }
            }
        } else null
        val page = getForYouFeed(
            inputs = rankInputs(firstPage, loaded),
            cursors = after, // null = first page; else the encoded cursor bundle
            excludeIds = if (firstPage) emptySet() else loaded.mapTo(HashSet()) { it.id },
            carryOver = if (firstPage) emptyList() else leftovers,
            seeding = seeding,
        )
        if (firstPage) m.impressions.setLastTop(page.listing.items.take(10).map { it.id })
        leftovers = page.leftovers
        // Slots count through the whole feed (each page's ranking starts at 0).
        m.meta.value = if (firstPage) page.meta else m.meta.value + page.meta.mapValues { (_, v) -> v.copy(position = v.position + loaded.size) }
        withContext(Dispatchers.Default) { m.docFreq.observe(page.candidateTitles) }
        for (p in page.listing.items) m.metrics.count("src.ranked.${page.meta[p.id]?.source ?: "other"}")
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

    suspend fun cachedFirstPageTime(): Long? = c.session.username.takeIf { it.isNotEmpty() }?.let { savedPageTime(c.context, it, "foryou") }

    /** Snapshot of everything For You learned, for the ranker. */
    private fun rankInputs(firstPage: Boolean, loaded: List<Post>): RankInputs {
        val kw = m.keywords
        val df = m.docFreq
        return RankInputs(
            interest = m.interest.value,
            subStats = m.subStats.value,
            typeStats = m.typeStats.value,
            blendReddit = c.settings.value.blendReddit,
            explicit = m.explicit.value,
            keywordScore = { t -> kw.scoreTitle(t, df::idf) },
            topKeyword = { t -> kw.topKeywordIn(t, df::idf) },
            muted = m.muted.value,
            openedAt = c.history.state.value.associate { it.id to it.viewedAt },
            impressions = m.impressions::count,
            // A refresh makes room: the old top 10 is demoted a little — the one
            // on screen, and the last one built (so a cold launch makes room too).
            previousTop = if (firstPage) loaded.take(10).mapTo(HashSet()) { it.id } + m.impressions.lastTop else emptySet(),
            // Stories already shown on earlier pages count toward repeats.
            previousTitles = if (firstPage) emptyList() else loaded.asReversed().take(100).map { it.title },
            // Stories you opened in the last 36h, demoted when told again elsewhere.
            readTitles = System.currentTimeMillis().let { now ->
                c.history.state.value.filter { it.viewedAt > 0 && now - it.viewedAt < 36 * 3600_000L }.map { it.title }
            },
            discoveryAppetite = m.metrics.discoveryAppetite(),
            discoveryMix = c.settings.value.forYouDiscovery,
        )
    }

    /**
     * Communities you've dipped into or engage with but don't follow
     * (interest ≥ 0.5), plus ones you asked for more of, minus [skip] (the top
     * interests, fetched anyway): three per refresh, rotating, as personalised
     * discovery instead of r/popular alone. It used to stop at interest 2, so
     * an engaged community outside the top five was never fetched.
     */
    private fun candidateCommunities(subscribed: Set<String>, skip: List<String>): List<String> {
        val explicitMore = m.explicit.value.subs.filter { it.value > 0 }.keys
        val visited = m.interest.value.entries
            .filter { it.value >= 0.5 }
            .sortedByDescending { it.value }
            .map { it.key }
        val all = LinkedHashSet<String>().apply { addAll(explicitMore); addAll(visited) }
            .filter { it !in subscribed && it !in skip }
        if (all.isEmpty()) return emptyList()
        val start = (communityTurn++ * 3) % all.size
        return (0 until minOf(3, all.size)).map { all[(start + it) % all.size] }
    }

    /**
     * Cold start: the first time For You runs for an account, seed its model
     * from the user's own Reddit activity (their upvoted and saved posts — data
     * Reddit already holds for them, nothing third-party) plus local history,
     * so day one already prefers what they actually like. Once per account
     * (marked done only once both requests worked: a failure used to end it
     * for good; it's tried again on the next refresh), and only while history
     * tracking is on (the caller checks that and the signed-in [user]).
     */
    internal suspend fun seedIfNeeded(user: String) {
        val key = userScopedKey(c.prefs, user, "fy_seeded")
        if (c.prefs.getBool(key) == true) return

        val repo = c.repository
        val (up, sv) = coroutineScope {
            val up = async { orNull { repo.getUserPosts(user, where = "upvoted", limit = 100).items } }
            val sv = async { orNull { repo.getUserSaved(user, limit = 100).items.filterIsInstance<Post>() } }
            up.await() to sv.await()
        }
        if (up == null || sv == null || c.session.username != user) return
        c.prefs.setBool(key, true)
        val upvoted: List<Post> = up
        val saved: List<Post> = sv

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
     * engaged communities and a few the user has visited, plus
     * today's top of r/all to explore. [carryOver] is the previous page's
     * unplaced pool; [seeding] the cold-start seed the ranking waits for.
     */
    private suspend fun getForYouFeed(
        inputs: RankInputs,
        cursors: String?, // JSON cursor bundle from a previous page's `after`
        excludeIds: Set<String>,
        carryOver: List<Candidate>,
        seeding: Deferred<Unit>?,
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
        // An empty page (all muted/seen) retries the next cursors once before
        // ending the feed — it used to stop dead. Not when a source failed:
        // asking everything again at once only repeated the failure (the failed
        // source keeps its place for the next page).
        for (attempt in 0 until 2) {
            // First page only without a cursor at all: once every source has run
            // out the cursor is empty ({}), and the leftovers page on from there.
            val first = cursors.isNullOrEmpty() && attempt == 0
            val pg = forYouPage(inputs, prev, excludeIds, if (attempt == 0) carryOver else emptyList(), first, seeding)
            page = pg
            if (pg.listing.items.isNotEmpty() || pg.cursors.isEmpty() || pg.sourceFailed) break
            prev = pg.cursors
        }
        return page!!
    }

    private suspend fun forYouPage(
        inputs: RankInputs,
        prev: Map<String, String?>,
        excludeIds: Set<String>,
        carryOver: List<Candidate>,
        firstPage: Boolean,
        seeding: Deferred<Unit>?,
    ): ForYouPage = coroutineScope {
        val repo = c.repository
        val muted = inputs.muted

        // Each source: its listing, or null if it failed / timed out. Secondary
        // sources get a short timeout so the slowest community doesn't decide how
        // long the page takes.
        // The first real failure (not a timeout), to report if nothing at all loads.
        var firstError: Exception? = null
        var answered = false // a source answered (even with nothing new)
        var failed = false // a source failed or timed out
        fun source(secondary: Boolean = true, f: suspend () -> Listing<Post>): Deferred<Listing<Post>?> = async {
            try {
                if (secondary) withTimeout(2500) { f() } else f()
            } catch (e: kotlinx.coroutines.TimeoutCancellationException) {
                failed = true
                null
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (firstError == null) firstError = e
                failed = true
                null
            }?.also { l ->
                answered = true
                if (firstPage) _progress.update { it + l.items.size }
            }
        }

        // A cursor of "" means "start this source from the top" (its first
        // fetch failed); a missing key means the source is exhausted.
        fun live(k: String) = firstPage || prev.containsKey(k)
        fun after(k: String): String? = prev[k]?.ifEmpty { null }
        val none = async<Listing<Post>?> { null }

        // The first page's community listings don't change much in a few
        // minutes: a quick refresh reuses them instead of asking again.
        val now = System.currentTimeMillis()
        val cache = synchronized(listingCache) {
            listingCache.entries.removeAll { now - it.value.first >= 5 * 60_000L }
            HashMap(listingCache)
        }
        val fetched = ArrayList<Pair<String, Deferred<Listing<Post>?>>>() // cache name → request
        fun cached(name: String, f: suspend () -> Listing<Post>): Deferred<Listing<Post>?> {
            cache[name]?.let { hit -> return source { hit.second } }
            return source(f = f).also { fetched.add(name to it) }
        }
        // Hot posts from several communities in one request (/r/a+b+c/hot) —
        // up to sixteen requests became two. Each group is at most eight names,
        // far under any URL limit.
        fun hot(subs: List<String>, perSub: Int): Deferred<Listing<Post>?> {
            if (subs.isEmpty()) return none
            val name = subs.joinToString("+")
            return cached(name) {
                try {
                    repo.getPosts(subreddit = name, sort = PostSort.HOT, limit = minOf(100, perSub * subs.size))
                } catch (e: com.bennybar.luli_for_reddit.core.net.RedditApiException) {
                    if (e.statusCode != 403 || subs.size < 2) throw e
                    // Website sign-in where Reddit's edge refuses listings: its
                    // GraphQL has no combined feed, so one community at a time.
                    val lists = coroutineScope {
                        subs.map { s -> async { orNull { repo.getPosts(subreddit = s, sort = PostSort.HOT, limit = perSub) }?.items ?: emptyList() } }
                            .awaitAll()
                    }
                    Listing(lists.flatten())
                }
            }
        }

        // Favourites and subscriptions: as the first page knew them, else from the
        // last snapshot, so favourites go out with everything else instead of
        // waiting ~2s for the subscription list. The live list is asked for once
        // per build, to refresh the snapshot for next time (it was every page),
        // and never signed out (it can only fail there, and was asked again each page).
        val user = c.session.username
        val known = (if (firstPage) null else knownSubs) ?: loadSubsSnapshot(user)
        // Subreddits you engage with most (learned on-device), even if not
        // favourited. Local data, so known before any request goes out. Ones
        // you don't follow first (3, then 2 you do): /best already brings your
        // subscriptions, so five subscribed ones here added little.
        val (engagedSubd, engagedOther) = inputs.interest.entries
            .filter { it.value >= K_ENGAGED_INTEREST && it.key !in muted }
            .sortedByDescending { it.value }
            .map { it.key }
            .partition { it in (known?.second ?: emptySet()) }
        val topInterest = (engagedOther.take(3) + engagedSubd.take(2) + engagedOther.drop(3) + engagedSubd.drop(2)).take(5)
        val communities = if (firstPage) candidateCommunities(known?.second ?: emptySet(), topInterest) else emptyList()
        val subsF = if (known == null && firstPage && user.isNotEmpty()) {
            async { orNull { repo.getSubscribedSubreddits() } ?: emptyList<Subreddit>() }
        } else {
            if (known != null && firstPage && user.isNotEmpty()) {
                c.scope.launch(Dispatchers.IO) { orNull { repo.getSubscribedSubreddits() }?.let { saveSubsSnapshot(user, it) } }
            }
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
        val nearF = if (firstPage) hot((topInterest + communities.filter { it !in muted }).distinct(), perSub = 8) else none
        // Exploration beyond the communities you already touch (they were its
        // only other source): today's top posts across Reddit, ranked as discovery.
        val exploreF = if (firstPage) {
            cached("all/top/day") { repo.getPosts(subreddit = "all", sort = PostSort.TOP, time = TopTime.DAY, limit = 25) }
        } else none

        val (favourites, subscribed) = known ?: run {
            val mySubs = subsF?.await() ?: emptyList()
            if (mySubs.isNotEmpty()) saveSubsSnapshot(user, mySubs)
            mySubs.filter { it.userHasFavorited }.mapTo(LinkedHashSet()) { it.name.lowercase() } to
                mySubs.mapTo(HashSet()) { it.name.lowercase() }
        }
        if (subscribed.isNotEmpty()) knownSubs = favourites to subscribed
        // Favourites go out the moment the list is known, while the rest is still
        // in flight. One already fetched as a top interest isn't fetched twice.
        // Eight per load; with more favourites than that, each load takes the
        // next eight in turn (only the first eight ever got fetched before).
        val favouriteF = if (firstPage) {
            val favs = favourites.filter { it !in topInterest && it !in muted }
            val pick = if (favs.size <= 8) favs else {
                val k = userScopedKey(c.prefs, user, "fy_fav_rotation")
                val start = (c.prefs.getInt(k) ?: 0).mod(favs.size)
                c.prefs.setInt(k, start + 8)
                List(8) { favs[(start + it) % favs.size] }
            }
            hot(pick, perSub = 10)
        } else none

        // Blend (Beta): your Reddit Home is one more source, ranked with the
        // rest. It's slow to read (a hidden browser), so a page waits only so
        // long for it; later pages read the next batch.
        val s = c.settings.value
        val blend = s.forYouFeed && s.blendHome && s.redditHomeAllowed
        val homeBatch = if (blend && (firstPage || prev.containsKey("home"))) m.redditHome.blendBatch(firstPage) else null

        val best = bestF.await()
        val rising = risingF.await()
        val popular = popularF.await()
        val ids = HashSet(excludeIds)
        val pool = ArrayList<Candidate>()
        fun add(l: Listing<Post>?, src: String) {
            for (p in l?.items ?: emptyList()) if (ids.add(p.id)) pool.add(Candidate(p, src))
        }

        // Blend: Reddit's Home batch first, so a post it also recommends counts
        // as Reddit's pick whichever source found it too (de-duplication used
        // to keep whichever came first and drop the Home signal). Wait at most
        // 2.5s once the other sources are in (it was 10–12s, on every page) —
        // the first page shows the loading deck meanwhile, as Home does; a batch
        // still loading joins the next page instead.
        val near = nearF.await()
        val favourite = favouriteF.await()
        val explore = exploreF.await()
        val homeResult = homeBatch?.let { b -> withTimeoutOrNull(2_500L) { b.await() } }
        val homeLoading = homeBatch != null && !homeBatch.isCompleted
        if (homeLoading) m.redditHome.blendKeep(homeBatch!!)
        val home = (homeResult as? RedditHomeEngine.BlendResult.Posts)?.posts
        home?.forEachIndexed { i, p ->
            if (ids.add(p.id)) pool.add(Candidate(p, "home", homePos = i.toDouble() / maxOf(home.size - 1, 1)))
        }
        if (!home.isNullOrEmpty()) m.redditHome.blendPrefetch()
        // Held over from the last page ("home" ones stay Reddit's picks).
        for (cand in carryOver) if (ids.add(cand.post.id)) pool.add(if (cand.source == "home") cand else Candidate(cand.post, "carry"))
        add(best, "best")
        add(rising, "rising")
        add(popular, "popular")
        // The combined listings, each post labelled by its community's group.
        for (l in listOf(favourite, near)) {
            for (p in l?.items ?: emptyList()) {
                if (!ids.add(p.id)) continue
                val sub = p.subreddit.lowercase()
                pool.add(Candidate(p, if (sub in topInterest) "interest" else if (sub in favourites) "favourite" else "community"))
            }
        }
        add(explore, "explore")
        for ((name, request) in fetched) {
            val l = request.await() ?: continue
            synchronized(listingCache) { listingCache[name] = System.currentTimeMillis() to l }
        }

        // Every source failed (offline, rate-limited…): say so, rather than
        // showing an empty feed that just ends. Not when one answered (with
        // nothing new): that used to fail the build and retry it whole.
        if (pool.isEmpty() && !answered) firstError?.let { throw it }
        // Cold start: rank with what the seed learned (it ran alongside the
        // sources), waiting only so long for it.
        var ranked = inputs.withSubscriptions(favourites, subscribed)
        if (seeding != null) {
            withTimeoutOrNull(3_000) { seeding.await() }
            ranked = ranked.copy(interest = m.interest.value)
        }
        val result = withContext(Dispatchers.Default) { rankForYou(pool, ranked) }

        // Next cursors. A source that failed keeps its place (it used to be
        // dropped for the rest of the session — one timeout on /best and the
        // feed quietly became r/popular); an exhausted one is left out.
        val next = LinkedHashMap<String, String>()
        // Blend: Home's cursor is the hidden page itself; its value counts
        // misses in a row. Still loading or a passing failure: try again on
        // the next page (up to 3 failures, 2 empty batches, as Home allows);
        // signed out: the rest of this feed is For You's own, and says so.
        if (homeBatch != null) {
            val misses = prev["home"]?.removePrefix("m")?.toIntOrNull() ?: 0
            val state: RedditHomeEngine.BlendState?
            when {
                homeLoading -> {
                    next["home"] = "m$misses"
                    state = if (firstPage) RedditHomeEngine.BlendState.Loading else null
                }
                homeResult is RedditHomeEngine.BlendResult.Posts -> {
                    next["home"] = "m0"
                    state = null
                }
                homeResult is RedditHomeEngine.BlendResult.SignedOut -> state = RedditHomeEngine.BlendState.Unavailable(signedOut = true)
                misses + 1 < (if (homeResult is RedditHomeEngine.BlendResult.Empty) 2 else 3) -> {
                    next["home"] = "m${misses + 1}"
                    state = null
                }
                else -> state = RedditHomeEngine.BlendState.Unavailable(signedOut = false)
            }
            // "8 Reddit Home picks" in the header: placed in this feed so far.
            val placedHome = result.ranked.count { result.meta[it.id]?.source == "home" }
            blendPlaced = (if (firstPage) 0 else blendPlaced) + placedHome
            m.redditHome.blendState.value = state ?: RedditHomeEngine.BlendState.Included(blendPlaced)
        }
        for ((key, listing) in listOf("best" to best, "rising" to rising, "popular" to popular)) {
            if (!live(key)) continue
            if (listing == null) {
                next[key] = prev[key] ?: ""
            } else if (!listing.after.isNullOrEmpty()) {
                next[key] = listing.after
            }
        }
        // More while a source has a next page, or ranked posts are still waiting
        // (once every source ran out, its leftovers used to be unreachable).
        val hasMore = (result.ranked.isNotEmpty() || result.leftovers.isNotEmpty()) &&
            (next.isNotEmpty() || result.leftovers.isNotEmpty())
        ForYouPage(
            listing = Listing(
                result.ranked,
                after = if (hasMore) JsonObject(next.mapValues { JsonPrimitive(it.value) }).toString() else null,
            ),
            cursors = next,
            leftovers = result.leftovers,
            meta = result.meta,
            candidateTitles = pool.map { it.post.title },
            sourceFailed = failed,
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
