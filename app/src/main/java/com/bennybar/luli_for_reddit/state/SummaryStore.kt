package com.bennybar.luli_for_reddit.state

import android.content.Context
import com.bennybar.luli_for_reddit.core.AppJson
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import java.io.File

/** One AI thread summary, kept with enough of its post to list it and open it again. */
@Serializable
data class SavedSummary(
    val postId: String,
    val subreddit: String,
    val title: String,
    val permalink: String,
    val style: String,
    val model: String,
    val text: String,
    val createdAt: Long,
)

/**
 * The posts you've summarized (newest first), per account, on this device
 * only — the "Summaries" list in the You tab. A post summarized again
 * replaces its older entry. Kept to the last [MAX].
 */
class SummaryStore(private val context: Context) : UserScoped {
    // One writer at a time, in order: parallel writes could land out of order
    // or interleave and corrupt the file (which then loads as empty).
    private val io = CoroutineScope(SupervisorJob() + Dispatchers.IO.limitedParallelism(1))
    private var file = fileFor("")
    private val _items = MutableStateFlow<List<SavedSummary>>(emptyList())
    val items: StateFlow<List<SavedSummary>> = _items
    // The account's file hasn't loaded yet: summaries made meanwhile wait here,
    // so they're merged into it instead of overwriting it.
    @Volatile private var loaded = false
    private val early = mutableListOf<SavedSummary>()

    fun add(s: SavedSummary) {
        _items.value = (listOf(s) + _items.value.filter { it.postId != s.postId }).take(MAX)
        synchronized(early) { if (!loaded) { early.add(s); return } }
        save()
    }

    fun remove(postId: String) {
        _items.value = _items.value.filter { it.postId != postId }
        save()
    }

    private fun save() {
        val f = file
        val list = _items.value
        io.launch {
            runCatching {
                // Write a temp file and swap it in, so a crash mid-write can't truncate it.
                val tmp = File(f.parentFile, f.name + ".tmp")
                tmp.writeText(AppJson.encodeToString(ListSerializer(SavedSummary.serializer()), list))
                if (!tmp.renameTo(f)) { f.delete(); tmp.renameTo(f) }
            }
        }
    }

    override fun onUserChanged(username: String) {
        file = fileFor(username)
        _items.value = emptyList()
        synchronized(early) { loaded = false; early.clear() }
        val f = file
        io.launch {
            val list = runCatching {
                if (f.exists()) AppJson.decodeFromString(ListSerializer(SavedSummary.serializer()), f.readText()) else emptyList()
            }.getOrDefault(emptyList())
            if (file != f) return@launch
            val pending = synchronized(early) { loaded = true; early.toList().also { early.clear() } }
            var merged = list
            for (s in pending) merged = (listOf(s) + merged.filter { it.postId != s.postId }).take(MAX)
            _items.value = merged
            if (pending.isNotEmpty()) save()
        }
    }

    private fun fileFor(username: String) =
        File(context.filesDir, if (username.isEmpty()) "summaries.json" else "summaries_${username.lowercase()}.json")

    private companion object {
        const val MAX = 200
    }
}
