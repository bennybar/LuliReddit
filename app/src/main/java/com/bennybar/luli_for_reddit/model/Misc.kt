package com.bennybar.luli_for_reddit.model

import androidx.compose.runtime.Immutable
import com.bennybar.luli_for_reddit.core.arr
import com.bennybar.luli_for_reddit.core.get
import com.bennybar.luli_for_reddit.core.str
import kotlinx.serialization.json.JsonElement

/** A user multireddit (custom feed). */
@Immutable
data class Multireddit(
    val name: String,
    val displayName: String,
    val path: String, // /user/{username}/m/{name}/
    val subreddits: List<String>,
    val descriptionMd: String = "",
    val visibility: String = "private",
    val iconUrl: String? = null,
) {
    companion object {
        fun fromData(d: JsonElement) = Multireddit(
            name = d["name"].str() ?: "",
            displayName = d["display_name"].str() ?: d["name"].str() ?: "",
            path = d["path"].str() ?: "",
            subreddits = d["subreddits"].arr()?.mapNotNull { it["name"].str()?.ifEmpty { null } } ?: emptyList(),
            descriptionMd = d["description_md"].str() ?: "",
            visibility = d["visibility"].str() ?: "private",
            iconUrl = d["icon_url"].str()?.ifEmpty { null },
        )
    }
}

/** One piece of a user flair: some text, or an emoji (an image Reddit hosts). */
@Immutable
data class FlairPart(val text: String? = null, val emojiUrl: String? = null)

/** A user's flair (#31): its text and emoji, in order. */
@Immutable
data class UserFlair(val parts: List<FlairPart>) {
    /** Just the words, for where images can't go. */
    val text: String get() = parts.mapNotNull { it.text }.joinToString("").replace(Regex("\\s+"), " ").trim()
}

/**
 * A user's flair from a post or comment: the richtext's text and emoji
 * parts; else the plain text without its :emoji: codes (no image links
 * there). Null when there's none.
 */
fun authorFlairOf(d: JsonElement?): UserFlair? {
    val rich = d["author_flair_richtext"].arr()
    val parts = if (!rich.isNullOrEmpty()) {
        rich.mapNotNull { p ->
            when (p["e"].str()) {
                "text" -> p["t"].str()?.takeIf { it.isNotEmpty() }?.let { FlairPart(text = it) }
                "emoji" -> p["u"].str()?.takeIf { it.startsWith("http") }?.let { FlairPart(emojiUrl = it) }
                else -> null
            }
        }
    } else {
        listOfNotNull(
            d["author_flair_text"].str()?.replace(Regex(":[\\w-]+:"), "")?.replace(Regex("\\s+"), " ")?.trim()
                ?.takeIf { it.isNotEmpty() }?.let { FlairPart(text = it) },
        )
    }
    // Tidy the ends: no leading / trailing spaces around the emoji.
    val tidy = parts.mapIndexed { i, p ->
        if (p.text == null) p
        else p.copy(text = p.text.let { t -> if (i == 0) t.trimStart() else t }.let { t -> if (i == parts.lastIndex) t.trimEnd() else t })
    }.filter { it.emojiUrl != null || !it.text.isNullOrEmpty() }
    return tidy.takeIf { it.isNotEmpty() }?.let(::UserFlair)
}

/** A choice of user flair in a community, and whether you may write your own text in it. */
@Immutable
data class UserFlairChoice(val id: String, val text: String, val editable: Boolean)

/** Your flair in a community now, and what you can pick from. */
@Immutable
data class UserFlairSelector(val currentText: String?, val currentId: String?, val choices: List<UserFlairChoice>)

/** A subreddit link flair template. */
@Immutable
data class Flair(val id: String, val text: String) {
    companion object {
        fun fromJson(j: JsonElement) = Flair(id = j["id"].str() ?: "", text = (j["text"].str() ?: "").trim())
    }
}

/** A page of items plus the cursor (`after`) for the next page. */
@Immutable
data class Listing<T>(val items: List<T>, val after: String? = null, val fromCache: Boolean = false) {
    val hasMore: Boolean get() = !after.isNullOrEmpty()
}
