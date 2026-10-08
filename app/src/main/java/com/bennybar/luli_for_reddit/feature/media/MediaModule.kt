package com.bennybar.luli_for_reddit.feature.media

import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import androidx.activity.result.contract.ActivityResultContracts
import com.bennybar.luli_for_reddit.AppContainer
import com.bennybar.luli_for_reddit.state.UserScoped
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.withContext
import java.io.File

/**
 * A folder the user picked to save media into (Storage Access Framework).
 * [uri] is the persisted tree URI, [name] its display path such as
 * "Pictures/Reddit".
 */
data class MediaFolder(val uri: String, val name: String)

/** Media singletons: where saved media goes, and the pooled feed video player. */
class MediaModule(private val c: AppContainer) : UserScoped {
    private val _folder = MutableStateFlow(readFolder())

    /** Where saved media goes: a picked folder, or null for the gallery's "Ilay" album. */
    val folder: StateFlow<MediaFolder?> = _folder

    /** The one ExoPlayer shared by every inline feed video. */
    val inlinePlayer by lazy { InlineVideoPool(c.context) }

    private fun readFolder(): MediaFolder? {
        val uri = c.prefs.getString(URI_KEY) ?: return null
        return MediaFolder(uri, c.prefs.getString(NAME_KEY) ?: "")
    }

    /**
     * Opens the system folder picker; keeps the current choice on cancel.
     * The Storage Access Framework reaches any folder (including SD cards)
     * without storage permissions, and the grant persists across restarts.
     */
    suspend fun pickFolder() {
        val tree = launchForResult(ActivityResultContracts.OpenDocumentTree(), null) ?: return
        val resolver = c.context.contentResolver
        try {
            resolver.takePersistableUriPermission(
                tree,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
        } catch (_: SecurityException) {
            return
        }
        // "primary:Pictures/Reddit" → "Pictures/Reddit"; the root reads as "Internal storage".
        val docId = DocumentsContract.getTreeDocumentId(tree)
        val name = docId.substringAfter(':').ifEmpty { "Internal storage" }
        c.prefs.setString(URI_KEY, tree.toString())
        c.prefs.setString(NAME_KEY, name)
        _folder.value = MediaFolder(tree.toString(), name)
    }

    /** Back to saving into the gallery. */
    fun useGallery() {
        c.prefs.remove(URI_KEY)
        c.prefs.remove(NAME_KEY)
        _folder.value = null
    }

    /**
     * Copies the downloaded [file] into [folder] as [name]. False when the
     * folder is no longer accessible (removed, or a grant lost on restore).
     */
    suspend fun saveToFolder(folder: MediaFolder, file: File, name: String, mime: String): Boolean =
        withContext(Dispatchers.IO) {
            try {
                val tree = Uri.parse(folder.uri)
                val resolver = c.context.contentResolver
                if (resolver.persistedUriPermissions.none { it.uri == tree && it.isWritePermission }) {
                    return@withContext false
                }
                val dir = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
                val target = DocumentsContract.createDocument(resolver, dir, mime, name) ?: return@withContext false
                resolver.openOutputStream(target)!!.use { out -> file.inputStream().use { it.copyTo(out) } }
                true
            } catch (_: Exception) {
                false
            }
        }

    override fun onUserChanged(username: String) {}

    private companion object {
        // Same keys as the Flutter build, so a picked folder carries over.
        const val URI_KEY = "mediaFolderUri"
        const val NAME_KEY = "mediaFolderName"
    }
}
