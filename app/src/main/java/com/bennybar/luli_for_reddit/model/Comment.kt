package com.bennybar.luli_for_reddit.model

import com.bennybar.luli_for_reddit.core.giphyUrl
import androidx.compose.runtime.Immutable
import com.bennybar.luli_for_reddit.core.arr
import com.bennybar.luli_for_reddit.core.bool
import com.bennybar.luli_for_reddit.core.get
import com.bennybar.luli_for_reddit.core.int
import com.bennybar.luli_for_reddit.core.isTrue
import com.bennybar.luli_for_reddit.core.long
import com.bennybar.luli_for_reddit.core.obj
import com.bennybar.luli_for_reddit.core.str
import kotlinx.serialization.json.JsonElement

/**
 * A node in the comment tree. `kind: t1` is a comment; `kind: more` is a
 * "load more comments" placeholder ([isMore]).
 */
@Immutable
data class Comment(
    val id: String,
    val fullname: String, // t1_xxx
    val parentId: String = "", // t1_xxx or t3_xxx
    val author: String,
    val body: String,
    val score: Int,
    val createdUtc: Long, // millis since epoch
    val depth: Int,
    val distinguished: String? = null,
    val stickied: Boolean = false,
    val scoreHidden: Boolean = false,
    val saved: Boolean = false,
    val likes: Boolean? = null,
    // Present on user/saved comment listings — link back to the parent post.
    val linkTitle: String = "",
    val permalink: String = "",
    val subreddit: String = "",
    /** media_metadata id → playable URL, for media referenced as `![gif](giphy|…)`. */
    val media: Map<String, String> = emptyMap(),
    val replies: List<Comment> = emptyList(),
    // "more" placeholder fields
    val isMore: Boolean = false,
    val moreCount: Int = 0,
    val moreChildren: List<String> = emptyList(),
    val collapsed: Boolean = false,
) {
    companion object {
        fun fromChild(child: JsonElement, depth: Int): Comment {
            val kind = child["kind"].str()
            val d = child["data"]

            if (kind == "more") {
                val children = d["children"].arr()?.mapNotNull { it.str() } ?: emptyList()
                // "Continue this thread" stubs all come as id "_" / name "t1__":
                // give each a unique id from its parent, or two in one thread
                // would share a list key (a crash).
                val stub = d["id"].str() == "_"
                val parent = d["parent_id"].str() ?: ""
                return Comment(
                    id = if (stub) "more_$parent" else d["id"].str() ?: "more",
                    fullname = if (stub) "more_$parent" else d["name"].str() ?: "more_${d["id"].str()}",
                    parentId = d["parent_id"].str() ?: "",
                    author = "",
                    body = "",
                    score = 0,
                    createdUtc = 0,
                    depth = depth,
                    isMore = true,
                    moreCount = d["count"].int() ?: children.size,
                    moreChildren = children,
                )
            }

            val replies = d["replies"]["data"]["children"].arr()
                ?.filter { it.obj() != null }
                ?.map { fromChild(it, depth + 1) }
                ?: emptyList()

            return Comment(
                // Some responses (a website-session /api/comment) give the id
                // already prefixed ("t1_abc") and no name.
                id = d["id"].str()?.removePrefix("t1_") ?: "",
                fullname = d["name"].str() ?: "t1_${d["id"].str()?.removePrefix("t1_")}",
                parentId = d["parent_id"].str() ?: "",
                author = d["author"].str() ?: "[deleted]",
                body = d["body"].str() ?: "",
                score = d["score"].int() ?: 0,
                createdUtc = (d["created_utc"].long() ?: 0L) * 1000,
                depth = depth,
                distinguished = d["distinguished"].str(),
                stickied = d["stickied"].isTrue(),
                scoreHidden = d["score_hidden"].isTrue(),
                saved = d["saved"].isTrue(),
                likes = d["likes"].bool(),
                linkTitle = d["link_title"].str()?.trim() ?: "",
                permalink = d["permalink"].str() ?: "",
                subreddit = d["subreddit"].str() ?: "",
                media = mediaUrls(d["media_metadata"]),
                replies = replies,
            )
        }

        /**
         * Resolves `media_metadata` (GIFs from Reddit's GIF picker, uploaded
         * images) to one URL per id. Emotes are left out: they sit inline in text.
         */
        internal fun mediaUrls(raw: JsonElement?): Map<String, String> {
            val m = raw.obj() ?: return emptyMap()
            val out = LinkedHashMap<String, String>()
            for ((key, value) in m) {
                if (key.startsWith("emote|") || value.obj() == null) continue
                if (value["status"].str() != "valid") {
                    // Reddit often sends GIF-picker GIFs as "invalid" with no URL
                    // (its own apps still show them): use Giphy's copy by id.
                    giphyUrl(key)?.let { out[key] = it }
                    continue
                }
                val s = value["s"].obj() ?: continue
                val url = s["gif"].str() ?: s["u"].str() ?: s["mp4"].str() ?: continue
                out[key] = url.replace("&amp;", "&")
            }
            return out
        }
    }
}
