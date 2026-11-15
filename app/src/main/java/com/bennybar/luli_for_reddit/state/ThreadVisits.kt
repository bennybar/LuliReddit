package com.bennybar.luli_for_reddit.state

import com.bennybar.luli_for_reddit.core.AppJson
import com.bennybar.luli_for_reddit.core.long
import com.bennybar.luli_for_reddit.core.obj
import com.bennybar.luli_for_reddit.core.storage.Prefs
import com.bennybar.luli_for_reddit.settings.SettingsStore
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * When each thread was last opened (post id → millis), so comments posted
 * since can be highlighted on the next visit, and where you were in it (#179),
 * so it reopens there. Local, per-account, bounded, and only recorded while
 * history tracking is on.
 */
class ThreadVisits(private val prefs: Prefs, private val settings: SettingsStore) : UserScoped {
    private var key = BASE
    private var visits = LinkedHashMap<String, Long>()
    private var posKey = BASE_POS
    /** Post id → "<comment fullname> <offset px>": the comment at the top of the screen when you left. */
    private var positions = LinkedHashMap<String, String>()

    override fun onUserChanged(username: String) {
        key = userScopedKey(prefs, username, BASE)
        posKey = userScopedKey(prefs, username, BASE_POS)
        visits = LinkedHashMap()
        positions = LinkedHashMap()
        prefs.getString(key)?.let { raw ->
            runCatching {
                AppJson.parseToJsonElement(raw).obj()?.forEach { (k, v) -> v.long()?.let { visits[k] = it } }
            }
        }
        prefs.getString(posKey)?.let { raw ->
            runCatching {
                AppJson.parseToJsonElement(raw).obj()?.forEach { (k, v) -> (v as? JsonPrimitive)?.content?.let { positions[k] = it } }
            }
        }
    }

    /** Where you left [postId]: the comment then at the top of the screen and how far it was scrolled past. */
    fun lastPosition(postId: String): Pair<String, Int>? {
        val (fullname, offset) = positions[postId]?.split(' ')?.takeIf { it.size == 2 } ?: return null
        return fullname to (offset.toIntOrNull() ?: 0)
    }

    /** Where you're leaving [postId]; a null [fullname] (at the top) forgets it, so it opens at the top. */
    fun recordPosition(postId: String, fullname: String?, offset: Int) {
        if (!settings.value.trackHistory) return
        if (fullname == null) {
            if (positions.remove(postId) == null) return
        } else {
            positions.remove(postId)
            positions[postId] = "$fullname $offset" // newest last
            while (positions.size > CAP) positions.remove(positions.keys.first())
        }
        prefs.setString(posKey, JsonObject(positions.mapValues { JsonPrimitive(it.value) }).toString())
    }

    /** The previous visit to [postId] (millis), or null on a first visit. */
    fun lastVisit(postId: String): Long? = visits[postId]

    fun clear() {
        visits = LinkedHashMap()
        positions = LinkedHashMap()
        prefs.remove(key)
        prefs.remove(posKey)
    }

    fun record(postId: String) {
        if (!settings.value.trackHistory) return
        visits.remove(postId)
        visits[postId] = System.currentTimeMillis() // newest last
        while (visits.size > CAP) visits.remove(visits.keys.first())
        prefs.setString(key, JsonObject(visits.mapValues { JsonPrimitive(it.value) }).toString())
    }

    companion object {
        private const val BASE = "thread_visits"
        private const val BASE_POS = "thread_positions"
        private const val CAP = 300
    }
}
