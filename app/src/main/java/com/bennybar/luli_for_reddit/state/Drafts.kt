package com.bennybar.luli_for_reddit.state

import com.bennybar.luli_for_reddit.core.storage.Prefs

/**
 * Persists in-progress composer text so a long reply/post/message survives
 * navigating away, backgrounding or a crash. Keyed by the compose target
 * (e.g. the parent fullname). Cleared on a successful submit. Local only.
 */
class Drafts(private val prefs: Prefs) {
    private fun k(key: String) = "draft_$key"
    fun get(key: String): String? = prefs.getString(k(key))
    fun save(key: String, value: String) = if (value.isBlank()) clear(key) else prefs.setString(k(key), value)
    fun clear(key: String) = prefs.remove(k(key))
}
