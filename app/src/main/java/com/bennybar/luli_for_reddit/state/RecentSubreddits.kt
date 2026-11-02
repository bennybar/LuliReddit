package com.bennybar.luli_for_reddit.state

import androidx.compose.runtime.Immutable
import com.bennybar.luli_for_reddit.core.AppJson
import com.bennybar.luli_for_reddit.core.get
import com.bennybar.luli_for_reddit.core.int
import com.bennybar.luli_for_reddit.core.long
import com.bennybar.luli_for_reddit.core.storage.Prefs
import com.bennybar.luli_for_reddit.core.str
import com.bennybar.luli_for_reddit.model.Subreddit
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/** A subreddit you opened, with what it takes to list it again without asking Reddit. */
@Immutable
data class RecentSubreddit(
    val name: String,
    val namePrefixed: String,
    val iconUrl: String?,
    val subscribers: Int,
    val visitedAt: Long,
) {
    fun asSubreddit() = Subreddit(name, namePrefixed, "", "", subscribers, iconUrl)
}

/**
 * The subreddits you opened last, newest first, per account and on-device only
 * (prefs `recent_subreddits_<user>`, a JSON string list). Whether you're
 * subscribed doesn't matter (#63).
 */
class RecentSubreddits(private val prefs: Prefs) : UserScoped {
    private var key = BASE
    private val _state = MutableStateFlow<List<RecentSubreddit>>(emptyList())
    val state: StateFlow<List<RecentSubreddit>> = _state

    override fun onUserChanged(username: String) {
        key = userScopedKey(prefs, username, BASE)
        _state.value = (prefs.getStringList(key) ?: emptyList()).mapNotNull { s ->
            runCatching {
                val j = AppJson.parseToJsonElement(s)
                RecentSubreddit(
                    name = j["name"].str() ?: return@mapNotNull null,
                    namePrefixed = j["prefixed"].str() ?: return@mapNotNull null,
                    iconUrl = j["icon"].str(),
                    subscribers = j["members"].int() ?: 0,
                    visitedAt = j["ts"].long() ?: 0,
                )
            }.getOrNull()
        }
    }

    fun visit(s: Subreddit) {
        val entry = RecentSubreddit(s.name, s.namePrefixed, s.iconUrl, s.subscribers, System.currentTimeMillis())
        publish(visited(_state.value, entry))
    }

    /** Removes entries older than [ageMillis], with History's own clear options. */
    fun clearOlderThan(ageMillis: Long) {
        val cutoff = System.currentTimeMillis() - ageMillis
        publish(_state.value.filter { it.visitedAt >= cutoff })
    }

    fun clear() = publish(emptyList())

    private fun publish(list: List<RecentSubreddit>) {
        _state.value = list
        prefs.setStringList(
            key,
            list.map { e ->
                buildJsonObject {
                    put("name", e.name); put("prefixed", e.namePrefixed); put("icon", e.iconUrl)
                    put("members", e.subscribers); put("ts", e.visitedAt)
                }.toString()
            },
        )
    }

    companion object {
        private const val BASE = "recent_subreddits"
        private const val CAP = 5

        /** [list] with [entry] first, once, whatever case its name came in. */
        fun visited(list: List<RecentSubreddit>, entry: RecentSubreddit): List<RecentSubreddit> =
            (listOf(entry) + list.filter { !it.name.equals(entry.name, ignoreCase = true) }).take(CAP)
    }
}
