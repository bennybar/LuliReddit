package com.bennybar.luli_for_reddit.core.net

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MultipartBody
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

/**
 * Uploads bytes to catbox.moe — a free, anonymous file host (no account / API
 * key) that accepts images and video. Returns the public direct URL.
 *
 * Used for media Reddit can't host natively: videos in comment replies and
 * any attachment in a private message. Anyone with the (unguessable) URL can
 * reach the file — surface that before uploading.
 */
suspend fun uploadToCatbox(bytes: ByteArray, filename: String): String {
    val body = MultipartBody.Builder().setType(MultipartBody.FORM)
        .addFormDataPart("reqtype", "fileupload")
        .addFormDataPart("fileToUpload", filename, bytes.toRequestBody())
        .build()
    val req = Request.Builder().url("https://catbox.moe/user/api.php").post(body).build()
    val text = Http.client.await(req).use { withContext(Dispatchers.IO) { it.body.string() } }.trim()
    if (!text.startsWith("http")) throw Exception("Upload failed: ${text.ifEmpty { "empty response" }}")
    return text
}
