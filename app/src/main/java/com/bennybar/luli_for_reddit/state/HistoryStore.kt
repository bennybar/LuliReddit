package com.bennybar.luli_for_reddit.state

import androidx.compose.runtime.Immutable
import com.bennybar.luli_for_reddit.core.AppJson
import com.bennybar.luli_for_reddit.core.get
import com.bennybar.luli_for_reddit.core.isTrue
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
    // For "Hide NSFW posts"; absent in older entries (unknown: shown).
    val nsfw: Boolean = false,
    // The community's picture (#155); absent in older entries.
    val icon: String? = null,
)

/**
 * Viewed posts, newest first, per account (prefs `history_<user>`, a JSON
 * string list). The History page shows the newest [CAP]; which posts were
 * read is kept much longer in a compact id list (`readIds_<user>`, "id:secs"
 * comma-joined, newest first) so "Hide read posts" and the read dimming don't
 * forget a post after a few days of marking read as you scroll (#148).
 */
class HistoryStore(private val prefs: Prefs) : UserScoped {
    private var key = BASE
    private var readKey = READ_BASE
    // id -> viewed at (seconds), newest first.
    private var read = LinkedHashMap<String, Long>()
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
                    nsfw = j["nsfw"].isTrue(),
                    icon = j["icon"].str(),
                )
            }.getOrNull()
        }
        readKey = userScopedKey(prefs, username, READ_BASE)
        read = LinkedHashMap()
        val stored = prefs.getString(readKey)
        if (stored != null) {
            for (pair in stored.split(',')) {
                val i = pair.indexOf(':')
                if (i > 0) read[pair.substring(0, i)] = pair.substring(i + 1).toLongOrNull() ?: 0
            }
        } else {
            // First run with the long list: start it from history.
            for (e in list) read[e.id] = e.viewedAt / 1000
        }
        publish(list)
    }

    fun contains(id: String): Boolean = id in _ids.value

    fun markViewed(p: Post) {
        val entry = HistoryEntry(p.id, p.subreddit, p.title, p.permalink, System.currentTimeMillis(), p.over18, p.subredditIcon)
        val next = LinkedHashMap<String, Long>(read.size + 1)
        next[p.id] = entry.viewedAt / 1000
        for ((id, t) in read) if (id != p.id && next.size < READ_CAP) next[id] = t
        read = next
        publish((listOf(entry) + _state.value.filter { it.id != p.id }).take(CAP))
        persist()
    }

    fun removeViewed(id: String) {
        read.remove(id)
        publish(_state.value.filter { it.id != id })
        persist()
    }

    /** Undo of [removeViewed] (#154): the entry back in its place, by when it was read. */
    fun restore(e: HistoryEntry) {
        if (e.id in _ids.value) return
        val at = e.viewedAt / 1000
        val next = LinkedHashMap<String, Long>(read.size + 1)
        var placed = false
        for ((id, t) in read) {
            if (!placed && t <= at) { next[e.id] = at; placed = true }
            next[id] = t
        }
        if (!placed) next[e.id] = at
        read = next
        publish((_state.value + e).sortedByDescending { it.viewedAt }.take(CAP))
        persist()
    }

    /** Removes entries older than [ageMillis]; legacy entries (no timestamp) count as old. */
    fun clearOlderThan(ageMillis: Long) {
        val cutoff = System.currentTimeMillis() - ageMillis
        read.entries.removeAll { it.value * 1000 < cutoff }
        publish(_state.value.filter { it.viewedAt >= cutoff })
        persist()
    }

    fun clear() {
        read.clear()
        publish(emptyList())
        persist()
    }

    private fun publish(list: List<HistoryEntry>) {
        _state.value = list
        _ids.value = HashSet(read.keys).apply { list.mapTo(this) { it.id } }
    }

    private fun persist() {
        prefs.setString(readKey, read.entries.joinToString(",") { "${it.key}:${it.value}" })
        prefs.setStringList(
            key,
            _state.value.map { e ->
                buildJsonObject {
                    put("id", e.id); put("sub", e.subreddit); put("title", e.title)
                    put("permalink", e.permalink); put("ts", e.viewedAt)
                    // Only when set: SFW entries keep the shape older versions wrote.
                    if (e.nsfw) put("nsfw", true)
                    if (e.icon != null) put("icon", e.icon)
                }.toString()
            },
        )
    }

    companion object {
        private const val BASE = "history"
        private const val CAP = 500
        private const val READ_BASE = "readIds"
        private const val READ_CAP = 5000
    }
}
