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
    /** The community's own colour ("#0079D3"), for its header without a banner (#257). */
    val keyColor: String? = null,
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
                // The banner made for phones first: the desktop one is 4000 px wide and as
                // little as 128 tall, a sliver of it blown up in a phone's header.
                bannerUrl = clean(d["mobile_banner_image"].str()) ?: clean(d["banner_background_image"].str()) ?: clean(d["banner_img"].str()),
                keyColor = clean(d["primary_color"].str()) ?: clean(d["key_color"].str()),
                over18 = d["over18"].isTrue(),
                userHasFavorited = d["user_has_favorited"].isTrue(),
                userIsSubscriber = d["user_is_subscriber"].bool(),
            )
        }
    }
}

/**
 * Each subreddit's icon as the API gives it (lowercased name → URL). A Reddit Home card,
 * read from Reddit's page, takes its icon from here, so it already shows the URL the full
 * post brings a moment later: no letter turning into an icon, no second load.
 */
class SubredditIconMap() {
    private val icons = LinkedHashMap<String, String>() // oldest first

    /** From its stored form: "name\turl" per entry, oldest first. */
    constructor(entries: List<String>) : this() {
        for (e in entries) {
            val tab = e.indexOf('\t')
            if (tab > 0) remember(e.substring(0, tab), e.substring(tab + 1))
        }
    }

    val size get() = icons.size
    val entries: List<String> get() = icons.map { (k, v) -> "$k\t$v" }

    fun icon(subreddit: String): String? = icons[subreddit.lowercase()]

    /**
     * Remembers [url] for [subreddit]; true if anything changed. With `overwrite = false` a
     * known one stays (a post's URL wins over the subscription list's).
     */
    fun remember(subreddit: String, url: String?, overwrite: Boolean = true): Boolean {
        if (url.isNullOrEmpty() || subreddit.isEmpty()) return false
        val key = subreddit.lowercase()
        val old = icons[key]
        if (old != null) {
            if (old == url || !overwrite) return false
            icons.remove(key) // back in as the newest
        }
        icons[key] = url
        if (icons.size > CAP) {
            // Down to 90%: trimmed in steps, not on every new one.
            val drop = icons.size - (CAP - CAP / 10)
            val oldest = icons.keys.iterator()
            repeat(drop) {
                oldest.next()
                oldest.remove()
            }
        }
        return true
    }

    companion object {
        const val CAP = 2000
    }
}

/**
 * The app's [SubredditIconMap], filled from every parsed post and the subscription list,
 * kept across launches (per device).
 */
object SubredditIcons {
    /** "__": a cache, left out of backups. */
    const val PREFS_KEY = "__subredditIcons"

    private var map = SubredditIconMap()
    private var prefs: com.bennybar.luli_for_reddit.core.storage.Prefs? = null
    private var saving = false
    private val saver = java.util.concurrent.Executors.newSingleThreadScheduledExecutor { r ->
        Thread(r, "subreddit-icons").apply { isDaemon = true }
    }

    /** Loads the remembered icons (once, at start); any learnt before then are kept. */
    fun attach(prefs: com.bennybar.luli_for_reddit.core.storage.Prefs) {
        val stored = prefs.getStringList(PREFS_KEY).orEmpty()
        synchronized(this) {
            map = SubredditIconMap(stored + map.entries)
            this.prefs = prefs
        }
    }

    fun icon(subreddit: String): String? = synchronized(this) { map.icon(subreddit) }

    fun remember(subreddit: String, url: String?, overwrite: Boolean = true) {
        val save = synchronized(this) {
            if (!map.remember(subreddit, url, overwrite) || prefs == null || saving) return
            saving = true
            true
        }
        // A few seconds later, once for everything learnt by then.
        if (save) saver.schedule({
            val (p, entries) = synchronized(this) {
                saving = false
                prefs to map.entries
            }
            p?.setStringList(PREFS_KEY, entries)
        }, 3, java.util.concurrent.TimeUnit.SECONDS)
    }
}
