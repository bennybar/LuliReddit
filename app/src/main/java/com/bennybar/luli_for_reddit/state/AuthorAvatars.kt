package com.bennybar.luli_for_reddit.state

import androidx.compose.runtime.staticCompositionLocalOf
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.feature.post.CommentTree
import com.bennybar.luli_for_reddit.model.Comment
import com.bennybar.luli_for_reddit.model.Post
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update

/**
 * Commenters' profile pictures (#133), by lowercased name. Reddit's comments .json has
 * none. With the website sign-in they come from its GraphQL comment forest, about 25
 * comments a request: the first page as a thread opens (one more request), and up to
 * [MORE_PAGES] more once a long thread's full page is in (#217). With an API key they
 * come by account id, 100 a request, for at most 200 new commenters at a time (#185):
 * the first page, the full page and loaded "more replies" (#217). (The website sign-in
 * gets a 404 there.) Kept here for this thread and the next ones. In memory only.
 */
class AuthorAvatars {
    private val _icons = MutableStateFlow<Map<String, String>>(emptyMap())
    val icons: StateFlow<Map<String, String>> = _icons
    private val asked = HashSet<String>()
    /** Account ids already asked for with an API key (found or not). */
    private val askedIds = HashSet<String>()
    /** Website sign-in: where each thread's (postId|sort) GraphQL pages continue. */
    private val next = HashMap<String, String>()

    /** Once per thread and sort ([comments]: its first page); nothing with the setting off. */
    suspend fun loadFor(postId: String, sort: String, comments: List<Comment>) {
        if (!app.settings.value.commentAvatars || !asked.add("$postId|$sort")) return
        if (!app.client.isWebMode()) return loadAuthors(comments)
        val (found, after) = try {
            app.repository.getCommentAvatars(postId, sort)
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            asked.remove("$postId|$sort")
            return
        }
        if (after != null) next["$postId|$sort"] = after
        add(found)
    }

    /** A long thread's full page is in ([comments]): the commenters past the first page. */
    suspend fun loadRest(postId: String, sort: String, comments: List<Comment>) {
        if (!app.settings.value.commentAvatars) return
        if (!app.client.isWebMode()) return loadAuthors(comments)
        repeat(MORE_PAGES) {
            val after = next.remove("$postId|$sort") ?: return
            val (found, more) = try {
                app.repository.getCommentAvatars(postId, sort, after)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                return
            }
            if (more != null) next["$postId|$sort"] = more
            add(found)
        }
    }

    /** API key: [comments]' authors not known yet, by account id (each asked for once). */
    suspend fun loadAuthors(comments: List<Comment>) {
        if (!app.settings.value.commentAvatars || app.client.isWebMode()) return
        val known = _icons.value
        val ids = CommentTree.flatten(comments, emptySet())
            .filter { it.authorFullname.startsWith("t2_") && it.author.lowercase() !in known }
            .map { it.authorFullname }.distinct().filter { askedIds.add(it) }.take(200)
        if (ids.isEmpty()) return
        val found = try {
            HashMap<String, String>().apply { for (batch in ids.chunked(100)) putAll(app.repository.getUserIcons(batch)) }
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            askedIds.removeAll(ids.toSet())
            return
        }
        add(found)
    }

    /** Posters waiting to be asked for, by account id. Main thread only. */
    private val pending = LinkedHashSet<String>()
    private var flush: Job? = null

    /**
     * A card shows [post] (#270): its poster's picture is asked for together with the
     * other cards shown about now, so a page of posts costs one request (100 a request).
     * Nothing with the setting off, or with the website sign-in (it gets a 404 there).
     */
    fun wantPoster(post: Post) {
        // Settings › Poster's picture, or a layout that always shows it (Compact cards, #284).
        val s = app.settings.value
        if (!s.postAvatars && !s.postDisplay.showsPosters) return
        // The post brought its poster's picture (GraphQL, the website sign-in): no request.
        post.authorIcon?.let { icon ->
            if (_icons.value[post.author.lowercase()] != icon) add(mapOf(post.author.lowercase() to icon))
            return
        }
        val id = post.authorFullname
        if (!id.startsWith("t2_") || post.author.lowercase() in _icons.value || !askedIds.add(id)) return
        pending += id
        if (flush?.isActive == true) return
        flush = app.scope.launch {
            delay(POSTER_BATCH_WAIT_MS)
            if (app.client.isWebMode()) {
                pending.clear()
                return@launch
            }
            while (pending.isNotEmpty()) {
                val batch = pending.take(100)
                pending.removeAll(batch.toSet())
                val found = try {
                    app.repository.getUserIcons(batch)
                } catch (e: CancellationException) {
                    throw e
                } catch (_: Exception) {
                    askedIds.removeAll(batch.toSet())
                    return@launch
                }
                add(found)
            }
        }
    }

    private fun add(found: Map<String, String>) {
        if (found.isEmpty()) return
        _icons.update { old ->
            // Bounded: the oldest go first.
            val all = LinkedHashMap(old).apply { putAll(found) }
            if (all.size <= MAX) all else all.entries.drop(all.size - MAX).associate { it.key to it.value }
        }
    }

    private companion object {
        const val MAX = 3000
        const val MORE_PAGES = 3
        const val POSTER_BATCH_WAIT_MS = 300L
    }
}

/** [AuthorAvatars.icons] for a thread's rows, read once at its top. */
val LocalAuthorIcons = staticCompositionLocalOf<Map<String, String>> { emptyMap() }
