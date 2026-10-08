package com.bennybar.luli_for_reddit.nav

import androidx.compose.animation.core.MutableTransitionState
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.listSaver
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * A full-screen media viewer. Not a NavHost destination: viewers are drawn
 * as a transparent overlay above the current screen (the Flutter build's
 * non-opaque fade route), so swipe-to-dismiss reveals the feed underneath.
 */
@Serializable
sealed interface MediaViewer {
    @Serializable data class Image(val url: String, val title: String? = null) : MediaViewer

    @Serializable data class Gallery(
        val urls: List<String>,
        val widths: List<Int> = emptyList(),
        val heights: List<Int> = emptyList(),
        val title: String? = null,
        val initialIndex: Int = 0,
    ) : MediaViewer

    @Serializable data class Video(
        val url: String,
        val title: String? = null,
        val downloadUrl: String? = null,
        val externalUrl: String? = null,
    ) : MediaViewer
}

/** The open viewers, bottom to top. Each fades in (220ms) and out (180ms) before it leaves. */
class ViewerStack(restored: List<MediaViewer> = emptyList()) {
    class Entry(val viewer: MediaViewer, val id: Long, visible: Boolean) {
        val visibility = MutableTransitionState(visible).apply { targetState = true }
        val closing get() = !visibility.targetState
    }

    private var nextId = 0L
    val entries = mutableStateListOf<Entry>().apply { restored.forEach { add(Entry(it, nextId++, visible = true)) } }

    val isOpen get() = entries.any { !it.closing }

    fun open(viewer: MediaViewer) {
        entries += Entry(viewer, nextId++, visible = false)
    }

    /** Fades out the top viewer; false when none is open. */
    fun closeTop(): Boolean {
        val top = entries.lastOrNull { !it.closing } ?: return false
        top.visibility.targetState = false
        return true
    }

    fun clear() = entries.clear()

    companion object {
        private val json = Json { ignoreUnknownKeys = true }

        /** Survives activity recreation, like the NavHost back stack. */
        val Saver: Saver<ViewerStack, Any> = listSaver(
            save = { s -> s.entries.filter { !it.closing }.map { json.encodeToString(MediaViewer.serializer(), it.viewer) } },
            restore = { list -> ViewerStack(list.mapNotNull { runCatching { json.decodeFromString(MediaViewer.serializer(), it) }.getOrNull() }) },
        )
    }
}
