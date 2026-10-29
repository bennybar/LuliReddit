package com.bennybar.luli_for_reddit.data

import com.bennybar.luli_for_reddit.core.AppJson
import com.bennybar.luli_for_reddit.core.arr
import com.bennybar.luli_for_reddit.core.bool
import com.bennybar.luli_for_reddit.core.get
import com.bennybar.luli_for_reddit.core.giphyUrl
import com.bennybar.luli_for_reddit.core.int
import com.bennybar.luli_for_reddit.core.obj
import com.bennybar.luli_for_reddit.core.str
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.addJsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject

// Website sign-in: when Reddit's edge refuses a thread's .json (403, as it did
// search and /by_id), the thread loads like in Reddit's app: the post by id
// and its comment forest from PostComments, mapped to the comments response
// the app already parses (and saves for offline reading).
internal const val GQL_POST_COMMENTS = "8a25ae56c1d4813102f4eded0c427b99f46f6a63f77630e78767f27ef5186f1f"

/**
 * A "more" row from GraphQL holds its cursor as its only child id, behind
 * this prefix: getMoreComments continues it through PostComments, since
 * /api/morechildren only takes comment ids.
 */
internal const val GQL_MORE = "gql:"

// The comment fragment's switches; off: what the app doesn't show.
private val commentFlags = mapOf(
    "includeAwards" to false, "includeCommentsHtmlField" to false, "includeIsGildable" to false,
    "includeModerationInfo" to false, "subredditUserPostEditingAllowed" to false,
    "includeExtendedVideoAsset" to true, "includePlaybackMp4s" to true, "includeMuxedMp4s" to true,
    "includeVideoPlaybackInComments" to false, "includeCommentViewStats" to false,
    "includePremiumAvatarTreatment" to false, "includeCommentFollowedForNotificationsStatus" to false,
    "includeCommentEntityHighlights" to false, "includeRedditHandleInfo" to false,
    "includeVerificationStatus" to false,
)

private val gqlCommentSorts = mapOf(
    "confidence" to "CONFIDENCE", "top" to "TOP", "new" to "NEW",
    "controversial" to "CONTROVERSIAL", "old" to "OLD", "qa" to "QA",
)

/**
 * PostComments' variables: a post's comments ([after]: a "more" row's
 * cursor), or [focusCommentId]'s thread with 3 parents, like the website's
 * `?comment=…&context=3`. Reddit sends at most 25 comments per request.
 */
internal fun postCommentsVariables(postFullname: String, sort: String, focusCommentId: String?, after: String?) =
    buildJsonObject {
        for ((k, v) in commentFlags) put(k, v)
        put("id", postFullname)
        put("maxDepth", 10)
        put("count", 200)
        put("includeAdEligibility", false)
        put("isUserMod", false)
        put("skipPostInfoFragment", true)
        put("includeConsistencyToken", false)
        putJsonObject("callerContext") { put("referrer", "FEED") }
        gqlCommentSorts[sort]?.let { put("sortType", it) }
        if (after != null) put("after", after)
        if (focusCommentId != null) {
            putJsonObject("focusedCommentContext") {
                put("commentId", "t1_$focusCommentId")
                put("isFocusedThreadOnly", true)
                put("minDeepCommentParents", 3)
            }
            put("numParents", 3)
        }
    }

/**
 * PostComments' forest (a flat, depth-first list of comments and "more"
 * entries) as listing things (kind t1 / more), each naming its parent: the
 * shape /api/morechildren returns. Depths are relative (a loaded "more"
 * starts deeper, a focused thread's parents are negative), so the shallowest
 * entries hang off the forest's own parent, else [linkFullname].
 */
internal fun gqlCommentThings(trees: List<JsonElement>, linkFullname: String, moreParent: String? = null): List<JsonObject> {
    val base = trees.mapNotNull { it["depth"].int() }.minOrNull() ?: 0
    // ancestors[d]: the latest comment at relative depth d.
    val ancestors = ArrayList<String>()
    val out = ArrayList<JsonObject>()
    trees.forEachIndexed { i, tree ->
        val depth = tree["depth"].int() ?: base
        val level = depth - base
        // A loaded "more" ([moreParent]): its shallowest entries are that row's
        // replies, whatever form Reddit's parentId takes (CommentTree.replaceMore
        // attaches them by it).
        val parent = if (level == 0) moreParent ?: tree["parentId"].str() ?: linkFullname
        else ancestors.getOrNull(level - 1) ?: return@forEachIndexed
        val more = tree["more"].obj()
        if (more != null) {
            val cursor = more["cursor"].str() ?: return@forEachIndexed
            out += buildJsonObject {
                put("kind", "more")
                putJsonObject("data") {
                    put("id", "more_$parent")
                    put("name", "more_$parent")
                    put("parent_id", parent)
                    put("count", more["count"].int() ?: 0)
                    // The row's parent travels with its cursor, for when it loads.
                    putJsonArray("children") { add(JsonPrimitive("$GQL_MORE$parent $cursor")) }
                }
            }
            return@forEachIndexed
        }
        val n = tree["node"].obj() ?: return@forEachIndexed
        // A deleted comment comes without its id, but the replies under it
        // name it as their parent (Reddit only keeps deleted ones with replies).
        val name = n["id"].str()
            ?: trees.drop(i + 1).takeWhile { (it["depth"].int() ?: depth) > depth }
                .firstOrNull { it["depth"].int() == depth + 1 && it["parentId"].str() != null }?.get("parentId").str()
            ?: "t1_deleted$i"
        ancestors.subList(level, ancestors.size).clear()
        ancestors.add(name)
        val deleted = n["__typename"].str() != "Comment" || n["isRemoved"].bool() == true || n["content"] !is JsonObject
        val gone = n["removedByCategory"].str().let { if (it == null || it == "DELETED") "[deleted]" else "[removed]" }
        val flair = n["authorFlair"]
        out += buildJsonObject {
            put("kind", "t1")
            putJsonObject("data") {
                put("id", name.removePrefix("t1_"))
                put("name", name)
                put("parent_id", parent)
                put("author", if (deleted) "[deleted]" else n["authorInfo"]["name"].str() ?: "[deleted]")
                put("body", if (deleted) gone else gqlMarkdown(n["content"], name.removePrefix("t1_")))
                put("score", n["score"].int() ?: 0)
                put("created_utc", gqlSeconds(n["createdAt"].str()))
                put("distinguished", when (n["distinguishedAs"].str()) { "MODERATOR" -> "moderator"; "ADMIN" -> "admin"; else -> null })
                put("stickied", n["isStickied"].bool() == true)
                put("score_hidden", n["isScoreHidden"].bool() == true)
                put("saved", n["isSaved"].bool() == true)
                put("is_submitter", n["isOP"].bool() == true)
                when (n["voteState"].str()) {
                    "UP" -> put("likes", true)
                    "DOWN" -> put("likes", false)
                    else -> put("likes", JsonNull)
                }
                put("permalink", n["permalink"].str())
                // The flair's richtext is a JSON string here, an array on the website.
                flair["richtext"].str()?.let { runCatching { AppJson.parseToJsonElement(it) }.getOrNull() }
                    ?.let { put("author_flair_richtext", it) }
                put("author_flair_text", flair["text"].str())
                // Uploaded images and GIFs the markdown names by id (`![img](id)`).
                val media = n["content"]["richtextMedia"].arr()?.mapNotNull { m -> m["id"].str()?.let { it to mediaUrl(m) } }
                if (!media.isNullOrEmpty()) {
                    putJsonObject("media_metadata") {
                        for ((id, url) in media) {
                            putJsonObject(id) {
                                put("status", if (url != null) "valid" else "unprocessed")
                                if (url != null) putJsonObject("s") { put("u", url) }
                            }
                        }
                    }
                }
            }
        }
    }
    return out
}

/**
 * PostsByIds' post and PostComments' forest as a thread's comments response
 * (`[post listing, comment listing]`), which parseThread reads and the
 * offline copy keeps.
 */
internal fun gqlThreadData(post: JsonObject, trees: List<JsonElement>): JsonArray {
    val things = gqlCommentThings(trees, post["name"].str() ?: "")
    val byParent = things.groupBy { it["data"]["parent_id"].str() }
    val names = things.mapTo(HashSet()) { it["data"]["name"].str() }
    fun nest(t: JsonObject): JsonObject {
        val replies = byParent[t["data"]["name"].str()] ?: return t
        val data = t["data"].obj()!!
        return JsonObject(t + ("data" to JsonObject(data + ("replies" to buildJsonObject {
            putJsonObject("data") { put("children", JsonArray(replies.map(::nest))) }
        }))))
    }
    return buildJsonArray {
        addJsonObject { putJsonObject("data") { putJsonArray("children") { addJsonObject { put("kind", "t3"); put("data", post) } } } }
        addJsonObject {
            putJsonObject("data") {
                put("children", JsonArray(things.filter { it["data"]["parent_id"].str() !in names }.map(::nest)))
            }
        }
    }
}

// A richtext media asset's URL, largest size first.
private fun mediaUrl(m: JsonElement?): String? =
    listOf("xxxlarge", "xxlarge", "xlarge", "large", "medium").firstNotNullOfOrNull { m[it]["url"].str() } ?: m["url"].str()

// Markdown's inline syntax, escaped in plain text so it reads literally.
private val mdSpecial = Regex("""[\\`*_~^\[\]>]""")

/**
 * A comment's body as markdown. The source markdown when Reddit sends it
 * (what editing, copying and translating need); otherwise converted from the
 * richtext, Reddit's own parse of the markdown as JSON:
 *  - blocks: par, h{l}, blockquote, list{o} > li, code > raw lines, hr,
 *    table{h, c}, img / gif / video{id}
 *  - inline: text{t, f}, link{u, t, f}, r/ and u/{t, l}, spoilertext{c},
 *    br, raw{t}, img / gif / video{id}
 *  - f: [bits, start, length] ranges of t, counted in code points; bits
 *    1 bold, 2 italic, 8 strike, 32 superscript, 64 code.
 * Media become bare links, which the comment renderer shows as media.
 */
internal fun gqlMarkdown(content: JsonElement?, thingId: String): String {
    content["markdown"].str()?.takeIf { it.isNotEmpty() }?.let { return it }
    val doc = content["richtext"].str()?.let { runCatching { AppJson.parseToJsonElement(it) }.getOrNull() }["document"].arr()
        ?: return ""
    val media = content["richtextMedia"].arr()?.associateBy { it["id"].str() } ?: emptyMap()
    fun escape(t: String) = t.replace(mdSpecial) { "\\" + it.value }
    fun mediaLink(n: JsonElement): String {
        val id = n["id"].str() ?: return ""
        // The player link Reddit's own HTML used for videos in a body.
        if (n["e"].str() == "video") return "https://reddit.com/link/$thingId/video/$id/player"
        return giphyUrl(id) ?: mediaUrl(media[id]) ?: ""
    }
    fun formatted(n: JsonElement, render: (String) -> String): String {
        val cps = (n["t"].str() ?: "").codePoints().toArray()
        fun slice(from: Int, to: Int): String {
            val a = from.coerceIn(0, cps.size)
            return String(cps, a, to.coerceIn(a, cps.size) - a)
        }
        val ranges = n["f"].arr()?.mapNotNull { r -> r[0].int()?.let { Triple(it, r[1].int() ?: 0, r[2].int() ?: 0) } }
            ?.sortedBy { it.second } ?: emptyList()
        val out = StringBuilder()
        var pos = 0
        for ((bits, start, length) in ranges) {
            if (start > pos) out.append(render(slice(pos, start)))
            val text = slice(maxOf(start, pos), start + length)
            pos = maxOf(pos, start + length)
            val core = text.trim()
            if (core.isEmpty()) {
                out.append(render(text))
                continue
            }
            // Markers must touch the text: `** bold**` isn't bold.
            var md = if (bits and 64 != 0) "`$core`" else render(core)
            if (bits and 32 != 0) md = "^($md)"
            if (bits and 8 != 0) md = "~~$md~~"
            if (bits and 2 != 0) md = "*$md*"
            if (bits and 1 != 0) md = "**$md**"
            out.append(text.substring(0, text.indexOf(core))).append(md).append(text.substring(text.indexOf(core) + core.length))
        }
        if (pos < cps.size) out.append(render(slice(pos, cps.size)))
        return out.toString()
    }
    fun inline(nodes: JsonElement?): String = (nodes.arr() ?: emptyList()).joinToString("") { n ->
        when (val e = n["e"].str()) {
            "text" -> formatted(n, ::escape)
            "link" -> {
                val url = (n["u"].str() ?: "").replace(" ", "%20").replace("(", "%28").replace(")", "%29")
                formatted(n) { "[${escape(it)}]($url)" }
            }
            "r/", "u/" -> (if (n["l"].bool() == true || n["l"].int() == 1) "/" else "") + e + (n["t"].str() ?: "")
            "spoilertext" -> ">!${inline(n["c"])}!<"
            "br" -> "  \n"
            "img", "gif", "video" -> mediaLink(n)
            else -> escape(n["t"].str() ?: "")
        }
    }
    fun blocks(nodes: JsonElement?): String = (nodes.arr() ?: emptyList()).joinToString("\n\n") { n ->
        when (n["e"].str()) {
            "par" -> inline(n["c"])
            "h" -> "#".repeat((n["l"].int() ?: 1).coerceIn(1, 6)) + " " + inline(n["c"])
            "blockquote" -> blocks(n["c"]).lines().joinToString("\n") { if (it.isEmpty()) ">" else "> $it" }
            "list" -> (n["c"].arr() ?: emptyList()).mapIndexed { i, li ->
                val marker = if (n["o"].bool() == true) "${i + 1}. " else "- "
                marker + blocks(li["c"]).lines().joinToString("\n" + " ".repeat(marker.length))
            }.joinToString("\n")
            "code" -> "```\n" + (n["c"].arr() ?: emptyList()).joinToString("\n") { it["t"].str() ?: "" } + "\n```"
            "hr" -> "---"
            "table" -> {
                val head = n["h"].arr() ?: emptyList()
                val rows = (n["c"].arr() ?: emptyList()).map { row -> (row.arr() ?: emptyList()).map { inline(it["c"]) } }
                (listOf(head.map { inline(it["c"]) }, head.map {
                    when (it["a"].str()) { "L" -> ":--"; "C" -> ":-:"; "R" -> "--:"; else -> "---" }
                }) + rows).joinToString("\n") { "| " + it.joinToString(" | ") + " |" }
            }
            "img", "gif", "video" -> mediaLink(n)
            // Anything newer: its inline content, or its text.
            else -> if (n["c"] is JsonArray) inline(n["c"]) else escape(n["t"].str() ?: "")
        }
    }
    return blocks(doc)
}
