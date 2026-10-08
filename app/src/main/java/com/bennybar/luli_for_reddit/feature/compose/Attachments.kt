package com.bennybar.luli_for_reddit.feature.compose

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier

/**
 * [Agent B] A piece of media to attach to a reply or message, read into
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

/**
 * [Agent B] Composer attachment UI: pending-attachment preview plus
 * pick-image / pick-video / paste buttons. [leading] = extra buttons (e.g.
 * GIF). [catboxForImages]: messages host even images on Catbox.
 */
@Composable
fun AttachmentControls(
    media: MediaAttachment?,
    onChanged: (MediaAttachment?) -> Unit,
    onError: (String) -> Unit,
    modifier: Modifier = Modifier,
    catboxForImages: Boolean = false,
    leading: @Composable () -> Unit = {},
) {}

/** [Agent B] Giphy search sheet (uses the stored Giphy key). Returns the GIF URL or null. */
suspend fun showGiphyPicker(): String? = null
