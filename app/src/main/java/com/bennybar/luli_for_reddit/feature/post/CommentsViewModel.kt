package com.bennybar.luli_for_reddit.feature.post

import androidx.compose.runtime.Immutable
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.data.COMMENT_SORTS
import com.bennybar.luli_for_reddit.model.Comment
import com.bennybar.luli_for_reddit.model.Post
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** A loaded thread: the post, its comment tree and per-view state. */
@Immutable
data class PostThread(
    val post: Post,
    val comments: List<Comment>,
    val collapsed: Set<String> = emptySet(), // collapsed comment ids
    val loadingMore: Set<String> = emptySet(), // "more" node fullnames being fetched
    /** Visible rows, depth-first (recomputed whenever the tree or collapse set changes). */
    val flat: List<Comment> = CommentTree.flatten(comments, collapsed),
)

@Immutable
data class ThreadUiState(
    val thread: PostThread? = null,
    val loading: Boolean = true,
    val refreshing: Boolean = false,
    val error: Throwable? = null,
    val sort: String = "",
)

/**
 * The thread screen's state (the Flutter CommentsController): loads the post +
 * comments (following a suggested sort, falling back to an offline copy),
 * and owns collapse / reply / edit / vote / delete / load-more on the tree.
 */
class CommentsViewModel(
    private val subreddit: String,
    private val postId: String,
    /** Set when viewing a single comment thread. */
    val focusCommentId: String?,
) : ViewModel() {
    private val _state = MutableStateFlow(ThreadUiState())
    val state: StateFlow<ThreadUiState> = _state

    // Empty until the first load seeds it from the user's default comment sort.
    private var sort = ""
    private var sortChosen = false // the user picked a sort for this thread
    private var loadJob: Job? = null

    init {
        load(showLoading = true)
    }

    private suspend fun build(): PostThread {
        // Seed from the user's default comment sort (changeSort overrides it).
        if (sort.isEmpty()) sort = app.settings.value.defaultCommentSort
        val repo = app.repository
        var t = try {
            repo.getComments(subreddit, postId, sort, focusCommentId)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // Saved for offline (Read later)? Show that copy instead of an error.
            val saved = if (focusCommentId == null) app.offline.read(postId) else null
            saved ?: throw e
            val th = withContext(Dispatchers.Default) { repo.parseThread(saved) }
            return PostThread(th.post, th.comments)
        }
        // Threads like AMAs set a suggested sort (Q&A, New). Follow it unless the
        // user picked a sort for this thread; it's only known once fetched.
        val suggested = t.suggestedSort
        if (!sortChosen && suggested != null && suggested != sort && COMMENT_SORTS.any { it.first == suggested }) {
            sort = suggested
            _state.update { it.copy(sort = sort) }
            t = repo.getComments(subreddit, postId, sort, focusCommentId)
        }
        // "Collapse AutoModerator" filter: start its comments collapsed.
        val collapsed = if (app.contentFilters.value.collapseAutoMod) {
            t.comments.filter { it.author == "AutoModerator" }.mapTo(HashSet()) { it.id }
        } else emptySet()
        return withContext(Dispatchers.Default) { PostThread(t.post, t.comments, collapsed) }
    }

    private fun load(showLoading: Boolean) {
        loadJob?.cancel()
        _state.update {
            if (showLoading) it.copy(loading = true, error = null, thread = null, sort = sort)
            else it.copy(refreshing = true, sort = sort)
        }
        loadJob = viewModelScope.launch {
            try {
                val t = build()
                _state.value = ThreadUiState(thread = t, loading = false, sort = sort)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.value = ThreadUiState(thread = null, loading = false, error = e, sort = sort)
            }
        }
    }

    val currentSort: String get() = sort.ifEmpty { app.settings.value.defaultCommentSort }

    fun changeSort(s: String) {
        sort = s
        sortChosen = true
        load(showLoading = true)
    }

    /** Pull-to-refresh: keeps the current thread on screen until the new one is in. */
    fun refresh() = load(showLoading = _state.value.thread == null)

    private inline fun edit(block: (PostThread) -> PostThread) {
        _state.update { s -> s.thread?.let { s.copy(thread = block(it)) } ?: s }
    }

    private fun PostThread.withTree(comments: List<Comment>) =
        copy(comments = comments, flat = CommentTree.flatten(comments, collapsed))

    fun toggleCollapse(commentId: String) = edit { t ->
        val next = if (commentId in t.collapsed) t.collapsed - commentId else t.collapsed + commentId
        t.copy(collapsed = next, flat = CommentTree.flatten(t.comments, next))
    }

    /**
     * Splices a freshly-created reply into the tree under [parentFullname]
     * (the post's fullname → new top-level comment; else under that comment).
     */
    fun insertReply(parentFullname: String, reply: Comment) = edit { t ->
        if (parentFullname == t.post.fullname) t.withTree(listOf(reply) + t.comments)
        else t.withTree(CommentTree.insertReply(t.comments, parentFullname, reply))
    }

    fun applyEdit(fullname: String, newBody: String) = edit { t ->
        if (fullname == t.post.fullname) t.copy(post = t.post.copy(selftext = newBody))
        else t.withTree(CommentTree.update(t.comments, fullname) { it.copy(body = newBody) })
    }

    fun updateComment(fullname: String, change: (Comment) -> Comment) = edit { t ->
        t.withTree(CommentTree.update(t.comments, fullname, change))
    }

    fun removeComment(fullname: String) = edit { t -> t.withTree(CommentTree.remove(t.comments, fullname)) }

    fun loadMore(moreNode: Comment) {
        val s = _state.value.thread ?: return
        if (moreNode.moreChildren.isEmpty() || moreNode.fullname in s.loadingMore) return
        edit { it.copy(loadingMore = it.loadingMore + moreNode.fullname) }
        viewModelScope.launch {
            try {
                val flat = app.repository.getMoreComments(
                    s.post.fullname,
                    moreNode.moreChildren,
                    sort = currentSort, // expanded replies follow the thread's sort
                    depth = moreNode.depth,
                )
                val tree = withContext(Dispatchers.Default) {
                    CommentTree.replaceMore(_state.value.thread?.comments ?: s.comments, moreNode, flat)
                }
                edit { it.withTree(tree).copy(loadingMore = it.loadingMore - moreNode.fullname) }
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                edit { it.copy(loadingMore = it.loadingMore - moreNode.fullname) }
            }
        }
    }
}
