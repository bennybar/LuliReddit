package com.bennybar.luli_for_reddit.model

import androidx.compose.runtime.Immutable
import com.bennybar.luli_for_reddit.core.get
import com.bennybar.luli_for_reddit.core.int
import com.bennybar.luli_for_reddit.core.long
import com.bennybar.luli_for_reddit.core.str
import kotlinx.serialization.json.JsonElement

@Immutable
data class RedditUser(
    val name: String,
    val iconUrl: String? = null,
    val bannerUrl: String? = null,
    val linkKarma: Int = 0,
    val commentKarma: Int = 0,
    val createdUtc: Long,
    val description: String = "",
) {
    companion object {
        fun fromData(d: JsonElement): RedditUser {
            fun clean(s: String?) = if (s.isNullOrEmpty()) null else s.replace("&amp;", "&").substringBefore('?')
            val sub = d["subreddit"]
            return RedditUser(
                name = d["name"].str() ?: "",
                iconUrl = clean(d["icon_img"].str()) ?: clean(sub["icon_img"].str()),
                bannerUrl = clean(sub["banner_img"].str()),
                linkKarma = d["link_karma"].int() ?: 0,
                commentKarma = d["comment_karma"].int() ?: 0,
                createdUtc = (d["created_utc"].long() ?: 0L) * 1000,
                description = (sub["public_description"].str() ?: "").trim(),
            )
        }
    }
}
