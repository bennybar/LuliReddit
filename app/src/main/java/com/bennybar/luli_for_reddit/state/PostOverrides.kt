package com.bennybar.luli_for_reddit.state

import androidx.compose.runtime.Immutable
import com.bennybar.luli_for_reddit.model.Post
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update

/**
 * The current, user-visible state of a post that can change after it's
 * fetched (vote, score, saved, comment count). Shared, keyed by post id, so a
 * feed card and the post-detail screen stay in sync without a refresh.
 */
@Immutable
data class PostOverride(
    val likes: Boolean?, // true=up, false=down, null=no vote
    val score: Int,
    val numComments: Int,
    val saved: Boolean,
)

class PostOverrides : UserScoped {
    private val _state = MutableStateFlow<Map<String, PostOverride>>(emptyMap())
    val state: StateFlow<Map<String, PostOverride>> = _state

    // When the user last voted/saved each post. A fresh server copy wins
    // otherwise, so scores don't freeze at whatever was first seen.
    private val localAt = HashMap<String, Long>()

    /** Effective state for [p] (an override if one exists, else the post's own). */
    fun effective(p: Post): PostOverride =
        _state.value[p.id] ?: PostOverride(p.likes, p.score, p.numComments, p.saved)

    private fun set(id: String, o: PostOverride) = _state.update { it + (id to o) }

    /** Applies a vote (−1, 0, +1). Does nothing if it's already the current vote. */
    fun setVote(p: Post, targetDir: Int) {
        val cur = effective(p)
        val curDir = dirOf(cur.likes)
        if (targetDir == curDir) return
        localAt[p.id] = System.currentTimeMillis()
        set(
            p.id,
            cur.copy(
                score = cur.score + (targetDir - curDir),
                likes = when (targetDir) { 1 -> true; -1 -> false; else -> null },
            ),
        )
    }

    fun setSaved(p: Post, saved: Boolean) {
        localAt[p.id] = System.currentTimeMillis()
        set(p.id, effective(p).copy(saved = saved))
    }

    fun bumpComments(p: Post, delta: Int) {
        val e = effective(p)
        set(p.id, e.copy(numComments = e.numComments + delta))
    }

    /**
     * Refresh from a freshly-fetched post. The server copy wins, except
     * vote/score/saved the user changed in the last couple of minutes (a
     * request may still be in flight, or Reddit's copy may lag).
     */
    fun syncFromServer(p: Post) {
        val existing = _state.value[p.id]
        val at = localAt[p.id]
        val recentLocal = existing != null && at != null && System.currentTimeMillis() - at < 2 * 60_000
        set(
            p.id,
            PostOverride(
                likes = if (recentLocal) existing!!.likes else p.likes,
                score = if (recentLocal) existing!!.score else p.score,
                numComments = p.numComments,
                saved = if (recentLocal) existing!!.saved else p.saved,
            ),
        )
    }

    override fun onUserChanged(username: String) {
        localAt.clear()
        _state.value = emptyMap()
    }

    companion object {
        fun dirOf(likes: Boolean?): Int = when (likes) { true -> 1; false -> -1; null -> 0 }
    }
}
