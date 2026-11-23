package com.bennybar.luli_for_reddit.feature.digest

import com.bennybar.luli_for_reddit.core.compactNumber
import com.bennybar.luli_for_reddit.feature.foryou.normalisedUrl
import com.bennybar.luli_for_reddit.feature.foryou.sameStory
import com.bennybar.luli_for_reddit.feature.foryou.titleKeywords
import com.bennybar.luli_for_reddit.model.Post
import kotlin.math.roundToInt

// The Digest (docs/digest-spec.md): the notable posts of the last 24 hours in the
// communities you choose, kept per day. This file is the pure part (what gets
// picked, and how a refresh merges into the day), so it's unit-tested on both apps.

/** How long a digest is (Settings › Feed › Digest › Size). Persisted by index (`digestSize`). */
enum class DigestSize(val items: Int, val perCommunity: Int, val label: String, val description: String) {
    BRIEF(5, 2, "Brief", "About 5 posts, at most 2 from a community"),
    STANDARD(12, 2, "Standard", "About 12 posts, at most 2 from a community"),
    EVERYTHING(30, 5, "Everything notable", "Every notable post, up to 30"),
    ;

    companion object {
        fun of(i: Int) = entries.getOrElse(i) { STANDARD }
    }
}

/**
 * A post in a digest, with why it's there. [addedAt]: when this day's digest gained it;
 * [importance]: the AI's 1–5 rating (0: picked without AI).
 */
data class DigestItem(val post: Post, val why: String, val notability: Double, val addedAt: Long, val importance: Int = 0)

/** Settings › Digest › Order by (`digestOrder`). [AI]: the AI's importance, without it as [NOTABLE]. */
enum class DigestOrder(val label: String, val description: String) {
    NOTABLE("Most notable", "How much a post stands out in its own community"),
    UPVOTED("Most upvoted", "The most points first"),
    NEWEST("Newest", "The most recent first"),
    AI("AI's assessment", "How important the AI rated it, then how notable"),
    ;

    companion object {
        fun of(i: Int) = entries.getOrElse(i) { NOTABLE }
    }
}

/** The AI's answer for a build: an overview (when asked for) and its verdicts, by post id. */
data class DigestAi(val overview: String?, val verdicts: Map<String, AiVerdict>)

/** [importance]: 1–5; under 2 is never shown. */
data class AiVerdict(val importance: Int, val why: String)

/**
 * A candidate's verdict for the day, kept so a refresh doesn't judge it again (nor
 * send it to the AI again). [secondLook]: it already had its one re-check.
 */
data class Judged(val picked: Boolean, val notability: Double, val at: Long, val secondLook: Boolean = false)

/**
 * One day's digest ([day]: the local date, yyyy-MM-dd). [builtAt]: its first build;
 * [refreshedAt]: the last fetch; [seenAt]: when it was last looked at (an item added
 * after both is "New").
 */
data class DigestDay(
    val day: String,
    val builtAt: Long,
    val refreshedAt: Long,
    val seenAt: Long,
    val items: List<DigestItem>,
    val judged: Map<String, Judged>,
    /** The AI's paragraph about the day (its first build, when asked for). */
    val overview: String? = null,
    /** The last build wanted the AI and couldn't have it: picked by activity instead. */
    val aiFailed: Boolean = false,
    /** The last AI call for this day (0: none), for the automatic builds' 12-hour guard. */
    val aiAt: Long = 0,
) {
    fun isNew(item: DigestItem) = item.addedAt > builtAt && item.addedAt > seenAt
}

/** At or above this, a post is notable: twice what's usual in its community. */
internal const val NOTABLE = 2.0

/** A community's best post of the day counts even under [NOTABLE], but only above this. */
internal const val TOP_MIN = 1.3

/** Fewer points and the numbers never pick it, however it compares in a quiet community. */
internal const val MIN_POINTS = 10
private const val DAY_MS = 24 * 60 * 60_000L

/**
 * How a post stands out in its own community, in this batch: its points against the
 * community's median, and (less) its comments against theirs. 1 = a typical post.
 * Relative, so a small community's big day counts as much as a big one's.
 */
internal fun notabilityOf(posts: List<Post>): Map<String, Double> {
    val out = HashMap<String, Double>()
    for ((_, group) in posts.groupBy { it.subreddit.lowercase() }) {
        val score = median(group.map { it.score.toDouble() }).coerceAtLeast(1.0)
        val comments = median(group.map { it.numComments.toDouble() }).coerceAtLeast(1.0)
        for (p in group) out[p.id] = 0.7 * p.score.coerceAtLeast(0) / score + 0.3 * p.numComments / comments
    }
    return out
}

private fun median(v: List<Double>): Double {
    if (v.isEmpty()) return 0.0
    val s = v.sorted()
    return if (s.size % 2 == 1) s[s.size / 2] else (s[s.size / 2 - 1] + s[s.size / 2]) / 2
}

/** The line under a post saying why it's in the digest, from the numbers. */
internal fun digestWhy(p: Post, notability: Double, top: Boolean): String {
    val comments = if (p.numComments > 0) " · ${compactNumber(p.numComments)} comments" else ""
    if (top && notability < NOTABLE) return "Top post today in r/${p.subreddit}$comments"
    val times = if (notability >= 10) "${notability.roundToInt()}×" else "${(notability * 10).roundToInt() / 10.0}×".replace(".0×", "×")
    return (if (top) "Top post today in r/${p.subreddit} · $times a typical post" else "$times a typical post there") + comments
}

/** The candidates of a build, as both the AI request and the merge see them. */
private class Batch(val today: DigestDay?, val fresh: List<Post>, val notability: Map<String, Double>, val tops: Set<String>, val toJudge: List<Post>)

private fun batch(prev: DigestDay?, day: String, candidates: List<Post>, now: Long, shownBefore: Set<String>): Batch {
    val today = prev?.takeIf { it.day == day }
    // (Shown on an earlier day: a morning digest doesn't repeat last night's posts.)
    val fresh = candidates
        .filter { !it.stickied && it.createdUtc > 0 && now - it.createdUtc <= DAY_MS && it.id !in shownBefore }
        .distinctBy { it.id }
    val notability = notabilityOf(fresh)
    // Each community's best post today counts too, when it stands out a little.
    val tops = fresh.groupBy { it.subreddit.lowercase() }
        .mapNotNull { (_, g) -> g.maxByOrNull { notability[it.id] ?: 0.0 } }
        .filter { (notability[it.id] ?: 0.0) >= TOP_MIN }
        .mapTo(HashSet()) { it.id }
    val shown = today?.items?.mapTo(HashSet()) { it.post.id } ?: emptySet()
    val judged = today?.judged ?: emptyMap()
    // Not judged yet, or not picked and twice as notable as then (one second look).
    val toJudge = fresh.filter { p ->
        if (p.id in shown) return@filter false
        val j = judged[p.id] ?: return@filter true
        !j.picked && !j.secondLook && (notability[p.id] ?: 0.0) >= 2 * j.notability
    }.sortedByDescending { notability[it.id] ?: 0.0 }
    return Batch(today, fresh, notability, tops, toJudge)
}

/**
 * What a build would send the AI: the posts to judge (never one read before it was
 * judged), most notable first, at most [max]. Empty: no AI call.
 */
fun digestPending(
    prev: DigestDay?,
    day: String,
    candidates: List<Post>,
    readIds: Set<String>,
    now: Long,
    max: Int = AI_CANDIDATES,
    shownBefore: Set<String> = emptySet(),
): List<Post> {
    val b = batch(prev, day, candidates, now, shownBefore)
    return b.toJudge.filter { it.id in (b.today?.judged ?: emptyMap()) || it.id !in readIds }.take(max)
}

/** How many posts the AI is shown: the most notable, not the final picks (it chooses). */
const val AI_CANDIDATES = 40

/**
 * Today's digest after a build or refresh ([prev]: the day so far, null for a first
 * build or a rebuild). [candidates]: the communities' top posts of the day, already
 * without hidden and filtered ones; [readIds]: posts the user has read.
 *
 * Posts judged earlier keep their verdict (a refresh only judges what's new), except
 * one not picked whose notability has since doubled: it gets one second look. Nothing
 * already in the digest goes away; new picks go after it. The size is the target for
 * the day's first build; later ones add up to the per-community cap (and Everything
 * notable keeps its 30).
 *
 * With [ai] (the AI's verdicts on [digestPending]'s posts), it picks instead of the
 * numbers: the posts it rated 2 or more, most important first, with its "why"; a post
 * it didn't rate isn't picked. [aiFailed]: the AI was wanted and failed, so this is by
 * the numbers and the screen says so. [shownBefore]: posts in earlier days' digests,
 * left out.
 */
fun mergeDigest(
    prev: DigestDay?,
    day: String,
    candidates: List<Post>,
    readIds: Set<String>,
    size: DigestSize,
    now: Long,
    ai: DigestAi? = null,
    aiFailed: Boolean = false,
    shownBefore: Set<String> = emptySet(),
): DigestDay {
    val b = batch(prev, day, candidates, now, shownBefore)
    val today = b.today
    val notability = b.notability
    val tops = b.tops

    val byId = b.fresh.associateBy { it.id }
    // What's shown stays, with today's numbers (points, comments).
    val items = (today?.items ?: emptyList()).mapTo(ArrayList()) { item -> byId[item.post.id]?.let { item.copy(post = it) } ?: item }
    val judged = HashMap(today?.judged ?: emptyMap())

    // One copy of a link or a story: against what's shown, then each pick.
    val urls = items.mapNotNullTo(HashSet()) { normalisedUrl(it.post) }
    val stories = items.map { titleKeywords(it.post.title).toSet() }.filterTo(ArrayList()) { it.size >= 3 }
    val perCommunity = HashMap<String, Int>()
    for (it in items) perCommunity.merge(it.post.subreddit.lowercase(), 1, Int::plus)
    val cap = if (today == null || size == DigestSize.EVERYTHING) size.items else Int.MAX_VALUE

    val verdicts = ai?.verdicts
    val toJudge = if (verdicts == null) b.toJudge
    else b.toJudge.sortedWith(compareByDescending<Post> { verdicts[it.id]?.importance ?: 0 }.thenByDescending { notability[it.id] ?: 0.0 })

    for (p in toJudge) {
        val n = notability[p.id] ?: 0.0
        val again = p.id in judged
        val sub = p.subreddit.lowercase()
        val words = titleKeywords(p.title).toSet()
        val url = normalisedUrl(p)
        val verdict = verdicts?.get(p.id)
        val pick = when {
            // Read before it was ever judged: it shouldn't take a place.
            !again && p.id in readIds -> false
            // The AI chooses: what it rated under 2, or didn't rate, stays out.
            verdicts != null -> verdict != null && verdict.importance >= 2
            p.score < MIN_POINTS -> false
            n < NOTABLE && p.id !in tops -> false
            else -> true
        } && when {
            items.size >= cap -> false
            (perCommunity[sub] ?: 0) >= size.perCommunity -> false
            url != null && url in urls -> false
            words.size >= 3 && stories.any { sameStory(it, words) } -> false
            else -> true
        }
        judged[p.id] = Judged(pick, n, now, secondLook = again)
        if (!pick) continue
        val why = verdict?.why?.takeIf { it.isNotBlank() } ?: digestWhy(p, n, p.id in tops)
        items.add(DigestItem(p, why, n, now, importance = verdict?.importance ?: 0))
        perCommunity.merge(sub, 1, Int::plus)
        url?.let(urls::add)
        if (words.size >= 3) stories.add(words)
    }
    return DigestDay(
        day = day,
        builtAt = today?.builtAt ?: now,
        refreshedAt = now,
        seenAt = today?.seenAt ?: now,
        items = items,
        judged = judged,
        // The overview is about the day's first build; a refresh keeps it.
        overview = today?.overview ?: ai?.overview?.takeIf { it.isNotBlank() },
        aiFailed = aiFailed,
        aiAt = if (ai != null || aiFailed) now else today?.aiAt ?: 0,
    )
}

/**
 * [day] with the AI's lines for the posts it was shown (picked by the numbers, so its
 * ratings don't count) and its overview, when the day has none yet.
 */
fun explainDigest(day: DigestDay, ai: DigestAi, now: Long): DigestDay = day.copy(
    items = day.items.map { item -> ai.verdicts[item.post.id]?.why?.takeIf { it.isNotBlank() }?.let { item.copy(why = it) } ?: item },
    overview = day.overview ?: ai.overview?.takeIf { it.isNotBlank() },
    aiFailed = false,
    aiAt = now,
)

/** The items in [order]: one list across communities (each card says its community). */
fun orderDigest(items: List<DigestItem>, order: DigestOrder): List<DigestItem> = when (order) {
    DigestOrder.NOTABLE -> items.sortedByDescending { it.notability }
    DigestOrder.UPVOTED -> items.sortedByDescending { it.post.score }
    DigestOrder.NEWEST -> items.sortedByDescending { it.post.createdUtc }
    DigestOrder.AI -> items.sortedWith(compareByDescending<DigestItem> { it.importance }.thenByDescending { it.notability })
}
