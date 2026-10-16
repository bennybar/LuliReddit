package com.bennybar.luli_for_reddit.state

import androidx.compose.runtime.Immutable
import com.bennybar.luli_for_reddit.core.AppJson
import com.bennybar.luli_for_reddit.core.arr
import com.bennybar.luli_for_reddit.core.get
import com.bennybar.luli_for_reddit.core.storage.Prefs
import com.bennybar.luli_for_reddit.core.str
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/** A search kept to run again: its words, where (null = all of Reddit), sort and time range. */
@Immutable
data class SavedSearch(val query: String, val subreddit: String?, val sort: String, val time: String) {
    val key: String get() = "${subreddit.orEmpty().lowercase()}|${query.lowercase()}|$sort|$time"
}

/** Searches pinned from the search screen, per account (prefs `saved_searches_<user>`). Newest first. */
class SavedSearches(private val prefs: Prefs, private val username: () -> String) {
    private fun prefKey() = userScopedKey(prefs, username(), "saved_searches")

    private val _items = MutableStateFlow<List<SavedSearch>>(emptyList())
    val items: StateFlow<List<SavedSearch>> = _items

    /** Re-reads this account's list (the search screen calls it when it opens). */
    fun refresh() {
        _items.value = runCatching {
            AppJson.parseToJsonElement(prefs.getString(prefKey()) ?: return@runCatching emptyList()).arr().orEmpty().mapNotNull { j ->
                SavedSearch(j["q"].str() ?: return@mapNotNull null, j["sr"].str(), j["sort"].str() ?: "relevance", j["t"].str() ?: "all")
            }
        }.getOrDefault(emptyList())
    }

    fun contains(s: SavedSearch) = _items.value.any { it.key == s.key }

    fun add(s: SavedSearch) = persist(listOf(s) + _items.value.filter { it.key != s.key })

    fun remove(s: SavedSearch) = persist(_items.value.filter { it.key != s.key })

    private fun persist(next: List<SavedSearch>) {
        _items.value = next
        prefs.setString(
            prefKey(),
            JsonArray(next.map { s ->
                buildJsonObject { put("q", s.query); s.subreddit?.let { put("sr", it) }; put("sort", s.sort); put("t", s.time) }
            }).toString(),
        )
    }
}
