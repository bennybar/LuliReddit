package com.bennybar.luli_for_reddit.feature.compose

import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Image
import androidx.compose.material.icons.outlined.Movie
import androidx.compose.material.icons.outlined.Videocam
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.ContentPaste
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.compose.AsyncImage
import com.bennybar.luli_for_reddit.feature.markdown.IconTooltip
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * A piece of media to attach to a reply or message, read into
 * memory and ready to upload (Reddit for inline comment images, Catbox for
 * videos / message attachments).
 */
class MediaAttachment(val bytes: ByteArray, val filename: String, val mimeType: String, val isVideo: Boolean) {
    val sizeLabel: String
        get() {
            val kb = bytes.size / 1024.0
            return if (kb < 1024) "${kb.toInt()} KB" else String.format(java.util.Locale.US, "%.1f MB", kb / 1024)
        }
}

/** An image mime type from a file name, defaulting to JPEG. */
fun mimeForImage(name: String): String {
    val n = name.lowercase()
    return when {
        n.endsWith(".png") -> "image/png"
        n.endsWith(".gif") -> "image/gif"
        n.endsWith(".webp") -> "image/webp"
        else -> "image/jpeg"
    }
}

/** The display name of a content [uri], or null. */
fun displayName(context: Context, uri: Uri): String? = runCatching {
    context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
        if (c.moveToFirst()) c.getString(0) else null
    }
}.getOrNull()

/** Reads a picked image/video into memory. */
suspend fun readAttachment(context: Context, uri: Uri, isVideo: Boolean): MediaAttachment = withContext(Dispatchers.IO) {
    val cr = context.contentResolver
    val bytes = cr.openInputStream(uri)?.use { it.readBytes() } ?: throw Exception("Couldn't read the file.")
    val name = displayName(context, uri)?.ifEmpty { null } ?: if (isVideo) "video.mp4" else "image.jpg"
    val mime = cr.getType(uri) ?: if (isVideo) "video/mp4" else mimeForImage(name)
    MediaAttachment(bytes, name, mime, isVideo)
}

/**
 * Reads an image off the system clipboard (a pasted screenshot/copy). Returns
 * null if the clipboard holds no image.
 */
suspend fun pasteImageAttachment(context: Context): MediaAttachment? {
    val cm = context.getSystemService(ClipboardManager::class.java) ?: return null
    val clip = cm.primaryClip ?: return null
    val desc = cm.primaryClipDescription
    for (i in 0 until clip.itemCount) {
        val uri = clip.getItemAt(i).uri ?: continue
        val type = context.contentResolver.getType(uri)
        val isImage = type?.startsWith("image/") == true ||
            (desc != null && (0 until desc.mimeTypeCount).any { ClipDescription.compareMimeTypes(desc.getMimeType(it), "image/*") })
        if (!isImage) continue
        val bytes = withContext(Dispatchers.IO) {
            runCatching { context.contentResolver.openInputStream(uri)?.use { it.readBytes() } }.getOrNull()
        }
        if (bytes == null || bytes.isEmpty()) continue
        val mime = type ?: "image/png"
        val ext = when (mime) { "image/jpeg" -> "jpg"; "image/gif" -> "gif"; "image/webp" -> "webp"; else -> "png" }
        return MediaAttachment(bytes, "pasted.$ext", mime, isVideo = false)
    }
    return null
}

/**
 * Composer attachment UI: pending-attachment preview plus
 * pick-image / pick-video / paste buttons. [leading] = extra buttons (e.g.
 * GIF). [catboxForImages]: messages host even images on Catbox.
 * Stateless — the parent owns [media] and is told via [onChanged] / [onError].
 */
@Composable
fun AttachmentControls(
    media: MediaAttachment?,
    onChanged: (MediaAttachment?) -> Unit,
    onError: (String) -> Unit,
    modifier: Modifier = Modifier,
    catboxForImages: Boolean = false,
    leading: @Composable () -> Unit = {},
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    fun load(uri: Uri?, isVideo: Boolean) {
        uri ?: return
        scope.launch {
            try {
                onChanged(readAttachment(context, uri, isVideo))
            } catch (e: Exception) {
                onError((e.message ?: e.toString()).removePrefix("Exception: "))
            }
        }
    }
    val pickImage = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { load(it, false) }
    val pickVideo = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { load(it, true) }
    val cs = MaterialTheme.colorScheme

    Column(modifier) {
        if (media != null) {
            AttachmentPreview(media, onRemove = { onChanged(null) })
            Spacer(Modifier.height(4.dp))
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            leading()
            IconTooltip("Attach image") {
                IconButton(onClick = { pickImage.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }) {
                    Icon(Icons.Outlined.Image, contentDescription = "Attach image")
                }
            }
            IconTooltip("Attach video") {
                IconButton(onClick = { pickVideo.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.VideoOnly)) }) {
                    Icon(Icons.Outlined.Videocam, contentDescription = "Attach video")
                }
            }
            IconTooltip("Paste image") {
                IconButton(onClick = {
                    scope.launch {
                        try {
                            val m = pasteImageAttachment(context)
                            if (m == null) onError("No image on the clipboard.") else onChanged(m)
                        } catch (e: Exception) {
                            onError((e.message ?: e.toString()).removePrefix("Exception: "))
                        }
                    }
                }) {
                    Icon(Icons.Rounded.ContentPaste, contentDescription = "Paste image")
                }
            }
        }
        if (media != null) {
            Text(
                if (media.isVideo || catboxForImages) "Will be uploaded to catbox.moe and linked (public)."
                else "Image posts inline (hosted by Reddit; some subs disallow it — falls back to a catbox.moe link).",
                fontSize = 11.sp,
                color = cs.onSurfaceVariant,
            )
        }
    }
}

/** Small inline preview of a pending attachment with a remove button. */
@Composable
fun AttachmentPreview(media: MediaAttachment, onRemove: () -> Unit, modifier: Modifier = Modifier) {
    val cs = MaterialTheme.colorScheme
    Row(
        modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(cs.surfaceContainerHighest)
            .padding(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier.size(48.dp).clip(RoundedCornerShape(8.dp)).background(cs.surfaceContainerHigh),
            contentAlignment = Alignment.Center,
        ) {
            if (media.isVideo) {
                Icon(Icons.Outlined.Movie, null, tint = cs.onSurfaceVariant)
            } else {
                AsyncImage(model = media.bytes, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.size(48.dp))
            }
        }
        Spacer(Modifier.width(10.dp))
        Column(Modifier.weight(1f)) {
            Text(if (media.isVideo) "Video" else "Image", fontWeight = FontWeight.SemiBold)
            Text(media.sizeLabel, fontSize = 12.sp, color = cs.onSurfaceVariant)
        }
        IconTooltip("Remove") {
            IconButton(onClick = onRemove) { Icon(Icons.Rounded.Close, contentDescription = "Remove") }
        }
    }
}
