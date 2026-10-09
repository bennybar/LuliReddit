package com.bennybar.luli_for_reddit.state

import androidx.compose.runtime.Immutable
import com.bennybar.luli_for_reddit.core.AppJson
import com.bennybar.luli_for_reddit.core.arr
import com.bennybar.luli_for_reddit.core.get
import com.bennybar.luli_for_reddit.core.isTrue
import com.bennybar.luli_for_reddit.core.storage.Prefs
import com.bennybar.luli_for_reddit.model.Post
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.jsonPrimitive

/**
 * User content filters: hide posts whose title contains a keyword, whose
 * domain or flair matches, or from a filtered subreddit; optionally hide all
 * NSFW posts and collapse AutoModerator comments. Local, per-account,
 * applied across every feed.
 */
@Immutable
data class ContentFilters(
    val keywords: List<String> = emptyList(),
    val domains: List<String> = emptyList(),
    val flairs: List<String> = emptyList(),
    val subreddits: List<String> = emptyList(), // lowercase names, without "r/"
    val hideNsfw: Boolean = false,
    val collapseAutoMod: Boolean = false,
) {
    val isEmpty: Boolean
        get() = keywords.isEmpty() && domains.isEmpty() && flairs.isEmpty() && subreddits.isEmpty() && !hideNsfw

    /**
     * Whether [p] is hidden. A filtered subreddit still shows on its own page
     * ([viewingSubreddit]) — the filter keeps it out of everything else.
     */
    fun hides(p: Post, viewingSubreddit: String? = null): Boolean {
        if (hideNsfw && p.over18) return true
        val sub = p.subreddit.lowercase()
        if (sub in subreddits && viewingSubreddit?.lowercase() != sub) return true
        if (keywordRegex?.containsMatchIn(p.title) == true) return true
        val domain = p.domain.lowercase()
        if (domains.any { it.isNotEmpty() && domain.contains(it) }) return true
        val flair = (p.linkFlairText ?: "").lowercase()
        if (flair.isNotEmpty() && flairs.any { it.isNotEmpty() && flair.contains(it) }) return true
        return false
    }

    /**
     * All keywords as one whole-word, any-script pattern ("cat" doesn't hide
     * "vacation"), compiled once per filter set — it used to be compiled per
     * keyword per post, each time a feed list was recomputed.
     */
    private val keywordRegex: Regex? by lazy {
        val words = keywords.filter { it.isNotEmpty() }
        if (words.isEmpty()) null
        else Regex(
            "(?<![\\p{L}\\p{N}])(?:${words.joinToString("|") { Regex.escape(it) }})(?![\\p{L}\\p{N}])",
            RegexOption.IGNORE_CASE, // Kotlin adds UNICODE_CASE itself
        )
    }
}

class ContentFiltersStore(private val prefs: Prefs) : UserScoped {
    private var key = BASE
    private val _state = MutableStateFlow(ContentFilters())
    val state: StateFlow<ContentFilters> = _state
    val value: ContentFilters get() = _state.value

    override fun onUserChanged(username: String) {
        key = userScopedKey(prefs, username, BASE)
        val raw = prefs.getString(key)
        _state.value = if (raw == null) ContentFilters() else runCatching {
            val m = AppJson.parseToJsonElement(raw)
            fun g(k: String) = m[k].arr()?.map { it.jsonPrimitive.content } ?: emptyList()
            ContentFilters(g("keywords"), g("domains"), g("flairs"), g("subreddits"), m["hideNsfw"].isTrue(), m["collapseAutoMod"].isTrue())
        }.getOrDefault(ContentFilters())
    }

    private fun set(next: ContentFilters) {
        _state.value = next
        fun arr(l: List<String>) = JsonArray(l.map { JsonPrimitive(it) })
        prefs.setString(
            key,
            buildJsonObject {
                put("keywords", arr(next.keywords)); put("domains", arr(next.domains))
                put("flairs", arr(next.flairs)); put("subreddits", arr(next.subreddits))
                put("hideNsfw", next.hideNsfw); put("collapseAutoMod", next.collapseAutoMod)
            }.toString(),
        )
    }

    /** [type] ∈ keyword | domain | subreddit | flair. */
    private fun list(type: String) = when (type) {
        "keyword" -> value.keywords
        "domain" -> value.domains
        "subreddit" -> value.subreddits
        else -> value.flairs
    }

    private fun withList(type: String, v: List<String>) = when (type) {
        "keyword" -> value.copy(keywords = v)
        "domain" -> value.copy(domains = v)
        "subreddit" -> value.copy(subreddits = v)
        else -> value.copy(flairs = v)
    }

    fun add(type: String, raw: String) {
        var v = raw.trim().lowercase()
        if (type == "subreddit") v = v.replaceFirst(Regex("^/?r/"), "")
        if (v.isEmpty() || v in list(type)) return
        set(withList(type, list(type) + v))
    }

    fun remove(type: String, v: String) = set(withList(type, list(type) - v))
    fun setHideNsfw(v: Boolean) = set(value.copy(hideNsfw = v))
    fun setCollapseAutoMod(v: Boolean) = set(value.copy(collapseAutoMod = v))

    companion object {
        private const val BASE = "content_filters"
    }
}
