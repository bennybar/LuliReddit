package com.bennybar.luli_for_reddit.state

import androidx.compose.runtime.Immutable
import com.bennybar.luli_for_reddit.model.Comment
import com.bennybar.luli_for_reddit.state.PostOverrides.Companion.dirOf
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update

/**
 * Your recent votes, kept until Reddit's copy shows them. Reddit's copies
 * lag: a fetch soon after voting can still carry the old vote, or the new
 * vote with the score from before it. Trusting it blindly made a vote look
 * un-counted when you went back into a thread.
 */
class LocalVotes {
    private class Pending(val dir: Int, val baseScore: Int, val baseDir: Int, val at: Long)

    private val pending = HashMap<String, Pending>()
    // The last server (score, dir) seen per id: the baseline for the next vote.
    private val seen = HashMap<String, Pair<Int, Int>>()

    /** You voted [dir] on [id]; [serverScore]/[serverLikes] are the copy you voted on. */
    @Synchronized
    fun record(id: String, dir: Int, serverScore: Int, serverLikes: Boolean?) {
        val prev = pending[id]
        val (score, d) = seen[id] ?: (serverScore to dirOf(serverLikes))
        pending[id] = Pending(dir, prev?.baseScore ?: score, prev?.baseDir ?: d, System.currentTimeMillis())
    }

    /** The vote and score to show for a fresh server copy of [id]. */
    @Synchronized
    fun reconcile(id: String, serverLikes: Boolean?, serverScore: Int): Pair<Boolean?, Int> {
        val sDir = dirOf(serverLikes)
        val p = pending[id]
        if (p == null || System.currentTimeMillis() - p.at > WINDOW) {
            pending.remove(id)
            seen[id] = serverScore to sDir
            return serverLikes to serverScore
        }
        val likes = likesOf(p.dir)
        return when {
            // Reddit doesn't have the vote yet: its score is from the old one.
            sDir != p.dir -> likes to serverScore + (p.dir - sDir)
            // The vote is in but the score hasn't moved since you voted.
            serverScore == p.baseScore -> likes to serverScore + (p.dir - p.baseDir)
            // Reddit has caught up.
            else -> {
                pending.remove(id)
                seen[id] = serverScore to sDir
                serverLikes to serverScore
            }
        }
    }

    @Synchronized
    fun isPending(id: String) = id in pending

    @Synchronized
    fun clear() {
        pending.clear()
        seen.clear()
    }

    companion object {
        private const val WINDOW = 15 * 60_000L

        fun likesOf(dir: Int): Boolean? = when (dir) { 1 -> true; -1 -> false; else -> null }
    }
}

/**
 * Your comment votes, keyed by comment id, so a thread you go back into and
 * your profile's comments show them (a thread used to keep them only while open).
 */
class CommentVotes : UserScoped {
    @Immutable
    data class Vote(val likes: Boolean?, val score: Int)

    private val votes = LocalVotes()
    private val _state = MutableStateFlow<Map<String, Vote>>(emptyMap())
    val state: StateFlow<Map<String, Vote>> = _state

    fun effective(c: Comment): Vote = _state.value[c.id] ?: Vote(c.likes, c.score)

    /** Applies a vote (−1, 0, +1) on [c] as shown. */
    fun setVote(c: Comment, target: Int) {
        val cur = effective(c)
        votes.record(c.id, target, c.score, c.likes)
        _state.update { it + (c.id to Vote(LocalVotes.likesOf(target), cur.score + target - dirOf(cur.likes))) }
    }

    /** Fresh comments from Reddit, with the votes it hasn't caught up with yet. */
    fun apply(comments: List<Comment>): List<Comment> =
        if (_state.value.isEmpty()) comments else comments.map(::applyOne)

    private fun applyOne(c: Comment): Comment {
        val withReplies = if (c.replies.isEmpty()) c else c.copy(replies = c.replies.map(::applyOne))
        if (c.isMore || c.id !in _state.value) return withReplies
        val (likes, score) = votes.reconcile(c.id, c.likes, c.score)
        if (!votes.isPending(c.id)) _state.update { it - c.id }
        return withReplies.copy(likes = likes, score = score)
    }

    override fun onUserChanged(username: String) {
        votes.clear()
        _state.value = emptyMap()
    }
}
