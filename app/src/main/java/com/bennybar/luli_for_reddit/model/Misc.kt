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
