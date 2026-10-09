package com.bennybar.luli_for_reddit.state

import com.bennybar.luli_for_reddit.core.storage.Prefs
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * Posts swiped away (the "Dismiss" swipe action) from Home / For You. Local
 * only — unlike Hide, nothing is sent to Reddit — and each one expires after
 * a day, so the list stays small and a post can come back tomorrow.
 * Persisted per account as "id:millis" strings.
 */
class DismissedPosts(private val prefs: Prefs) : UserScoped {
    private var key = "dismissedPosts"
    private val since = HashMap<String, Long>()
    private val _ids = MutableStateFlow<Set<String>>(emptySet())
    val ids: StateFlow<Set<String>> = _ids

    fun add(id: String) {
        since[id] = System.currentTimeMillis()
        save()
    }

    fun remove(id: String) {
        if (since.remove(id) != null) save()
    }

    private fun save() {
        val now = System.currentTimeMillis()
        since.entries.removeAll { now - it.value > TTL }
        prefs.setStringList(key, since.map { "${it.key}:${it.value}" })
        _ids.value = since.keys.toSet()
    }

    override fun onUserChanged(username: String) {
        key = userScopedKey(prefs, username, "dismissedPosts")
        since.clear()
        for (row in prefs.getStringList(key).orEmpty()) {
            val i = row.lastIndexOf(':')
            val t = row.substring(i + 1).toLongOrNull() ?: continue
            if (i > 0) since[row.substring(0, i)] = t
        }
        save() // drops the expired ones
    }

    private companion object {
        const val TTL = 24 * 60 * 60_000L
    }
}
