package com.bennybar.luli_for_reddit.state

import android.content.Context
import androidx.compose.runtime.Immutable
import coil3.SingletonImageLoader
import coil3.request.ImageRequest
import com.bennybar.luli_for_reddit.core.AppJson
import com.bennybar.luli_for_reddit.core.arr
import com.bennybar.luli_for_reddit.core.get
import com.bennybar.luli_for_reddit.core.long
import com.bennybar.luli_for_reddit.core.storage.Prefs
import com.bennybar.luli_for_reddit.core.str
import com.bennybar.luli_for_reddit.data.RedditRepository
import com.bennybar.luli_for_reddit.model.Post
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.io.File

/** A thread saved for reading later / offline. */
@Immutable
data class OfflineThread(val id: String, val subreddit: String, val title: String, val savedAt: Long)

/**
 * "Read later": threads saved with their comments for offline reading. The
 * list is per account (prefs `offline_threads_<user>`); the files are keyed
 * by post id under filesDir/offline_threads (same place as the Flutter build,
 * so saved threads carry over).
 */
class OfflineStore(
    private val context: Context,
    private val prefs: Prefs,
    private val repo: RedditRepository,
) : UserScoped {
    private var key = BASE
    private val _state = MutableStateFlow<List<OfflineThread>>(emptyList())
    val state: StateFlow<List<OfflineThread>> = _state

    private fun threadFile(postId: String): File =
        File(context.filesDir, "offline_threads").apply { if (!exists()) mkdirs() }.let { File(it, "$postId.json") }

    override fun onUserChanged(username: String) {
        key = userScopedKey(prefs, username, BASE)
        val raw = prefs.getString(key)
        _state.value = if (raw == null) emptyList() else runCatching {
            AppJson.parseToJsonElement(raw).arr()!!.map {
                OfflineThread(it["id"].str()!!, it["sub"].str() ?: "", it["title"].str() ?: "", it["at"].long() ?: 0)
            }
        }.getOrDefault(emptyList())
    }

    fun contains(postId: String): Boolean = _state.value.any { it.id == postId }

    /** The saved comments response for [postId], or null if it wasn't saved. */
    suspend fun read(postId: String): JsonElement? = withContext(Dispatchers.IO) {
        runCatching { threadFile(postId).takeIf { it.exists() }?.readText()?.let(AppJson::parseToJsonElement) }.getOrNull()
    }

    private fun persist(next: List<OfflineThread>) {
        _state.value = next
        prefs.setString(
            key,
            JsonArray(next.map { t ->
                buildJsonObject { put("id", t.id); put("sub", t.subreddit); put("title", t.title); put("at", t.savedAt) }
            }).toString(),
        )
    }

    /** Downloads [post]'s thread (up to 500 comments) and its images. */
    suspend fun save(post: Post) {
        val raw = repo.getCommentsRaw(post.subreddit, post.id, limit = 500)
        withContext(Dispatchers.IO) { threadFile(post.id).writeText(raw.toString()) }
        // Images go into the regular image cache, so the post renders offline.
        val loader = SingletonImageLoader.get(context)
        (listOfNotNull(post.previewUrl, post.previewMedUrl) + post.gallery.map { it.url }).toSet().forEach {
            loader.enqueue(ImageRequest.Builder(context).data(it).build())
        }
        persist(listOf(OfflineThread(post.id, post.subreddit, post.title, System.currentTimeMillis())) +
            _state.value.filter { it.id != post.id })
    }

    suspend fun remove(postId: String) {
        persist(_state.value.filter { it.id != postId })
        withContext(Dispatchers.IO) { runCatching { threadFile(postId).delete() } }
    }

    companion object {
        private const val BASE = "offline_threads"
    }
}
