package com.bennybar.luli_for_reddit

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var pendingPick: MethodChannel.Result? = null

    // "Save media to" a folder the user picks. The Storage Access Framework
    // reaches any folder (including SD cards) without storage permissions,
    // and the grant persists across restarts.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ilay/media_folder")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pick" -> {
                        pendingPick?.error("cancelled", "Superseded", null)
                        pendingPick = result
                        startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE), PICK_FOLDER)
                    }
                    "save" -> try {
                        result.success(
                            save(
                                Uri.parse(call.argument<String>("tree")!!),
                                call.argument<String>("path")!!,
                                call.argument<String>("name")!!,
                                call.argument<String>("mime")!!,
                            )
                        )
                    } catch (e: Exception) {
                        result.error("save_failed", e.message, null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_FOLDER) return
        val result = pendingPick ?: return
        pendingPick = null
        val tree = data?.data
        if (resultCode != Activity.RESULT_OK || tree == null) {
            result.success(null)
            return
        }
        contentResolver.takePersistableUriPermission(
            tree, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        )
        // "primary:Pictures/Reddit" → "Pictures/Reddit"; the root reads as "Internal storage".
        val docId = DocumentsContract.getTreeDocumentId(tree)
        val name = docId.substringAfter(':').ifEmpty { "Internal storage" }
        result.success(mapOf("uri" to tree.toString(), "name" to name))
    }

    /** Copies the downloaded file at [path] into the picked folder; returns false if access was lost. */
    private fun save(tree: Uri, path: String, name: String, mime: String): Boolean {
        if (contentResolver.persistedUriPermissions.none { it.uri == tree && it.isWritePermission }) {
            return false
        }
        val folder = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
        val target = DocumentsContract.createDocument(contentResolver, folder, mime, name) ?: return false
        contentResolver.openOutputStream(target)!!.use { out ->
            File(path).inputStream().use { it.copyTo(out) }
        }
        return true
    }

    private companion object {
        const val PICK_FOLDER = 4107
    }
}
