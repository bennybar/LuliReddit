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
 * since can be highlighted on the next visit. Local, per-account, bounded,
 * and only recorded while history tracking is on.
 */
class ThreadVisits(private val prefs: Prefs, private val settings: SettingsStore) : UserScoped {
    private var key = BASE
    private var visits = LinkedHashMap<String, Long>()

    override fun onUserChanged(username: String) {
        key = userScopedKey(prefs, username, BASE)
        visits = LinkedHashMap()
        val raw = prefs.getString(key) ?: return
        runCatching {
            AppJson.parseToJsonElement(raw).obj()?.forEach { (k, v) -> v.long()?.let { visits[k] = it } }
        }
    }

    /** The previous visit to [postId] (millis), or null on a first visit. */
    fun lastVisit(postId: String): Long? = visits[postId]

    fun clear() {
        visits = LinkedHashMap()
        prefs.remove(key)
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
        private const val CAP = 300
    }
}
