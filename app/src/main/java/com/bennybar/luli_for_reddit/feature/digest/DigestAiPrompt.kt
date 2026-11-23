package com.bennybar.luli_for_reddit.feature.digest

import com.bennybar.luli_for_reddit.core.AppJson
import com.bennybar.luli_for_reddit.model.Post
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray

// The Digest's AI step (docs/digest-spec.md, section 6): one request per build, with
// the posts not judged yet; the reply is parsed leniently. Pure, so both are tested
// with canned replies (no real AI calls in tests).

/** What the AI is told about the user: their strongest learned words, and what they asked for more or less of. */
data class DigestInterests(
    val keywords: List<String> = emptyList(),
    val moreTopics: List<String> = emptyList(),
    val lessTopics: List<String> = emptyList(),
    val moreCommunities: List<String> = emptyList(),
    val lessCommunities: List<String> = emptyList(),
)

/** The system and user messages for [posts] (indexed in order). [language]: "" for the posts' own. */
fun digestAiMessages(
    posts: List<Post>,
    interests: DigestInterests,
    size: DigestSize,
    overview: Boolean,
    language: String,
    now: Long,
): Pair<String, String> {
    val lang = if (language.isEmpty()) "Write in the language most of the titles are in." else "Write in $language."
    val system = "You pick the most important Reddit posts of the last day for one reader, from communities " +
        "they follow. Rate each post's importance to this reader from 1 (skip) to 5 (must read), weighing " +
        "real news and substance over jokes and reposts, and the reader's interests. For each post worth " +
        "reading (2 or more), write \"why\": one plain sentence under 140 characters saying what it is " +
        "and why it matters. " +
        (if (overview) "Also write \"overview\": 2 to 4 sentences on what stood out today across these communities. " else "") +
        "$lang Reply with only JSON, no other text: " +
        (if (overview) "{\"overview\": \"…\", \"items\": [{\"i\": 0, \"importance\": 4, \"why\": \"…\"}]}"
        else "{\"items\": [{\"i\": 0, \"importance\": 4, \"why\": \"…\"}]}")
    val user = buildJsonObject {
        put("wanted", "about ${size.items} posts, at most ${size.perCommunity} from one community")
        put("interests", buildJsonObject {
            if (interests.keywords.isNotEmpty()) putJsonArray("often_reads") { interests.keywords.forEach { add(JsonPrimitive(it)) } }
            if (interests.moreTopics.isNotEmpty()) putJsonArray("more_of") { interests.moreTopics.forEach { add(JsonPrimitive(it)) } }
            if (interests.lessTopics.isNotEmpty()) putJsonArray("less_of") { interests.lessTopics.forEach { add(JsonPrimitive(it)) } }
            if (interests.moreCommunities.isNotEmpty()) putJsonArray("favour_communities") { interests.moreCommunities.forEach { add(JsonPrimitive(it)) } }
            if (interests.lessCommunities.isNotEmpty()) putJsonArray("less_from_communities") { interests.lessCommunities.forEach { add(JsonPrimitive(it)) } }
        })
        put("posts", buildJsonArray {
            posts.forEachIndexed { i, p ->
                add(buildJsonObject {
                    put("i", i)
                    put("community", p.subreddit)
                    put("title", p.title)
                    put("score", p.score)
                    put("comments", p.numComments)
                    put("age_hours", ((now - p.createdUtc) / 3_600_000L).coerceAtLeast(0))
                    p.linkFlairText?.takeIf { it.isNotBlank() }?.let { put("flair", it) }
                    if (p.isSelf && p.selftext.isNotBlank()) put("text", p.selftext.take(300))
                })
            }
        })
    }.toString()
    return system to user
}

/**
 * The AI's [reply] for [posts]: its verdicts by post id, and the overview. Lenient: a
 * code fence or words around the JSON are fine, unknown indices and broken items are
 * skipped. Null when there's nothing usable (the build then goes by the numbers).
 */
fun parseDigestAi(reply: String, posts: List<Post>): DigestAi? {
    val start = reply.indexOf('{')
    val end = reply.lastIndexOf('}')
    if (start < 0 || end <= start) return null
    val obj = runCatching { AppJson.parseToJsonElement(reply.substring(start, end + 1)) as? JsonObject }.getOrNull() ?: return null
    val list = obj["items"] as? JsonArray ?: return null
    val verdicts = LinkedHashMap<String, AiVerdict>()
    for (el in list) {
        val o = el as? JsonObject ?: continue
        val i = (o["i"] as? JsonPrimitive)?.intOrNull ?: continue
        val post = posts.getOrNull(i) ?: continue
        val importance = (o["importance"] as? JsonPrimitive)?.intOrNull?.coerceIn(1, 5) ?: continue
        val why = (o["why"] as? JsonPrimitive)?.contentOrNull?.trim().orEmpty()
        verdicts[post.id] = AiVerdict(importance, why)
    }
    if (verdicts.isEmpty() && list.isNotEmpty()) return null
    val overview = (obj["overview"] as? JsonPrimitive)?.contentOrNull?.trim()?.takeIf { it.isNotEmpty() }
    return DigestAi(overview, verdicts)
}
