package com.bennybar.luli_for_reddit.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.key
import kotlinx.coroutines.CompletableDeferred

/**
 * Imperative bottom sheets and dialogs, the way the Flutter build used
 * `showModalBottomSheet` / `showDialog`: call a suspend function, get the
 * result back. [OverlayHost] (at the app root) draws whatever is open.
 *
 * ```
 * val reason = Overlays.show<String> { done -> ReportDialog(onPick = done, onDismiss = { done(null) }) }
 * ```
 * The content must call `done(result)` exactly when it closes (null = dismissed).
 */
object Overlays {
    internal class Entry(val id: Long, val content: @Composable (done: (Any?) -> Unit) -> Unit, val result: CompletableDeferred<Any?>)

    internal val stack = mutableStateListOf<Entry>()
    private var nextId = 0L

    @Suppress("UNCHECKED_CAST")
    suspend fun <T> show(content: @Composable (done: (T?) -> Unit) -> Unit): T? {
        val deferred = CompletableDeferred<Any?>()
        val entry = Entry(nextId++, { done -> content { done(it) } }, deferred)
        stack.add(entry)
        return try {
            deferred.await() as T?
        } finally {
            stack.remove(entry)
        }
    }

    /** Fire-and-forget variant for sheets with no result. */
    fun launch(content: @Composable (done: () -> Unit) -> Unit) {
        val deferred = CompletableDeferred<Any?>()
        lateinit var entry: Entry
        entry = Entry(nextId++, { done -> content { done(null) } }, deferred)
        deferred.invokeOnCompletion { stack.remove(entry) }
        stack.add(entry)
    }

    fun dismissAll() {
        stack.toList().forEach { it.result.complete(null) }
        stack.clear()
    }
}

@Composable
fun OverlayHost() {
    for (entry in Overlays.stack) {
        key(entry.id) {
            entry.content { result ->
                entry.result.complete(result)
                Overlays.stack.remove(entry)
            }
        }
    }
}
