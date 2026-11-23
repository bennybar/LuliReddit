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
    STANDARD(12, 3, "Standard", "About 12 posts, at most 3 from a community"),
    EVERYTHING(30, 5, "Everything notable", "Every notable post, up to 30"),
    ;

    companion object {
        fun of(i: Int) = entries.getOrElse(i) { STANDARD }
    }
}

/** A post in a digest, with why it's there. [addedAt]: when this day's digest gained it. */
data class DigestItem(val post: Post, val why: String, val notability: Double, val addedAt: Long)

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
) {
    fun isNew(item: DigestItem) = item.addedAt > builtAt && item.addedAt > seenAt
}

/** At or above this, a post is notable: twice what's usual in its community. */
internal const val NOTABLE = 2.0
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
    val sub = "r/${p.subreddit}"
    val comments = if (p.numComments > 0) " · ${compactNumber(p.numComments)} comments" else ""
    if (top && notability < NOTABLE) return "Top post today in $sub$comments"
    val times = if (notability >= 10) "${notability.roundToInt()}×" else "${(notability * 10).roundToInt() / 10.0}×".replace(".0×", "×")
    return (if (top) "Top post today in $sub, $times a typical post" else "$times a typical post in $sub") + comments
}

/**
 * Today's digest after a build or refresh ([prev]: the day so far, null for a first
 * build or a rebuild). [candidates]: the communities' top posts of the day, already
 * without hidden and filtered ones; [readIds]: posts the user has read.
 *
 * Posts judged earlier keep their verdict (a refresh only judges what's new), except
 * one not picked whose notability has since doubled: it gets one second look. Nothing
 * already in the digest goes away or moves; new picks go after it. The size is the
 * target for the day's first build; later ones add up to the per-community cap
 * (and Everything notable keeps its 30).
 */
fun mergeDigest(
    prev: DigestDay?,
    day: String,
    candidates: List<Post>,
    readIds: Set<String>,
    size: DigestSize,
    now: Long,
): DigestDay {
    val today = prev?.takeIf { it.day == day }
    val fresh = candidates
        .filter { !it.stickied && it.createdUtc > 0 && now - it.createdUtc <= DAY_MS }
        .distinctBy { it.id }
    val notability = notabilityOf(fresh)
    // Each community's best post today is notable whatever its number.
    val tops = fresh.groupBy { it.subreddit.lowercase() }
        .mapNotNull { (_, g) -> g.maxByOrNull { notability[it.id] ?: 0.0 }?.id }
        .toHashSet()

    val byId = fresh.associateBy { it.id }
    // What's shown stays, with today's numbers (points, comments).
    val items = (today?.items ?: emptyList()).mapTo(ArrayList()) { item -> byId[item.post.id]?.let { item.copy(post = it) } ?: item }
    val shown = items.mapTo(HashSet()) { it.post.id }
    val judged = HashMap(today?.judged ?: emptyMap())

    // One copy of a link or a story: against what's shown, then each pick.
    val urls = items.mapNotNullTo(HashSet()) { normalisedUrl(it.post) }
    val stories = items.map { titleKeywords(it.post.title).toSet() }.filterTo(ArrayList()) { it.size >= 3 }
    val perCommunity = HashMap<String, Int>()
    for (it in items) perCommunity.merge(it.post.subreddit.lowercase(), 1, Int::plus)
    val cap = if (today == null || size == DigestSize.EVERYTHING) size.items else Int.MAX_VALUE

    val toJudge = fresh.filter { p ->
        if (p.id in shown) return@filter false
        val j = judged[p.id] ?: return@filter true
        !j.picked && !j.secondLook && (notability[p.id] ?: 0.0) >= 2 * j.notability
    }.sortedByDescending { notability[it.id] ?: 0.0 }

    for (p in toJudge) {
        val n = notability[p.id] ?: 0.0
        val again = p.id in judged
        val sub = p.subreddit.lowercase()
        val words = titleKeywords(p.title).toSet()
        val url = normalisedUrl(p)
        val pick = when {
            // Read before it was ever judged: it shouldn't take a place.
            !again && p.id in readIds -> false
            n < NOTABLE && p.id !in tops -> false
            items.size >= cap -> false
            (perCommunity[sub] ?: 0) >= size.perCommunity -> false
            url != null && url in urls -> false
            words.size >= 3 && stories.any { sameStory(it, words) } -> false
            else -> true
        }
        judged[p.id] = Judged(pick, n, now, secondLook = again)
        if (!pick) continue
        items.add(DigestItem(p, digestWhy(p, n, p.id in tops), n, now))
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
    )
}

/**
 * The items grouped by community for the screen, in the order the communities first
 * appear (a first build is by notability, so the community with the day's biggest
 * post leads; later picks join their community, or come last).
 */
fun groupByCommunity(items: List<DigestItem>): List<Pair<String, List<DigestItem>>> {
    val groups = LinkedHashMap<String, MutableList<DigestItem>>()
    for (it in items) groups.getOrPut(it.post.subreddit.lowercase()) { ArrayList() }.add(it)
    return groups.map { (_, list) -> list.first().post.subreddit to list }
}
