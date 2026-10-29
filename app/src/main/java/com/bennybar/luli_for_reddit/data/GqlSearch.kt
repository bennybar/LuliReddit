package com.bennybar.luli_for_reddit.data

import com.bennybar.luli_for_reddit.core.arr
import com.bennybar.luli_for_reddit.core.bool
import com.bennybar.luli_for_reddit.core.get
import com.bennybar.luli_for_reddit.core.int
import com.bennybar.luli_for_reddit.core.obj
import com.bennybar.luli_for_reddit.core.str
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.addJsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatterBuilder
import java.time.temporal.ChronoField

// Website sign-in: Reddit's edge refuses the website's search endpoints and
// /by_id (403), so search and posts by id (Reddit Home, Blend) run on
// Reddit's app GraphQL API, as Reddit's own apps and other clients (e.g.
// Hydra) do. Its operations are persisted queries, run by
// name and the hash of the query Reddit already knows.
internal const val GQL_SEARCH_POSTS = "c3d31b88bfa15180fdcd0c8f6f13b8c0e131d0c981c9b9c8a7c537ddd0ed3348"
internal const val GQL_SEARCH_COMMUNITIES = "b58025ad0c98bdb93e9dc1db909accf440573bd7d3a48d2c73a02e96d33f1943"
internal const val GQL_SEARCH_PEOPLE = "db3607c1a7deea8441614a053c5f434f60da0c8c931db952f819a59d534d9743"
internal const val GQL_POSTS_BY_IDS = "b210ea1d852cdc2c25d9bff2d9fa8a406e1a968f36392798812f336694ac27f4"

/** A post (not an ad or an unavailable one) in GraphQL's results. */
internal fun gqlIsPost(n: JsonElement?): Boolean =
    n["__typename"].str() in setOf("SubredditPost", "ProfilePost", "DeletedSubredditPost")

/** PostsByIds' variables. */
internal fun postsByIdsVariables(ids: List<String>) = buildJsonObject {
    for ((k, v) in postFlags) put(k, v)
    putJsonArray("ids") { ids.forEach { add(JsonPrimitive(it)) } }
}

// The post fragment's switches, as Reddit's app sets them for full posts.
private val postFlags = mapOf(
    "includeSubredditInPosts" to true, "includeAwards" to true, "includePostStats" to true,
    "includeCurrentUserAwards" to false, "includeStillMediaAltText" to true,
    "includeExtraStillResolutions" to true, "includeExtendedVideoAsset" to false,
    "includePlaybackMp4s" to true, "includeMuxedMp4s" to true, "includeDevvitData" to true,
    "includeCommunityStatus" to true, "includeIsModRemovedContentReadAllowed" to true,
    "includeVideoPlaybackInComments" to false, "includeSubredditBackgroundColor" to true,
    "includeOverlayData" to true, "includeCtaEnrichedPageTitle" to true, "includePlaCards" to true,
    "includePlaCardThumbnail" to false, "includeWebviewPrefetchField" to true,
    "includeAdBrowserDestinationField" to true, "includeCollectionsHeroCard" to true,
    "includeGalleryAdUrl" to true, "includeCtaMediaColor" to true,
    "includeFollowedForNotificationsStatus" to true, "includePredictedRemovalReasons" to true,
    "includeRedditHandleInfo" to true, "includeVerificationStatus" to true,
    "skipModerationInfo" to false, "includeIsReceivingPostReplies" to false,
    "includeIsActiveComments" to true, "includeMediaSynthesis" to true,
    "skipRedditPlayPlaybackMp4s" to true, "includeLinkPreviewTitle" to false,
)

private val gqlSorts = mapOf("relevance" to "RELEVANCE", "hot" to "HOT", "new" to "NEW", "top" to "TOP", "comments" to "COMMENTS")

/** SearchPosts' variables; [after] is GraphQL's page cursor. */
internal fun searchPostsVariables(query: String, subreddit: String?, after: String?, sort: String, time: String) =
    buildJsonObject {
        for ((k, v) in postFlags) put(k, v)
        put("query", query)
        put("productSurface", "android")
        put("pageSize", 25)
        put("sort", gqlSorts[sort] ?: "RELEVANCE")
        if (after != null) put("afterCursor", after)
        putJsonArray("filters") {
            if (time != "all") addJsonObject { put("key", "time_range"); put("value", time) }
            if (subreddit != null) addJsonObject { put("key", "subreddit_names"); put("value", subreddit) }
        }
    }

/** One kind of search result (posts, communities, authors): its nodes, and the next page's cursor (null at the end). */
internal fun gqlSearch(data: JsonObject, kind: String): Pair<List<JsonObject>, String?> {
    val list = data["search"]["general"][kind]
    val info = list["pageInfo"]
    val nodes = list["edges"].arr()?.mapNotNull { it["node"].obj() } ?: emptyList()
    return nodes to (if (info["hasNextPage"].bool() == false) null else info["endCursor"].str())
}

// "2026-10-04T00:26:11.575000+0000": up to 9 fraction digits, offset without a colon.
private val gqlTime = DateTimeFormatterBuilder()
    .appendPattern("yyyy-MM-dd'T'HH:mm:ss")
    .optionalStart().appendFraction(ChronoField.NANO_OF_SECOND, 0, 9, true).optionalEnd()
    .appendPattern("[XXX][XX]")
    .toFormatter()

/** A GraphQL time in epoch seconds, or 0. */
internal fun gqlSeconds(iso: String?): Double =
    iso?.let { runCatching { OffsetDateTime.parse(it, gqlTime).toEpochSecond().toDouble() }.getOrNull() } ?: 0.0

/** A community search result in the shape Subreddit.fromData reads. */
internal fun gqlSubredditData(n: JsonObject): JsonObject = buildJsonObject {
    val name = n["name"].str() ?: ""
    put("display_name", name)
    put("display_name_prefixed", n["prefixedName"].str() ?: "r/$name")
    put("subscribers", n["subscribersCount"].int() ?: 0)
    put("public_description", n["publicDescriptionText"].str() ?: "")
    put("icon_img", n["styles"]["icon"].str() ?: n["styles"]["legacyIcon"]["url"].str())
}

/** A people search result in the shape RedditUser.fromData reads (search only has total karma). */
internal fun gqlUserData(n: JsonObject): JsonObject = buildJsonObject {
    put("name", n["name"].str())
    put("link_karma", n["karma"]["total"].int() ?: 0)
    put("comment_karma", 0)
    put("created_utc", gqlSeconds(n["profile"]["createdAt"].str()))
}

/**
 * A GraphQL post (search, PostsByIds) in the shape Post.fromData reads
 * (Reddit's listing JSON): what a card shows, with its media. Opening it
 * loads the full post.
 */
internal fun gqlPostData(n: JsonObject): JsonObject {
    val fullname = n["id"].str() ?: ""
    val id = fullname.removePrefix("t3_")
    val community = (n["subreddit"] as? JsonObject) ?: n["profile"].obj()
    val sub = community["name"].str() ?: ""
    val url = n["url"].str() ?: ""
    val host = runCatching { java.net.URI(url).host }.getOrNull() ?: ""
    val isSelf = n["isSelfPost"].bool() == true
    // The image (a gallery's first) at each size, smallest first.
    fun size(s: JsonElement?): Triple<String, Int?, Int?>? =
        s["url"].str()?.let { Triple(it, s["dimensions"]["width"].int(), s["dimensions"]["height"].int()) }
    val still = n["media"]["still"]
    val asset = n["gallery"]["items"][0]["media"]
    val sizes = buildList {
        if (still is JsonObject) {
            for (k in listOf("small", "medium", "large", "midlarge480", "xlarge", "xlargePlus720", "xxlarge", "xxxlarge", "source")) {
                size(still[k])?.let(::add)
            }
        }
        if (asset is JsonObject) {
            for (k in listOf("small", "medium", "large", "xlarge", "xxlarge", "xxxlarge")) size(asset[k])?.let(::add)
            asset["url"].str()?.let { add(Triple(it, asset["width"].int(), asset["height"].int())) }
        }
    }.distinctBy { it.first }
    val media = n["media"]
    val hls = media["streaming"]["hlsUrl"].str()
    val gifMp4 = (media["animated"]["mp4_source"]["url"] ?: media["animated"]["mp4_xxxlarge"]["url"]).str()
    // Every gallery image, as gallery_data + media_metadata.
    val galleryItems = n["gallery"]["items"].arr()?.mapNotNull { it["media"].obj()?.takeIf { m -> m["url"].str() != null } }
        ?: emptyList()
    val root = n["crosspostRoot"]["post"].obj()
    val icon = community["styles"]["icon"].str() ?: community["styles"]["legacyIcon"]["url"].str()
    return buildJsonObject {
        put("id", id)
        put("name", fullname)
        put("title", n["postTitle"].str() ?: n["title"].str() ?: "")
        put("author", n["authorInfo"]["name"].str() ?: "[deleted]")
        put("subreddit", sub)
        put("subreddit_name_prefixed", community["prefixedName"].str() ?: "r/$sub")
        put("score", n["score"].int() ?: 0)
        put("num_comments", n["commentCount"].int() ?: 0)
        put("created_utc", gqlSeconds(n["createdAt"].str()))
        put("permalink", n["permalink"].str() ?: "/r/$sub/comments/$id/")
        put("url", url)
        put("domain", if (isSelf) "self.$sub" else host)
        put("is_self", isSelf)
        put("is_video", host == "v.redd.it")
        put("selftext", n["content"]["markdown"].str() ?: "")
        put("over_18", n["isNsfw"].bool() == true)
        put("spoiler", n["isSpoiler"].bool() == true)
        put("stickied", n["isStickied"].bool() == true)
        put("locked", n["isLocked"].bool() == true)
        put("saved", n["isSaved"].bool() == true)
        when (n["voteState"].str()) {
            "UP" -> put("likes", true)
            "DOWN" -> put("likes", false)
            else -> put("likes", JsonNull)
        }
        put("link_flair_text", n["flair"]["text"].str())
        put("thumbnail", sizes.firstOrNull()?.first ?: if (isSelf) "self" else "default")
        if (sizes.isNotEmpty()) {
            put("post_hint", when (host) { "i.redd.it" -> "image"; "v.redd.it" -> "hosted:video"; else -> "link" })
        }
        if (icon != null) putJsonObject("sr_detail") { put("icon_img", icon.substringBefore('?')) }
        if (hls != null) {
            putJsonObject("media") {
                putJsonObject("reddit_video") {
                    put("hls_url", hls)
                    put("is_gif", media["streaming"]["isGif"].bool() == true)
                }
            }
        }
        if (galleryItems.isNotEmpty()) {
            putJsonObject("gallery_data") {
                putJsonArray("items") { galleryItems.indices.forEach { i -> addJsonObject { put("media_id", "g$i") } } }
            }
            putJsonObject("media_metadata") {
                galleryItems.forEachIndexed { i, m ->
                    putJsonObject("g$i") {
                        putJsonObject("s") { put("u", m["url"].str()); put("x", m["width"].int()); put("y", m["height"].int()) }
                    }
                }
            }
        }
        if (root != null && root["id"].str() != fullname) putJsonArray("crosspost_parent_list") { add(gqlPostData(root)) }
        if (sizes.isNotEmpty() || gifMp4 != null) {
            putJsonObject("preview") {
                if (sizes.isNotEmpty()) {
                    putJsonArray("images") {
                        addJsonObject {
                            fun image(s: Triple<String, Int?, Int?>) = buildJsonObject {
                                put("url", s.first); put("width", s.second); put("height", s.third)
                            }
                            put("source", image(sizes.last()))
                            putJsonArray("resolutions") { sizes.forEach { add(image(it)) } }
                        }
                    }
                }
                if (gifMp4 != null) putJsonObject("reddit_video_preview") { put("fallback_url", gifMp4) }
            }
        }
    }
}
