package com.bennybar.luli_for_reddit.feature.post

import com.bennybar.luli_for_reddit.ui.friendlyError
import androidx.compose.runtime.Immutable
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.core.Translate
import com.bennybar.luli_for_reddit.data.COMMENT_SORTS
import com.bennybar.luli_for_reddit.model.Comment
import com.bennybar.luli_for_reddit.model.Post
import com.bennybar.luli_for_reddit.nav.NavCache
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
    /** The languages Translate offers for this thread (the phone's and the second one, minus the thread's). */
    val translateTargets: List<String> = emptyList(),
    /** Shown translated into [translatedTo]: post ("title", "body") and comment (fullname) texts. Null: the original. */
    val translation: Map<String, String>? = null,
    val translatedTo: String? = null,
    val translating: Boolean = false,
)

/** [this] with [texts] (ThreadUiState.translation) in place of the original post and comment texts. */
fun PostThread.translated(texts: Map<String, String>?): PostThread {
    if (texts == null) return this
    fun tr(c: Comment): Comment =
        if (c.isMore) c else c.copy(body = texts[c.fullname] ?: c.body, replies = c.replies.map(::tr))
    val comments = comments.map(::tr)
    return copy(
        post = post.copy(title = texts["title"] ?: post.title, selftext = texts["body"] ?: post.selftext),
        comments = comments,
        flat = CommentTree.flatten(comments, collapsed),
    )
}

/**
 * Comments in the first request. Reddit answers 30 in about half the time of
 * 100 (~0.5s vs ~1s, a third of the bytes), so the thread paints with these
 * and the full [FULL_PAGE] follows in the background.
 */
private const val FIRST_PAGE = 30
private const val FULL_PAGE = 100

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
    // The tree changed locally (vote, reply, edit, load more…) since the first
    // page: the full page then must not replace it.
    private var touched = false
    // The thread's language and every text translated so far, per target
    // language, kept while the original is shown.
    private var language: String? = null
    private val translations = HashMap<String, HashMap<String, String>>()

    init {
        load(showLoading = true)
    }

    /** The first load, and whether the full page should follow (not for an offline copy or a focused thread). */
    private suspend fun build(): Pair<PostThread, Boolean> {
        // Seed from the user's default comment sort (changeSort overrides it).
        if (sort.isEmpty()) {
            sort = app.settings.value.defaultCommentSort
            // The feed's post knows the mods' suggested sort (AMAs: Q&A):
            // start with it rather than fetching twice.
            val suggested = NavCache.get<Post>(postId)?.suggestedSort
            if (!sortChosen && suggested != null && COMMENT_SORTS.any { it.first == suggested }) sort = suggested
        }
        val repo = app.repository
        // A focused (single-comment) thread is small: one full request.
        val paged = focusCommentId == null
        val limit = if (paged) FIRST_PAGE else FULL_PAGE
        var t = try {
            repo.getComments(subreddit, postId, sort, focusCommentId, limit)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // Saved for offline (Read later)? Show that copy instead of an error.
            val saved = if (focusCommentId == null) app.offline.read(postId) else null
            saved ?: throw e
            val th = withContext(Dispatchers.Default) { repo.parseThread(saved) }
            return PostThread(th.post, app.commentVotes.apply(th.comments)) to false
        }
        // Threads like AMAs set a suggested sort (Q&A, New). Follow it unless the
        // user picked a sort for this thread; it's only known once fetched.
        val suggested = t.suggestedSort
        if (!sortChosen && suggested != null && suggested != sort && COMMENT_SORTS.any { it.first == suggested }) {
            sort = suggested
            _state.update { it.copy(sort = sort) }
            t = repo.getComments(subreddit, postId, sort, focusCommentId, limit)
        }
        val collapsed = startCollapsed(t.comments)
        // Fetch the full page only when the first one was cut short (it ends in
        // "load more" rows); a small thread is already complete.
        return withContext(Dispatchers.Default) {
            val thread = PostThread(t.post, app.commentVotes.apply(t.comments), collapsed)
            thread to (paged && CommentTree.flatten(t.comments, emptySet()).any { it.isMore })
        }
    }

    /**
     * Swaps in the full page under the first one. Same sort, so the comments
     * already on screen keep their place (rows are keyed by id) and the rest
     * appear below; collapse state carries over. Skipped once the user has
     * changed the tree, or if the request fails (the first page's "more"
     * rows still load the rest).
     */
    private suspend fun loadFullPage() {
        val full = try {
            app.repository.getComments(subreddit, postId, sort, null, FULL_PAGE)
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            return
        }
        val cur = _state.value.thread ?: return
        if (touched) return
        // New comments start collapsed by the same rules as on first load.
        val autoMod = withContext(Dispatchers.Default) {
            val known = CommentTree.flatten(cur.comments, emptySet()).mapTo(HashSet()) { it.id }
            startCollapsed(full.comments, skip = known)
        }
        if (touched) return
        // Collapse state from the latest thread: a toggle made while the full
        // page was being prepared must survive the swap.
        _state.update { s ->
            val latest = s.thread ?: return@update s
            s.copy(thread = PostThread(full.post, app.commentVotes.apply(full.comments), latest.collapsed + autoMod))
        }
    }

    private fun load(showLoading: Boolean) {
        loadJob?.cancel()
        _state.update {
            if (showLoading) it.copy(loading = true, error = null, thread = null, sort = sort)
            else it.copy(refreshing = true, sort = sort)
        }
        loadJob = viewModelScope.launch {
            try {
                touched = false
                val (t, more) = build()
                val shown = _state.value
                _state.value = ThreadUiState(
                    thread = t, loading = false, sort = sort,
                    translateTargets = shown.translateTargets, translation = shown.translation, translatedTo = shown.translatedTo,
                )
                if (language == null) detectLanguage(t) else shown.translatedTo?.let(::translate)
                if (more) {
                    loadFullPage()
                    _state.value.translatedTo?.let(::translate)
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                val shown = _state.value.thread
                if (!showLoading && shown != null) {
                    // A failed refresh keeps the thread (and its collapsed
                    // comments) readable; the error screen is for nothing loaded.
                    _state.update { it.copy(refreshing = false) }
                    app.navigatorOrNull?.showSnackbar("Couldn't refresh: ${friendlyError(e)}", actionLabel = "Retry", onAction = ::refresh)
                } else {
                    _state.value = ThreadUiState(thread = null, loading = false, error = e, sort = sort)
                }
            }
        }
    }

    /**
     * Offers Translate into the phone's language and the second one (Settings
     * → Translation), less the thread's own. With Settings → Auto-translate, a
     * thread in neither opens translated into the phone's.
     */
    private suspend fun detectLanguage(t: PostThread) {
        val ctx = app.context
        // The post and its first comments: a title alone is too short to be sure.
        val sample = (listOf(t.post.title, t.post.selftext) + t.comments.filter { !it.isMore }.take(5).map { it.body })
        val lang = Translate.detect(ctx, sample.joinToString("\n")) ?: return
        val targets = Translate.targets(ctx, lang)
        if (targets.isEmpty()) return
        language = lang
        _state.update { it.copy(translateTargets = targets) }
        val s = app.settings.value
        if (s.autoTranslate && lang != s.translateSecondLanguage && Translate.primary in targets) translate(Translate.primary)
    }

    /** Shows the thread in [to], or the original when null. */
    fun translateTo(to: String?) {
        if (to == null) _state.update { it.copy(translation = null, translatedTo = null) } else translate(to)
    }

    /** Shows the thread translated into [to], translating what isn't yet (the post, comments loaded since). */
    private fun translate(to: String) {
        val from = language ?: return
        val t = _state.value.thread ?: return
        val translations = translations.getOrPut(to) { HashMap() }
        val missing = buildMap {
            if ("title" !in translations) put("title", t.post.title)
            if ("body" !in translations && t.post.selftext.isNotEmpty()) put("body", t.post.selftext)
            for (c in CommentTree.flatten(t.comments, emptySet())) {
                if (!c.isMore && c.fullname !in translations && c.body.isNotEmpty()) put(c.fullname, c.body)
            }
        }
        if (missing.isEmpty()) {
            _state.update { it.copy(translation = HashMap(translations), translatedTo = to) }
            return
        }
        _state.update { it.copy(translating = true) }
        viewModelScope.launch {
            val out = try {
                Translate.translate(app.context, missing.values.toList(), from, to)
            } catch (e: Exception) {
                _state.update { it.copy(translating = false) }
                app.navigatorOrNull?.showSnackbar("Couldn't translate: ${e.message}")
                return@launch
            }
            if (out == null) {
                _state.update { it.copy(translating = false) }
                val ctx = app.context
                val settings = Translate.downloadSettings(ctx)
                if (Translate.needsDownload(ctx, from, to)) {
                    app.navigatorOrNull?.showSnackbar(
                        "Download ${Translate.languageName(from)} in your phone's Live Translate settings to translate it",
                        actionLabel = if (settings != null) "Open" else null,
                        onAction = { settings?.let(ctx::startActivity) },
                    )
                } else {
                    app.navigatorOrNull?.showSnackbar("Couldn't translate this post")
                }
                return@launch
            }
            missing.keys.zip(out).forEach { (k, v) -> translations[k] = v }
            _state.update { it.copy(translating = false, translation = HashMap(translations), translatedTo = to) }
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

    private fun PostThread.withTree(comments: List<Comment>): PostThread {
        touched = true
        return copy(comments = comments, flat = CommentTree.flatten(comments, collapsed))
    }

    fun toggleCollapse(commentId: String) = edit { t ->
        val folded = CommentTree.folded(commentId)
        val next = when {
            // Expanding a comment also shows its folded replies.
            commentId in t.collapsed -> t.collapsed - commentId - folded
            folded in t.collapsed -> t.collapsed - folded
            // "Collapse only the replies": its own text stays (when it has replies to hide).
            app.settings.value.collapseRepliesOnly &&
                t.flat.firstOrNull { it.id == commentId }?.replies?.any { !it.isMore } == true -> t.collapsed + folded
            else -> t.collapsed + commentId
        }
        t.copy(collapsed = next, flat = CommentTree.flatten(t.comments, next))
    }

    /** "Show N replies" under a folded comment. */
    fun unfold(commentId: String) = edit { t ->
        val next = t.collapsed - CommentTree.folded(commentId)
        t.copy(collapsed = next, flat = CommentTree.flatten(t.comments, next))
    }

    /**
     * The comments a thread opens with collapsed: AutoModerator's (content
     * filter), ones scoring below the "Collapse low-scoring comments" setting
     * (not your own), and with "Open threads collapsed" every top-level
     * comment's replies (folded: its own text stays). [skip]: ones already
     * shown, left as they are.
     */
    private fun startCollapsed(comments: List<Comment>, skip: Set<String> = emptySet()): Set<String> {
        val autoMod = app.contentFilters.value.collapseAutoMod
        val s = app.settings.value
        val below = s.collapseBelowScore
        val me = app.session.username
        val out = HashSet<String>()
        for (c in CommentTree.flatten(comments, emptySet())) {
            if (c.isMore || c.id in skip) continue
            when {
                autoMod && c.author == "AutoModerator" -> out += c.id
                below != null && c.score < below && !c.scoreHidden && !c.author.equals(me, ignoreCase = true) -> out += c.id
                s.collapseTopLevel && c.depth == 0 && c.replies.any { !it.isMore } -> out += CommentTree.folded(c.id)
            }
        }
        return out
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
        if (fullname == t.post.fullname) t.copy(post = t.post.copy(selftext = newBody)).also { touched = true }
        else t.withTree(CommentTree.update(t.comments, fullname) { it.copy(body = newBody) })
    }

    fun updateComment(fullname: String, change: (Comment) -> Comment) = edit { t ->
        t.withTree(CommentTree.update(t.comments, fullname, change))
    }

    fun removeComment(fullname: String) = edit { t -> t.withTree(CommentTree.remove(t.comments, fullname)) }

    fun loadMore(moreNode: Comment) {
        val s = _state.value.thread ?: return
        if (moreNode.moreChildren.isEmpty() || moreNode.fullname in s.loadingMore) return
        touched = true // the full page would drop this "more" row mid-load
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
                    CommentTree.replaceMore(_state.value.thread?.comments ?: s.comments, moreNode, app.commentVotes.apply(flat))
                }
                edit { it.withTree(tree).copy(loadingMore = it.loadingMore - moreNode.fullname) }
                _state.value.translatedTo?.let(::translate)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                edit { it.copy(loadingMore = it.loadingMore - moreNode.fullname) }
            }
        }
    }
}
