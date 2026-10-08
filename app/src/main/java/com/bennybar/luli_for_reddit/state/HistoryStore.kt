package com.bennybar.luli_for_reddit.state

import androidx.compose.runtime.Immutable
import com.bennybar.luli_for_reddit.core.AppJson
import com.bennybar.luli_for_reddit.core.get
import com.bennybar.luli_for_reddit.core.long
import com.bennybar.luli_for_reddit.core.storage.Prefs
import com.bennybar.luli_for_reddit.core.str
import com.bennybar.luli_for_reddit.model.Post
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/** A locally-stored record of a viewed post. History is on-device only. */
@Immutable
data class HistoryEntry(
    val id: String,
    val subreddit: String,
    val title: String,
    val permalink: String,
    val viewedAt: Long = 0, // millis since epoch; 0 = legacy/unknown
)

/** Viewed posts, newest first, per account (prefs `history_<user>`, a JSON string list). */
class HistoryStore(private val prefs: Prefs) : UserScoped {
    private var key = BASE
    private val _state = MutableStateFlow<List<HistoryEntry>>(emptyList())
    val state: StateFlow<List<HistoryEntry>> = _state

    /** Ids for O(1) "seen?" checks (feeds dim read posts). */
    private val _ids = MutableStateFlow<Set<String>>(emptySet())
    val ids: StateFlow<Set<String>> = _ids

    override fun onUserChanged(username: String) {
        key = userScopedKey(prefs, username, BASE)
        val list = (prefs.getStringList(key) ?: emptyList()).mapNotNull { s ->
            runCatching {
                val j = AppJson.parseToJsonElement(s)
                HistoryEntry(
                    id = j["id"].str() ?: "",
                    subreddit = j["sub"].str() ?: "",
                    title = j["title"].str() ?: "",
                    permalink = j["permalink"].str() ?: "",
                    viewedAt = j["ts"].long() ?: 0,
                )
            }.getOrNull()
        }
        publish(list)
    }

    fun contains(id: String): Boolean = id in _ids.value

    fun markViewed(p: Post) {
        val entry = HistoryEntry(p.id, p.subreddit, p.title, p.permalink, System.currentTimeMillis())
        publish((listOf(entry) + _state.value.filter { it.id != p.id }).take(CAP))
        persist()
    }

    fun removeViewed(id: String) {
        publish(_state.value.filter { it.id != id })
        persist()
    }

    /** Removes entries older than [ageMillis]; legacy entries (no timestamp) count as old. */
    fun clearOlderThan(ageMillis: Long) {
        val cutoff = System.currentTimeMillis() - ageMillis
        publish(_state.value.filter { it.viewedAt >= cutoff })
        persist()
    }

    fun clear() {
        publish(emptyList())
        persist()
    }

    private fun publish(list: List<HistoryEntry>) {
        _state.value = list
        _ids.value = list.mapTo(HashSet()) { it.id }
    }

    private fun persist() {
        prefs.setStringList(
            key,
            _state.value.map { e ->
                buildJsonObject {
                    put("id", e.id); put("sub", e.subreddit); put("title", e.title)
                    put("permalink", e.permalink); put("ts", e.viewedAt)
                }.toString()
            },
        )
    }

    companion object {
        private const val BASE = "history"
        private const val CAP = 500
    }
}
