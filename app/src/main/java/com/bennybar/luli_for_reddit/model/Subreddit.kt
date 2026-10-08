package com.bennybar.luli_for_reddit.model

import androidx.compose.runtime.Immutable
import com.bennybar.luli_for_reddit.core.bool
import com.bennybar.luli_for_reddit.core.get
import com.bennybar.luli_for_reddit.core.int
import com.bennybar.luli_for_reddit.core.isTrue
import com.bennybar.luli_for_reddit.core.str
import kotlinx.serialization.json.JsonElement

@Immutable
data class Subreddit(
    val name: String, // display_name
    val namePrefixed: String, // r/name
    val title: String,
    val description: String,
    val subscribers: Int,
    val iconUrl: String? = null,
    val bannerUrl: String? = null,
    val over18: Boolean = false,
    val userHasFavorited: Boolean = false,
    val userIsSubscriber: Boolean? = null,
) {
    companion object {
        fun fromData(d: JsonElement): Subreddit {
            fun clean(s: String?) = if (s.isNullOrEmpty()) null else s.replace("&amp;", "&")
            val name = d["display_name"].str() ?: ""
            return Subreddit(
                name = name,
                namePrefixed = d["display_name_prefixed"].str() ?: "r/$name",
                title = (d["title"].str() ?: "").trim(),
                description = (d["public_description"].str() ?: "").trim(),
                subscribers = d["subscribers"].int() ?: 0,
                iconUrl = clean(d["community_icon"].str()) ?: clean(d["icon_img"].str()),
                bannerUrl = clean(d["banner_background_image"].str()) ?: clean(d["banner_img"].str()),
                over18 = d["over18"].isTrue(),
                userHasFavorited = d["user_has_favorited"].isTrue(),
                userIsSubscriber = d["user_is_subscriber"].bool(),
            )
        }
    }
}
