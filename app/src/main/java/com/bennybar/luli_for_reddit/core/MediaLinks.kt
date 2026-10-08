package com.bennybar.luli_for_reddit.core

import android.net.Uri

// Detection of media URLs embedded in comment/post markdown, so we can render
// them natively (image/video viewers) instead of kicking out to a browser.

/** Path (ignoring the query string), lowercased — reddit appends `?width=…&s=…`. */
private fun Uri.lowerPath(): String = (path ?: "").lowercase()

fun isImageUrl(u: Uri): Boolean {
    val p = u.lowerPath()
    if (p.endsWith(".jpg") || p.endsWith(".jpeg") || p.endsWith(".png") ||
        p.endsWith(".webp") || p.endsWith(".gif")
    ) return true
    val host = u.host?.lowercase()
    return host == "i.redd.it" || host == "preview.redd.it" || host == "i.imgur.com"
}

fun isVideoUrl(u: Uri): Boolean {
    val p = u.lowerPath()
    if (p.endsWith(".mp4") || p.endsWith(".gifv")) return true
    return u.host?.lowercase() == "v.redd.it"
}

fun isMediaUrl(u: Uri): Boolean = isVideoUrl(u) || isImageUrl(u)

/** True when the URL points at an animated GIF. */
fun isGifUrl(u: Uri): Boolean = u.lowerPath().endsWith(".gif")

private val urlRe = Regex("""https?://[^\s<>)\]"]+""")

/** Media URLs referenced anywhere in [markdown], de-duplicated, in order. */
fun extractMediaLinks(markdown: String): List<Uri> {
    val out = mutableListOf<Uri>()
    val seen = mutableSetOf<String>()
    for (m in urlRe.findAll(markdown)) {
        // Trim trailing markdown/sentence punctuation the regex may have caught.
        val raw = m.value.trimEnd { it in ".,;:!*_" }
        val uri = runCatching { Uri.parse(raw) }.getOrNull() ?: continue
        if (uri.scheme == null || !isMediaUrl(uri)) continue
        if (seen.add(raw)) out.add(uri)
    }
    return out
}

private val mediaRefRe = Regex("""!\[[^\]]*]\(([^)\s]+)\)""")

/**
 * Reddit stores GIFs from its picker and some uploaded images in a comment as
 * `![gif](giphy|id|downsized)` / `![img](id)`, with the real URL in
 * `media_metadata` ([media]). Returns [body] with those references removed
 * and their URLs.
 */
fun splitMediaRefs(body: String, media: Map<String, String>): Pair<String, List<Uri>> {
    if (media.isEmpty()) return body to emptyList()
    val found = mutableListOf<Uri>()
    val text = mediaRefRe.replace(body) { m ->
        val url = media[m.groupValues[1]] ?: return@replace m.value
        found.add(Uri.parse(url))
        ""
    }
    return text.trim() to found
}

/**
 * The playable URL for a video link: imgur `.gifv` → `.mp4`; everything else
 * unchanged. (v.redd.it links are resolved by the player via their HLS/DASH.)
 */
fun resolveVideoUrl(url: String): String =
    if (url.lowercase().substringBefore('?').endsWith(".gifv")) {
        url.replace(Regex("""\.gifv""", RegexOption.IGNORE_CASE), ".mp4")
    } else url
