package com.bennybar.luli_for_reddit.state

import com.bennybar.luli_for_reddit.core.storage.Prefs

/**
 * Persists in-progress composer text so a long reply/post/message survives
 * navigating away, backgrounding or a crash. Keyed by the signed-in account and
 * the compose target (e.g. the parent fullname), so another account never sees
 * or sends it; a draft from before accounts were part of the key moves to the
 * first account that opens it. Cleared on a successful submit. Local only.
 */
class Drafts(private val prefs: Prefs, private val username: () -> String) {
    private fun k(key: String) = userScopedKey(prefs, username(), "draft_$key")
    fun get(key: String): String? = prefs.getString(k(key))
    fun save(key: String, value: String) = if (value.isBlank()) clear(key) else prefs.setString(k(key), value)
    fun clear(key: String) = prefs.remove(k(key))
}
