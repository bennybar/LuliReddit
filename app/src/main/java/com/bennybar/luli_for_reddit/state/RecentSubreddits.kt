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
    val visits: Int = 1, // times opened, for the count and the "Most visited" order (#92)
) {
    fun asSubreddit() = Subreddit(name, namePrefixed, "", "", subscribers, iconUrl)
}

/**
 * The subreddits you opened last, newest first, per account and on-device only
 * (prefs `recent_subreddits_<user>`, a JSON string list, each with its visit
 * count). Whether you're subscribed doesn't matter (#63).
 *
 * More are remembered than listed, so with [byVisits] ("Most visited", #92) a
 * subreddit you open often keeps its count and its place while others come and go.
 */
class RecentSubreddits(private val prefs: Prefs, private val byVisits: () -> Boolean) : UserScoped {
    private var key = BASE
    private var all = emptyList<RecentSubreddit>()
    private val _state = MutableStateFlow<List<RecentSubreddit>>(emptyList())
    /** The ones to list, in the order Settings picked. */
    val state: StateFlow<List<RecentSubreddit>> = _state

    override fun onUserChanged(username: String) {
        key = userScopedKey(prefs, username, BASE)
        all = (prefs.getStringList(key) ?: emptyList()).mapNotNull { s ->
            runCatching {
                val j = AppJson.parseToJsonElement(s)
                RecentSubreddit(
                    name = j["name"].str() ?: return@mapNotNull null,
                    namePrefixed = j["prefixed"].str() ?: return@mapNotNull null,
                    iconUrl = j["icon"].str(),
                    subscribers = j["members"].int() ?: 0,
                    visitedAt = j["ts"].long() ?: 0,
                    // Saved before visits were counted: once.
                    visits = j["visits"].int() ?: 1,
                )
            }.getOrNull()
        }
        refresh()
    }

    /** Re-applies the order after Settings changed it. */
    fun refresh() {
        _state.value = shown(all, byVisits())
    }

    fun visit(s: Subreddit) {
        val entry = RecentSubreddit(s.name, s.namePrefixed, s.iconUrl, s.subscribers, System.currentTimeMillis())
        publish(visited(all, entry))
    }

    /** Removes entries older than [ageMillis], with History's own clear options. */
    fun clearOlderThan(ageMillis: Long) {
        val cutoff = System.currentTimeMillis() - ageMillis
        publish(all.filter { it.visitedAt >= cutoff })
    }

    fun clear() = publish(emptyList())

    /** Drops one subreddit from the list (#123). */
    fun remove(name: String) = publish(all.filter { !it.name.equals(name, ignoreCase = true) })

    private fun publish(list: List<RecentSubreddit>) {
        all = list
        refresh()
        prefs.setStringList(
            key,
            list.map { e ->
                buildJsonObject {
                    put("name", e.name); put("prefixed", e.namePrefixed); put("icon", e.iconUrl)
                    put("members", e.subscribers); put("ts", e.visitedAt); put("visits", e.visits)
                }.toString()
            },
        )
    }

    companion object {
        private const val BASE = "recent_subreddits"
        private const val CAP = 5 // listed
        private const val KEEP = 100 // remembered, with their counts

        /** [list] with [entry] first, once, whatever case its name came in, its visits counted. */
        fun visited(list: List<RecentSubreddit>, entry: RecentSubreddit): List<RecentSubreddit> {
            val before = list.firstOrNull { it.name.equals(entry.name, ignoreCase = true) }?.visits ?: 0
            return (listOf(entry.copy(visits = before + 1)) + list.filter { !it.name.equals(entry.name, ignoreCase = true) }).take(KEEP)
        }

        /** The [CAP] to list: newest first, or most visited first (ties: newest first). */
        fun shown(list: List<RecentSubreddit>, byVisits: Boolean): List<RecentSubreddit> =
            (if (byVisits) list.sortedByDescending { it.visits } else list).take(CAP)
    }
}
