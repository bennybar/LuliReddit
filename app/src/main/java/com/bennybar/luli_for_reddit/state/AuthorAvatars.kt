package com.bennybar.luli_for_reddit.state

import androidx.compose.runtime.staticCompositionLocalOf
import com.bennybar.luli_for_reddit.app
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update

/**
 * Commenters' profile pictures (#133), by lowercased name. Reddit's comments .json has
 * none; its GraphQL comment forest has each author's, so with the website sign-in a
 * thread asks for its first page that way too (one more request) and keeps what comes
 * back here, for this thread and the next ones. In memory only.
 */
class AuthorAvatars {
    private val _icons = MutableStateFlow<Map<String, String>>(emptyMap())
    val icons: StateFlow<Map<String, String>> = _icons
    private val asked = HashSet<String>()

    /** Once per thread and sort; nothing without the website sign-in or with the setting off. */
    suspend fun loadFor(postId: String, sort: String) {
        if (!app.settings.value.commentAvatars || !asked.add("$postId|$sort")) return
        val found = try {
            if (!app.client.isWebMode()) return
            app.repository.getCommentAvatars(postId, sort)
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            asked.remove("$postId|$sort")
            return
        }
        if (found.isEmpty()) return
        _icons.update { old ->
            // Bounded: the oldest go first.
            val all = LinkedHashMap(old).apply { putAll(found) }
            if (all.size <= MAX) all else all.entries.drop(all.size - MAX).associate { it.key to it.value }
        }
    }

    private companion object {
        const val MAX = 3000
    }
}

/** [AuthorAvatars.icons] for a thread's rows, read once at its top. */
val LocalAuthorIcons = staticCompositionLocalOf<Map<String, String>> { emptyMap() }
