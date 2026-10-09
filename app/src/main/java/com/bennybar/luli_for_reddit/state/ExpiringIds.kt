package com.bennybar.luli_for_reddit.state

import com.bennybar.luli_for_reddit.core.storage.Prefs
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

/**
 * A per-account set of ids that each expire [ttl] (read each time, so a
 * setting can change it) after being added,
 * persisted as "id:millis" strings under [baseKey]. Local only — nothing is
 * sent to Reddit. Used for posts swiped away ("Dismiss", a day) and
 * subreddits hidden from Home / For You ("Hide r/… for 7 days").
 */
class ExpiringIds(private val prefs: Prefs, private val baseKey: String, private val ttl: () -> Long) : UserScoped {
    private var key = baseKey
    private val since = HashMap<String, Long>()
    private val _ids = MutableStateFlow<Set<String>>(emptySet())
    // Wakes up when the next entry expires, so it un-hides while the app stays open.
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var expiryJob: Job? = null
    val ids: StateFlow<Set<String>> = _ids

    fun add(id: String) {
        since[id] = System.currentTimeMillis()
        save()
    }

    fun remove(id: String) {
        if (since.remove(id) != null) save()
    }

    /** Re-applies the expiry (the time-to-live setting changed). */
    fun refresh() = save()

    private fun save() {
        val now = System.currentTimeMillis()
        val ttlMillis = ttl()
        since.entries.removeAll { now - it.value > ttlMillis }
        prefs.setStringList(key, since.map { "${it.key}:${it.value}" })
        _ids.value = since.keys.toSet()
        expiryJob?.cancel()
        val next = since.values.minOrNull() ?: return
        expiryJob = scope.launch {
            delay((next + ttlMillis - System.currentTimeMillis()).coerceAtLeast(0) + 1_000)
            save()
        }
    }

    override fun onUserChanged(username: String) {
        key = userScopedKey(prefs, username, baseKey)
        since.clear()
        for (row in prefs.getStringList(key).orEmpty()) {
            val i = row.lastIndexOf(':')
            val t = row.substring(i + 1).toLongOrNull() ?: continue
            if (i > 0) since[row.substring(0, i)] = t
        }
        save() // drops the expired ones
    }
}
