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

/**
 * A user's flair as text (#31): the richtext's text parts, else the plain
 * text without its :emoji: codes (the emoji are images we don't draw).
 * Null when there's none.
 */
fun authorFlairOf(d: JsonElement?): String? {
    val rich = d["author_flair_richtext"].arr()
    val text = if (!rich.isNullOrEmpty()) {
        rich.filter { it["e"].str() == "text" }.joinToString("") { it["t"].str().orEmpty() }
    } else {
        d["author_flair_text"].str().orEmpty().replace(Regex(":[\\w-]+:"), "")
    }
    return text.replace(Regex("\\s+"), " ").trim().ifEmpty { null }
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
