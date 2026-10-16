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
 * list is per account (prefs `offline_threads_<user>`), and so are the files
 * (filesDir/offline_threads/u_<user>/<postId>.json). Older copies saved
 * straight under offline_threads (the Flutter build) are still read.
 */
class OfflineStore(
    private val context: Context,
    private val prefs: Prefs,
    private val repo: RedditRepository,
) : UserScoped {
    private var key = BASE
    private var user = ""
    private val _state = MutableStateFlow<List<OfflineThread>>(emptyList())
    val state: StateFlow<List<OfflineThread>> = _state

    private fun root(): File = File(context.filesDir, "offline_threads").apply { if (!exists()) mkdirs() }

    // Each account's threads in its own folder: two accounts saving the same
    // thread (or one with access to a private sub) never share or delete a copy.
    private fun threadFile(owner: String, postId: String): File =
        File(root(), "u_" + owner.lowercase().ifEmpty { "_" }).apply { if (!exists()) mkdirs() }.let { File(it, "$postId.json") }

    // Where the Flutter build (and Ilay before 2.0.10) kept them, for every account.
    private fun legacyFile(postId: String): File = File(root(), "$postId.json")

    override fun onUserChanged(username: String) {
        user = username
        key = userScopedKey(prefs, username, BASE)
        _state.value = readIndex(key)
    }

    private fun readIndex(indexKey: String): List<OfflineThread> {
        val raw = prefs.getString(indexKey) ?: return emptyList()
        return runCatching {
            AppJson.parseToJsonElement(raw).arr()!!.map {
                OfflineThread(it["id"].str()!!, it["sub"].str() ?: "", it["title"].str() ?: "", it["at"].long() ?: 0)
            }
        }.getOrDefault(emptyList())
    }

    fun contains(postId: String): Boolean = _state.value.any { it.id == postId }

    /** The saved comments response for [postId], or null if this account didn't save it. */
    suspend fun read(postId: String): JsonElement? {
        if (!contains(postId)) return null
        val owner = user
        return withContext(Dispatchers.IO) {
            runCatching {
                (threadFile(owner, postId).takeIf { it.exists() } ?: legacyFile(postId).takeIf { it.exists() })
                    ?.readText()?.let(AppJson::parseToJsonElement)
            }.getOrNull()
        }
    }

    private fun persist(indexKey: String, next: List<OfflineThread>) {
        if (indexKey == key) _state.value = next
        prefs.setString(
            indexKey,
            JsonArray(next.map { t ->
                buildJsonObject { put("id", t.id); put("sub", t.subreddit); put("title", t.title); put("at", t.savedAt) }
            }).toString(),
        )
    }

    /** Downloads [post]'s thread (up to 500 comments) and its images. */
    suspend fun save(post: Post) {
        // The account that asked: a switch during the download still files it there.
        val owner = user
        val indexKey = key
        val raw = repo.getCommentsRaw(post.subreddit, post.id, limit = 500)
        withContext(Dispatchers.IO) { threadFile(owner, post.id).writeText(raw.toString()) }
        // Images go into the regular image cache, so the post renders offline.
        val loader = SingletonImageLoader.get(context)
        (listOfNotNull(post.previewUrl, post.previewMedUrl) + post.gallery.map { it.url }).toSet().forEach {
            loader.enqueue(ImageRequest.Builder(context).data(it).build())
        }
        val current = if (indexKey == key) _state.value else readIndex(indexKey)
        persist(indexKey, listOf(OfflineThread(post.id, post.subreddit, post.title, System.currentTimeMillis())) +
            current.filter { it.id != post.id })
    }

    suspend fun remove(postId: String) {
        val owner = user
        persist(key, _state.value.filter { it.id != postId })
        withContext(Dispatchers.IO) {
            runCatching { threadFile(owner, postId).delete() }
            // A shared old-style copy goes only once no account lists it.
            val stillListed = prefs.keys().filter { it == BASE || it.startsWith(BASE + "_") }
                .any { k -> readIndex(k).any { it.id == postId } }
            if (!stillListed) runCatching { legacyFile(postId).delete() }
        }
    }

    companion object {
        private const val BASE = "offline_threads"
    }
}
