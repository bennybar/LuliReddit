package com.bennybar.luli_for_reddit.state

import androidx.compose.runtime.Immutable
import com.bennybar.luli_for_reddit.core.AppJson
import com.bennybar.luli_for_reddit.core.storage.Prefs
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * An unfinished reply / message / post: its composer [key] ("reply_t1_…",
 * "msgreply_t4_…", "compose_msg", "compose_post"), its [text] (JSON for the
 * message and post composers) and [info]: where it goes, for the Drafts list.
 */
@Immutable
data class Draft(val key: String, val text: String, val info: JsonElement?, val savedAt: Long)

/**
 * Persists in-progress composer text so a long reply/post/message survives
 * navigating away, backgrounding or a crash. Keyed by the signed-in account and
 * the compose target (e.g. the parent fullname), so another account never sees
 * or sends it; a draft from before accounts were part of the key moves to the
 * first account that opens it. Cleared on a successful submit. Local only.
 *
 * Next to each draft, [save]'s `info` says where it goes (post title,
 * subreddit, recipient) so You → Drafts can list and reopen it.
 */
class Drafts(private val prefs: Prefs, private val username: () -> String) {
    private fun k(key: String) = userScopedKey(prefs, username(), "draft_$key")
    private fun infoKey(key: String) = userScopedKey(prefs, username(), "draftinfo_$key")

    /** Bumped on every save / clear, so the Drafts list refreshes. */
    private val _changes = MutableStateFlow(0)
    val changes: StateFlow<Int> = _changes

    fun get(key: String): String? = prefs.getString(k(key))

    fun save(key: String, value: String, info: JsonObject? = null) {
        if (value.isBlank()) return clear(key)
        prefs.setString(k(key), value)
        val stamped = buildJsonObject {
            info?.forEach { (name, v) -> put(name, v) }
            put("at", System.currentTimeMillis())
        }
        prefs.setString(infoKey(key), stamped.toString())
        _changes.value++
    }

    fun clear(key: String) {
        prefs.remove(k(key))
        prefs.remove(infoKey(key))
        _changes.value++
    }

    /** This account's drafts, newest first. */
    fun list(): List<Draft> {
        val user = username().ifEmpty { return emptyList() }
        val suffix = "_" + user.lowercase()
        return prefs.keys()
            .filter { it.startsWith("draft_") && it.endsWith(suffix) }
            .mapNotNull { full ->
                val key = full.removePrefix("draft_").removeSuffix(suffix)
                if (key.isEmpty()) return@mapNotNull null
                val text = prefs.getString(full)?.takeIf { it.isNotBlank() } ?: return@mapNotNull null
                val info = prefs.getString("draftinfo_$key$suffix")?.let { runCatching { AppJson.parseToJsonElement(it) }.getOrNull() }
                val at = (info as? JsonObject)?.get("at")?.toString()?.toLongOrNull() ?: 0L
                Draft(key, text, info, at)
            }
            .sortedByDescending { it.savedAt }
    }
}
