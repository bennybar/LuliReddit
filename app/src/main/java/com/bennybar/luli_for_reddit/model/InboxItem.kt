package com.bennybar.luli_for_reddit.model

import androidx.compose.runtime.Immutable
import com.bennybar.luli_for_reddit.core.arr
import com.bennybar.luli_for_reddit.core.get
import com.bennybar.luli_for_reddit.core.isTrue
import com.bennybar.luli_for_reddit.core.long
import com.bennybar.luli_for_reddit.core.str
import kotlinx.serialization.json.JsonElement

enum class InboxKind { COMMENT_REPLY, POST_REPLY, MENTION, MESSAGE }

@Immutable
data class InboxItem(
    val fullname: String, // t1_ or t4_
    val kind: InboxKind,
    val author: String,
    val subject: String,
    val body: String,
    val createdUtc: Long,
    val isNew: Boolean = false,
    val context: String? = null, // permalink for comment replies/mentions
    val linkTitle: String? = null,
    val subreddit: String? = null,
    val dest: String? = null,
    val replies: List<InboxItem> = emptyList(),
) {
    val isMessage: Boolean get() = kind == InboxKind.MESSAGE

    /** For comment replies/mentions: (subreddit, postId) parsed from [context]. */
    val postRef: Pair<String, String>?
        get() {
            val ctx = context ?: return null
            val segs = ctx.substringBefore('?').split('/').filter { it.isNotEmpty() }
            val ci = segs.indexOf("comments")
            return if (ci >= 1 && ci + 1 < segs.size) segs[ci - 1] to segs[ci + 1] else null
        }

    /** The focused comment id in [context] (`…/comments/<post>/<slug>/<comment>/`), if any. */
    val contextCommentId: String?
        get() {
            val segs = (context ?: return null).substringBefore('?').split('/').filter { it.isNotEmpty() }
            val ci = segs.indexOf("comments")
            return if (ci != -1 && segs.size > ci + 3) segs[ci + 3] else null
        }

    companion object {
        fun fromChild(child: JsonElement): InboxItem {
            val type = child["kind"].str()
            val d = child["data"]
            val created = (d["created_utc"].long() ?: 0L) * 1000

            if (type == "t4") {
                return InboxItem(
                    fullname = d["name"].str() ?: "t4_${d["id"].str()}",
                    kind = InboxKind.MESSAGE,
                    author = d["author"].str() ?: "[unknown]",
                    subject = (d["subject"].str() ?: "").trim(),
                    body = d["body"].str() ?: "",
                    createdUtc = created,
                    isNew = d["new"].isTrue(),
                    dest = d["dest"].str(),
                    subreddit = d["subreddit"].str(),
                    replies = d["replies"]["data"]["children"].arr()?.map { fromChild(it) } ?: emptyList(),
                )
            }

            val kind = when (d["type"].str()) {
                "post_reply" -> InboxKind.POST_REPLY
                "username_mention" -> InboxKind.MENTION
                else -> InboxKind.COMMENT_REPLY
            }
            return InboxItem(
                fullname = d["name"].str() ?: "t1_${d["id"].str()}",
                kind = kind,
                author = d["author"].str() ?: "[deleted]",
                subject = (d["subject"].str() ?: "").trim(),
                body = d["body"].str() ?: "",
                createdUtc = created,
                isNew = d["new"].isTrue(),
                context = d["context"].str(),
                linkTitle = d["link_title"].str()?.trim(),
                subreddit = d["subreddit"].str(),
            )
        }
    }
}
