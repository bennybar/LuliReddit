package com.bennybar.luli_for_reddit.feature.foryou

import com.bennybar.luli_for_reddit.model.Post
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import java.util.Locale
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.pow
import kotlin.math.roundToInt

/** A post fetched for For You, and the request it came from. */
data class Candidate(
    val post: Post,
    val source: String, // best / rising / popular / favourite / interest / community
)

/**
 * Interest at or above this counts a subreddit as one you engage with — for
 * both primary membership and the "Because you engage" label (they used to
 * disagree: 2 vs 4).
 */
const val K_ENGAGED_INTEREST = 2.0

/**
 * Everything the ranker knows about the user, snapshotted from the local
 * stores. Pure data, so ranking is deterministic and unit-testable.
 */
data class RankInputs(
    val favourites: Set<String> = emptySet(), // lowercase
    val subscribed: Set<String> = emptySet(), // lowercase
    val interest: Map<String, Double> = emptyMap(),
    val subStats: Map<String, Pair<Double, Double>> = emptyMap(), // sub → (seen, engaged)
    val explicit: ExplicitPrefs = ExplicitPrefs(),
    val keywordScore: ((String) -> Double)? = null, // idf-weighted, −6…8
    val topKeyword: ((String) -> String?)? = null,
    val muted: Set<String> = emptySet(),
    val openedAt: Map<String, Long> = emptyMap(), // post id → millis
    val impressions: ((String) -> Double)? = null, // faded count
    val previousTop: Set<String> = emptySet(), // the top 10 before this refresh
    val previousTitles: List<String> = emptyList(), // titles already on earlier pages
    val discoveryAppetite: Double = 1.0, // discovery vs primary open rate
    val discoveryMix: Int = 0, // Settings → Familiar (-2) ↔ Discover (+2)
    val typeStats: Map<String, Pair<Double, Double>> = emptyMap(), // post type (postTypeKey) → (seen, engaged)
    val now: Long = System.currentTimeMillis(), // millis
) {
    /** The same inputs once the subscription list has arrived. */
    fun withSubscriptions(favourites: Set<String>, subscribed: Set<String>) =
        copy(favourites = favourites, subscribed = subscribed)
}

class RankResult(
    val ranked: List<Post>,
    val leftovers: List<Candidate>, // carried into the next page's pool
    val meta: Map<String, ForYouMeta>,
)

// Identity semantics on purpose (pools and the dropped set compare by instance).
private class Scored(
    val c: Candidate,
    val score: Double,
    val discovery: Boolean,
    val reason: String,
    val why: List<String>,
    val story: Set<String>, // title keywords, for same-story detection
)

private class Story(val words: Set<String>, var count: Int, var lastPos: Int)

/**
 * "For You" ranking.
 *
 * score = additive · community · affinity · explicit · keywords · quality ·
 *         fatigue — every factor positive, so nothing can flip sign (a
 *         negative keyword sum used to turn the multipliers upside down:
 *         opened posts and favourites ranking *below* others).
 */
fun rankForYou(pool: List<Candidate>, i: RankInputs, pageSize: Int = 50): RankResult {
    // Global open rate, the baseline each subreddit's rate is compared with.
    var seenAll = 0.0
    var engAll = 0.0
    for (v in i.subStats.values) {
        seenAll += v.first
        engAll += v.second
    }
    val globalCtr = (engAll + 1) / (seenAll + 6)

    fun ageHours(p: Post): Double = max(((i.now - p.createdUtc) / 60_000L) / 60.0, 1.0)

    // Per-subreddit velocity percentile, so small communities aren't drowned
    // out by raw point counts ("a top post *for this sub*" is what matters).
    val vels = HashMap<String, MutableList<Double>>()
    for (c in pool) vels.getOrPut(c.post.subreddit) { ArrayList() }.add(c.post.score / ageHours(c.post))
    vels.values.forEach { it.sort() }
    fun velPct(p: Post): Double {
        val v = vels[p.subreddit]!!
        if (v.size == 1) return 0.5
        val x = p.score / ageHours(p)
        // Average rank among equals: ties (a sub's brand-new posts, all at
        // 1 point) used to share the lowest percentile, 0.
        var lo = 0
        while (lo < v.size && v[lo] < x) lo++
        var hi = lo
        while (hi < v.size && v[hi] == x) hi++
        val rank = (lo + maxOf(hi - 1, lo)) / 2.0
        val raw = rank / (v.size - 1)
        // A sub with few candidates says little about how good a post is for
        // it: pulled toward the middle (a single candidate is 0.5, was 0.7).
        val trust = (v.size - 1) / (v.size + 2.0)
        return 0.5 + (raw - 0.5) * trust
    }

    // How often you engage with each kind of post (image, video, text…) that
    // For You shows, against your overall rate: learns what you like to see.
    var typeSeen = 0.0
    var typeEng = 0.0
    for (v in i.typeStats.values) {
        typeSeen += v.first
        typeEng += v.second
    }
    val typeCtr = (typeEng + 1) / (typeSeen + 6)
    fun typeMult(p: Post): Double {
        val st = i.typeStats[postTypeKey(p)] ?: return 1.0
        if (st.first < 8) return 1.0
        val lift = ln(((st.second + 1) / (st.first + 6)) / typeCtr).coerceIn(-0.5, 0.5)
        return exp(0.6 * lift) // ×0.74 … ×1.35
    }

    // Discussion: comments per hour, as a percentile in this pool (a busy
    // thread and a silent one used to rank alike).
    val talk = pool.map { it.post.numComments / ageHours(it.post) }.sorted()
    fun talkPct(p: Post): Double {
        if (talk.size < 2) return 0.5
        val x = p.numComments / ageHours(p)
        var lo = 0
        while (lo < talk.size && talk[lo] < x) lo++
        return lo.toDouble() / (talk.size - 1)
    }

    fun pct(f: Double): String {
        val digits = if (f >= 10) 0 else if (f >= 1) 1 else 2
        return "×" + String.format(Locale.ROOT, "%.${digits}f", f)
    }

    fun score(c: Candidate): Scored? {
        val p = c.post
        val sub = p.subreddit.lowercase()
        if (p.stickied || sub in i.muted) return null
        val opened = i.openedAt[p.id]
        // Opened more than 12h ago: done with it.
        if (opened != null && i.now - opened > 12 * 3600 * 1000L) return null

        val fav = sub in i.favourites
        val subd = sub in i.subscribed
        val explicitSub = i.explicit.subs[sub] ?: 0

        // Affinity: learned interest plus how often you actually open this
        // subreddit compared with everything else (rate, not count).
        var lift = 0.0
        val st = i.subStats[sub]
        if (st != null && st.first >= 3) {
            val ctr = (st.second + 1) / (st.first + 6)
            lift = ln(ctr / globalCtr).coerceIn(-1.5, 1.5)
        }
        val a = (i.interest[sub] ?: 0.0) + 4 * lift
        // Two-sided and non-saturating: "less" and downvotes now demote (they
        // were clamped away), heavy use keeps ordering instead of capping out.
        val wInterest = if (a >= 0) 1 + 0.6 * ln(1 + a / 3) else exp(a / 4)

        // Blend: a post from your Reddit Home is Reddit's own pick for you. It
        // competes in the main pool, between your communities and discovery,
        // and gets a small nudge for being recommended.
        val fromHome = c.source == "home"
        val primary = fav || subd || a >= K_ENGAGED_INTEREST || explicitSub > 0 || fromHome
        val base = if (fav) 4.0 else if (subd || explicitSub > 0) 2.5 else if (fromHome) 1.6 else 0.4
        val homeMult = if (fromHome) 1.15 else 1.0
        val eSub = if (explicitSub > 0) 1.6 else if (explicitSub < 0) 0.3 else 1.0

        val kw = i.keywordScore?.invoke(p.title) ?: 0.0
        val kwMult = exp(0.08 * kw) // ×0.62 … ×1.9
        val words = titleKeywords(p.title)
        var likedTopic: String? = null
        var dislikedTopic: String? = null
        for (w in words) {
            val v = i.explicit.topics[w]
            if (v != null && v < 0) dislikedTopic = dislikedTopic ?: w
            if (v != null && v > 0) likedTopic = likedTopic ?: w
        }
        val eTopic = if (dislikedTopic != null) 0.3 else if (likedTopic != null) 1.6 else 1.0

        val vp = velPct(p)
        val age = ageHours(p)
        val recency = 1 / (1 + age / 24)
        val additive = max(1.0, vp * 30 + recency * 30 + 15)
        val quality = 0.5 + p.upvoteRatio

        // Freshness: each faded impression costs 20%; opened posts mostly go;
        // posts already in the last top 10 make room on refresh.
        val shown = i.impressions?.invoke(p.id) ?: 0.0
        val fatigue = 0.8.pow(shown)
        val openedPen = if (opened != null) 0.15 else 1.0
        val churn = if (p.id in i.previousTop) 0.7 else 1.0

        val tMult = typeMult(p)
        val tp = talkPct(p)
        val discussion = 0.92 + 0.16 * tp // ×0.92 … ×1.08

        val s = additive * base * wInterest * eSub * kwMult * eTopic * quality * fatigue * openedPen * churn * tMult * discussion * homeMult

        // Explanation from what actually moved the score.
        val topKw = i.topKeyword?.invoke(p.title)
        val drivers = buildList {
            if (likedTopic != null) add(ln(1.6) to "You asked for more about “$likedTopic”")
            if (explicitSub > 0) add(ln(1.6) to "You asked for more from r/${p.subreddit}")
            if (fav) add(ln(4 / 2.5) to "★ Favourite · r/${p.subreddit}")
            if (a >= K_ENGAGED_INTEREST) add(ln(wInterest) to "Because you engage with r/${p.subreddit}")
            if (topKw != null && kw > 0) add(ln(kwMult) to "Because you read about “$topKw”")
        }.sortedByDescending { it.first }
        val reason = when {
            drivers.isNotEmpty() && drivers.first().first > ln(1.15) -> drivers.first().second
            age < 6 && p.score > 1000 && vp > 0.8 -> "🔥 Trending on Reddit"
            subd -> "From r/${p.subreddit}"
            fromHome -> "Recommended by Reddit · r/${p.subreddit}"
            c.source == "community" -> "Discover · r/${p.subreddit}, near communities you visit"
            else -> "Discover · r/${p.subreddit}"
        }

        val why = buildList {
            add(
                when {
                    fav -> "r/${p.subreddit} is one of your favourites"
                    subd -> "You're subscribed to r/${p.subreddit}"
                    fromHome -> "Reddit recommends r/${p.subreddit} to you (you don't follow it)"
                    else -> "Discovery: you don't follow r/${p.subreddit}"
                },
            )
            if (fromHome) add("In your Reddit Home${p.feedReason?.let { ": “$it”" } ?: ""} (×1.15)")
            if (explicitSub != 0) {
                add("You asked for ${if (explicitSub > 0) "more" else "less"} from r/${p.subreddit} (${pct(eSub)})")
            }
            if (kotlin.math.abs(wInterest - 1) > 0.05) add("Your activity in r/${p.subreddit} (${pct(wInterest)})")
            if (likedTopic != null) add("You asked for more about “$likedTopic” (×1.6)")
            if (dislikedTopic != null) add("You asked for less about “$dislikedTopic” (×0.3)")
            if (kotlin.math.abs(kwMult - 1) > 0.05) {
                add("Topics you read${if (topKw != null) ", like “$topKw”" else ""} (${pct(kwMult)})")
            }
            if (vp > 0.8) add("Doing well in r/${p.subreddit} right now")
            if (kotlin.math.abs(tMult - 1) > 0.05) {
                add("${if (tMult > 1) "You often open" else "You rarely open"} ${postTypeLabel(p)} posts (${pct(tMult)})")
            }
            if (tp > 0.85 && p.numComments >= 20) add("Lively discussion: ${p.numComments} comments (${pct(discussion)})")
            if (shown >= 0.5) add("Seen ${shown.roundToInt()}× before (${pct(fatigue)})")
            if (opened != null) add("You already opened it (×0.15)")
            add("Source: ${sourceLabel(c.source)}")
        }

        return Scored(c, s, !primary, reason, why, words.toSet())
    }

    val scored = pool.mapNotNull(::score).sortedByDescending { it.score }

    // Same link in several places (crossposts, the same article): keep the
    // best-scoring one.
    val byUrl = HashSet<String>()
    val unique = ArrayList<Scored>()
    for (s in scored) {
        val key = normalisedUrl(s.c.post)
        if (key == null || byUrl.add(key)) unique.add(s)
    }

    // Same story told in different subreddits: the second copy is allowed at
    // least 15 slots after the first, a third never. Stories from earlier
    // pages count.
    val stories = ArrayList<Story>()
    fun storyOf(words: Set<String>): Int? {
        if (words.size < 3) return null
        for (k in stories.indices) {
            val shared = stories[k].words.intersect(words).size
            if (shared >= 3 && shared.toDouble() / (stories[k].words union words).size >= 0.5) return k
        }
        return null
    }
    // Earlier pages, newest first: copies of one story count together (each
    // used to be its own story, so a third copy got through), and the newest
    // keeps its real distance (j + 1 slots before this page) for the spacing.
    for ((j, t) in i.previousTitles.withIndex()) {
        val w = titleKeywords(t).toSet()
        if (w.size < 3) continue
        val k = storyOf(w)
        if (k != null) stories[k].count += 1 else stories.add(Story(w, 1, -(j + 1)))
    }

    // Greedy placement: each slot takes the best remaining post after a
    // diversity discount (same subreddit in the last 8, same media type in
    // the last 4), alternating in discovery at an adaptive rate.
    val primaryPool = unique.filter { !it.discovery }.toMutableList()
    val discoveryPool = unique.filter { it.discovery }.toMutableList()
    // A discovery post every ~6 slots, adapted to how often you open them;
    // the Familiar ↔ Discover setting scales that (Familiar: ~1 in 20,
    // Discover: ~1 in 3). The middle keeps the adaptive 4–10 range.
    val mix = listOf(0.3, 0.6, 1.0, 1.4, 2.0)[i.discoveryMix.coerceIn(-2, 2) + 2]
    val every = if (i.discoveryMix == 0) (6 / i.discoveryAppetite.coerceIn(0.6, 1.5)).roundToInt().coerceIn(4, 10)
    else (6 / (i.discoveryAppetite.coerceIn(0.6, 1.5) * mix)).roundToInt().coerceIn(3, 20)
    val placed = ArrayList<Scored>()
    val dropped = HashSet<Scored>()

    fun pick(from: List<Scored>): Scored? {
        var best: Scored? = null
        var bestV = -1.0
        val recentSubs = placed.asReversed().take(8).map { it.c.post.subreddit }
        val recentTypes = placed.asReversed().take(4).map { it.c.post.type }
        for (s in from) {
            if (s in dropped) continue
            val k = storyOf(s.story)
            if (k != null && (stories[k].count >= 2 || placed.size - stories[k].lastPos < 15)) {
                if (stories[k].count >= 2) dropped.add(s)
                continue
            }
            val sameSub = recentSubs.count { it == s.c.post.subreddit }
            val sameType = recentTypes.count { it == s.c.post.type }
            val v = s.score * 0.6.pow(sameSub) * 0.85.pow(sameType)
            if (v > bestV) {
                bestV = v
                best = s
            }
        }
        return best
    }

    while (placed.size < pageSize) {
        val wantDiscovery = (placed.size + 1) % every == 0
        val s = (if (wantDiscovery) pick(discoveryPool) else null)
            ?: pick(primaryPool)
            ?: pick(discoveryPool)
            ?: break
        (if (s.discovery) discoveryPool else primaryPool).remove(s)
        val k = storyOf(s.story)
        if (k != null) {
            stories[k].count += 1
            stories[k].lastPos = placed.size
        } else if (s.story.size >= 3) {
            stories.add(Story(s.story, 1, placed.size))
        }
        placed.add(s)
    }

    // Unplaced posts aren't thrown away: the best carry over to the next page
    // (the per-subreddit cap used to discard them for good).
    val leftovers = (primaryPool + discoveryPool)
        .filter { it !in dropped }
        .sortedByDescending { it.score }
        .take(120)
        .map { it.c }

    val meta = LinkedHashMap<String, ForYouMeta>()
    val ranked = ArrayList<Post>(placed.size)
    for ((k, s) in placed.withIndex()) {
        ranked.add(s.c.post.copy(feedReason = s.reason))
        meta[s.c.post.id] = ForYouMeta(source = s.c.source, discovery = s.discovery, position = k, why = s.why)
    }
    return RankResult(ranked, leftovers, meta)
}

private fun sourceLabel(source: String): String = when (source) {
    "best" -> "your subscriptions (Best)"
    "rising" -> "rising in your subscriptions"
    "popular" -> "r/popular"
    "favourite" -> "a favourite community"
    "interest" -> "a community you engage with"
    "community" -> "a community you've visited"
    "carry" -> "held over from the previous page"
    "home" -> "your Reddit Home (Blend)"
    else -> source
}

/**
 * A link post's URL without scheme, `www.`, tracking parameters or
 * fragment — to spot the same link posted in several places. Null for text
 * posts (their URL is their own permalink).
 */
internal fun normalisedUrl(p: Post): String? {
    if (p.isSelf || p.url.isEmpty()) return null
    val u = p.url.toHttpUrlOrNull() ?: return null
    if (u.host.isEmpty()) return null
    val host = u.host.lowercase().replaceFirst(Regex("^www\\."), "")
    val names = u.queryParameterNames.filter { !it.startsWith("utm_") }.sorted()
    val q = names.joinToString("&") { "$it=${u.queryParameterValues(it).lastOrNull()}" }
    return "$host${u.encodedPath}${if (q.isEmpty()) "" else "?$q"}"
}

/** The kind of post, for learning which kinds you open (galleries count as images, GIFs as videos). */
fun postTypeKey(p: Post): String = when (p.type) {
    com.bennybar.luli_for_reddit.model.PostType.IMAGE, com.bennybar.luli_for_reddit.model.PostType.GALLERY -> "image"
    com.bennybar.luli_for_reddit.model.PostType.VIDEO, com.bennybar.luli_for_reddit.model.PostType.GIF -> "video"
    com.bennybar.luli_for_reddit.model.PostType.LINK -> "link"
    com.bennybar.luli_for_reddit.model.PostType.SELF -> "text"
}

private fun postTypeLabel(p: Post) = when (postTypeKey(p)) {
    "image" -> "image"
    "video" -> "video"
    "link" -> "link"
    else -> "text"
}
