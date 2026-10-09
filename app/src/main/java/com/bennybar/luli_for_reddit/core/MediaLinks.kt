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

/**
 * A video uploaded inside a text post or comment appears in the text as
 * `reddit.com/link/<post>/video/<id>/player`; it's the v.redd.it video `<id>`.
 * Returns that v.redd.it URL, else null.
 */
fun inlineRedditVideo(u: Uri): Uri? {
    val host = u.host?.lowercase() ?: return null
    if (host != "reddit.com" && !host.endsWith(".reddit.com")) return null
    val seg = u.pathSegments
    val i = seg.indexOf("video")
    if (seg.firstOrNull() != "link" || i < 0 || i + 1 >= seg.size) return null
    return Uri.parse("https://v.redd.it/${seg[i + 1]}")
}

fun isVideoUrl(u: Uri): Boolean {
    if (inlineRedditVideo(u) != null) return true
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
        val media = inlineRedditVideo(uri) ?: uri
        if (seen.add(media.toString())) out.add(media)
    }
    return out
}

/** An uploaded image / picker GIF in a body: `![gif](giphy|id|downsized)` / `![img](id)`; its URL is in `media_metadata`. */
private val mediaRefRe = Regex("""!\[[^\]]*]\(([^)\s]+)\)""")

/**
 * The playable URL for a video link: imgur `.gifv` → `.mp4`; a bare
 * v.redd.it video (or one embedded in a post / comment as
 * `reddit.com/link/…/video/<id>/player`) → its HLS playlist, which the player
 * streams with sound; everything else unchanged.
 */
fun resolveVideoUrl(url: String): String {
    val u = runCatching { Uri.parse(url) }.getOrNull()
    val v = u?.let { inlineRedditVideo(it) } ?: u?.takeIf { it.host?.lowercase() == "v.redd.it" }
    if (v != null && v.pathSegments.size == 1) return "https://v.redd.it/${v.pathSegments[0]}/HLSPlaylist.m3u8"
    return if (url.lowercase().substringBefore('?').endsWith(".gifv")) {
        url.replace(Regex("""\.gifv""", RegexOption.IGNORE_CASE), ".mp4")
    } else url
}

/** A piece of a post / comment body: markdown text, or one media item shown in its place. */
sealed interface BodySegment {
    data class Text(val markdown: String) : BodySegment
    data class Media(val uri: Uri) : BodySegment
}

private val paragraphRe = Regex("""\n\s*\n""")
private val loneLinkRe = Regex("""^!?\[[^\]]*]\((\S+?)\)$|^<?(https?://\S+?)>?$""")

/**
 * Splits [body] into text and media, in reading order. A paragraph that is
 * only a media link (a bare URL, `[text](url)` or an uploaded `![img](id)`
 * from [media]) becomes that media, without its link text; media linked
 * inside a sentence follows its paragraph. At most [maxMedia] media items.
 */
fun bodySegments(body: String, media: Map<String, String>, maxMedia: Int): List<BodySegment> {
    // Uploaded media refs become their own paragraphs holding the real URL.
    val expanded = if (media.isEmpty()) body else mediaRefRe.replace(body) { m ->
        media[m.groupValues[1]]?.let { "\n\n$it\n\n" } ?: m.value
    }
    val out = mutableListOf<BodySegment>()
    val text = StringBuilder()
    val seen = mutableSetOf<String>()
    var count = 0
    fun flush() {
        if (text.isNotBlank()) out.add(BodySegment.Text(text.toString().trim()))
        text.clear()
    }
    fun addMedia(u: Uri) {
        if (count >= maxMedia || !seen.add(u.toString())) return
        count++
        out.add(BodySegment.Media(u))
    }
    for (para in expanded.split(paragraphRe)) {
        val p = para.trim()
        if (p.isEmpty()) continue
        val lone = loneLinkRe.matchEntire(p)?.let { it.groupValues[1].ifEmpty { it.groupValues[2] } }
        val loneUri = lone?.let { runCatching { Uri.parse(it) }.getOrNull() }?.takeIf { it.scheme != null && isMediaUrl(it) }
        if (loneUri != null && count < maxMedia) {
            flush()
            addMedia(inlineRedditVideo(loneUri) ?: loneUri)
            continue
        }
        if (text.isNotEmpty()) text.append("\n\n")
        text.append(p)
        val inline = extractMediaLinks(p)
        if (inline.isNotEmpty()) {
            flush()
            inline.forEach(::addMedia)
        }
    }
    flush()
    return out
}

/** [body] without its media-only paragraphs and uploaded-media refs: the text a feed card previews. */
fun textWithoutMedia(body: String): String =
    mediaRefRe.replace(body, "").split(paragraphRe).map { it.trim() }.filter { p ->
        if (p.isEmpty()) return@filter false
        val lone = loneLinkRe.matchEntire(p)?.let { it.groupValues[1].ifEmpty { it.groupValues[2] } } ?: return@filter true
        val u = runCatching { Uri.parse(lone) }.getOrNull()
        !(u?.scheme != null && isMediaUrl(u))
    }.joinToString("\n\n")
