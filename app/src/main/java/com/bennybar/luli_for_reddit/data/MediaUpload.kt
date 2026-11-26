package com.bennybar.luli_for_reddit.data

import com.bennybar.luli_for_reddit.core.get
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

/**
 * Reddit's media lease (`/api/media/asset.json`), #296. An image leased with a `filepath`
 * comes back from Reddit as `{"status": "failed"}` (seen since about November 2026): an
 * image post went up as just its title, a gallery or an image in a body as a "Processing
 * img" placeholder. Images lease with only their mimetype, as Infinity for Reddit does since
 * then; videos keep the filepath. The mimetype must be the file's real format.
 */
object MediaUpload {
    fun leaseParams(filename: String, mimeType: String): Map<String, String> =
        if (mimeType.startsWith("video/")) mapOf("filepath" to filename, "mimetype" to mimeType)
        else mapOf("mimetype" to mimeType)

    /** An image's real format from its first bytes (a picker can mislabel it); else [fallback]. */
    fun imageMimeType(bytes: ByteArray, fallback: String): String {
        fun at(i: Int) = if (i < bytes.size) bytes[i].toInt() and 0xFF else -1
        fun ascii(from: Int, s: String) = s.indices.all { at(from + it) == s[it].code }
        return when {
            at(0) == 0xFF && at(1) == 0xD8 && at(2) == 0xFF -> "image/jpeg"
            at(0) == 0x89 && ascii(1, "PNG") -> "image/png"
            ascii(0, "GIF8") -> "image/gif"
            ascii(0, "RIFF") && ascii(8, "WEBP") -> "image/webp"
            ascii(4, "ftyp") && listOf("heic", "heix", "heif", "mif1").any { ascii(8, it) } -> "image/heic"
            else -> fallback
        }
    }

    /** [filename] with the extension of [mimeType], so the name, the lease and the bytes agree. */
    fun fileName(filename: String, mimeType: String): String {
        val ext = when (mimeType) {
            "image/jpeg" -> "jpg"
            "image/png" -> "png"
            "image/gif" -> "gif"
            "image/webp" -> "webp"
            else -> return filename
        }
        val base = filename.substringBeforeLast('.', filename).ifEmpty { "image" }
        return "$base.$ext"
    }

    /** The upload form: wrapped in `args` (a filepath lease) or bare (an image lease). */
    fun uploadForm(lease: JsonElement?): JsonElement? = lease["args"] as? JsonObject ?: lease

    /** A tag's text in S3's XML answer (`Location`, `Key`). */
    fun xmlTag(xml: String, tag: String): String? =
        Regex("<$tag>(.*?)</$tag>").find(xml)?.groupValues?.get(1)?.replace("&amp;", "&")
}
