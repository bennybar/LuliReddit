import Foundation

// Detection of media URLs embedded in comment/post markdown, so we can render
// them natively (image/video viewers) instead of kicking out to a browser.

private extension URL {
    /// Path (ignoring the query string), lowercased — reddit appends `?width=…&s=…`.
    var lowerPath: String { path.lowercased() }
}

func isImageUrl(_ u: URL) -> Bool {
    let p = u.lowerPath
    if p.hasSuffix(".jpg") || p.hasSuffix(".jpeg") || p.hasSuffix(".png") || p.hasSuffix(".webp") || p.hasSuffix(".gif") {
        return true
    }
    let host = u.host?.lowercased()
    return host == "i.redd.it" || host == "preview.redd.it" || host == "i.imgur.com"
}

/// A video uploaded inside a text post or comment appears in the text as
/// `reddit.com/link/<post>/video/<id>/player`; it's the v.redd.it video `<id>`.
/// Returns that v.redd.it URL, else nil.
func inlineRedditVideo(_ u: URL) -> URL? {
    guard let host = u.host?.lowercased() else { return nil }
    if host != "reddit.com", !host.hasSuffix(".reddit.com") { return nil }
    let seg = u.segments
    guard seg.first == "link", let i = seg.firstIndex(of: "video"), i + 1 < seg.count else { return nil }
    return URL(string: "https://v.redd.it/\(seg[i + 1])")
}

func isVideoUrl(_ u: URL) -> Bool {
    if inlineRedditVideo(u) != nil { return true }
    let p = u.lowerPath
    if p.hasSuffix(".mp4") || p.hasSuffix(".gifv") { return true }
    return u.host?.lowercased() == "v.redd.it"
}

func isMediaUrl(_ u: URL) -> Bool { isVideoUrl(u) || isImageUrl(u) }

/// True when the URL points at an animated GIF.
func isGifUrl(_ u: URL) -> Bool { u.lowerPath.hasSuffix(".gif") }

private let urlRe = Re(#"https?://[^\s<>)\]"]+"#)

/// Media URLs referenced anywhere in [markdown], de-duplicated, in order.
func extractMediaLinks(_ markdown: String) -> [URL] {
    var out: [URL] = []
    var seen = Set<String>()
    for m in urlRe.allMatches(markdown) {
        // Trim trailing markdown/sentence punctuation the regex may have caught.
        let raw = m.value.trimmingEnd(".,;:!*_")
        guard let uri = URL(string: raw), uri.scheme != nil, isMediaUrl(uri) else { continue }
        let media = inlineRedditVideo(uri) ?? uri
        if seen.insert(media.absoluteString).inserted { out.append(media) }
    }
    return out
}

/// Giphy's animated WebP for a GIF-picker reference (`giphy|<id>` or
/// `giphy|<id>|downsized`) — for when Reddit's `media_metadata` has no usable
/// URL for it. Nil for anything else.
func giphyUrl(_ ref: String) -> String? {
    guard ref.hasPrefix("giphy|") else { return nil }
    let parts = ref.components(separatedBy: "|")
    guard parts.count > 1, !parts[1].isEmpty, parts[1].allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
    return "https://media.giphy.com/media/\(parts[1])/giphy.webp"
}

/// An uploaded image / picker GIF in a body: `![gif](giphy|id|downsized)` / `![img](id)`; its URL is in `media_metadata`.
private let mediaRefRe = Re(#"!\[[^\]]*]\(([^)\s]+)\)"#)

private let gifvRe = Re(#"\.gifv"#, ignoreCase: true)

/// The playable URL for a video link: imgur `.gifv` → `.mp4`; a bare
/// v.redd.it video (or one embedded in a post / comment as
/// `reddit.com/link/…/video/<id>/player`) → its HLS playlist, which the player
/// streams with sound; everything else unchanged.
func resolveVideoUrl(_ url: String) -> String {
    let u = URL(string: url)
    let v = u.flatMap { inlineRedditVideo($0) } ?? (u?.host?.lowercased() == "v.redd.it" ? u : nil)
    if let v, v.segments.count == 1 { return "https://v.redd.it/\(v.segments[0])/HLSPlaylist.m3u8" }
    if url.lowercased().substringBefore("?").hasSuffix(".gifv") { return gifvRe.replace(url, with: ".mp4") }
    return url
}

/// A piece of a post / comment body: markdown text, or one media item shown in its place.
enum BodySegment: Equatable, Sendable {
    case text(String)
    case media(URL)
}

private let paragraphRe = Re(#"\n\s*\n"#)
private let loneLinkRe = Re(#"^!?\[[^\]]*]\((\S+?)\)$|^<?(https?://\S+?)>?$"#)

/// The link a paragraph consists of (a bare URL or `[text](url)`), if that's all it is.
private func loneLink(_ p: String) -> String? {
    guard let m = loneLinkRe.matchEntire(p) else { return nil }
    return m.groups[1].nilIfEmpty ?? m.groups[2]
}

/// Splits [body] into text and media, in reading order. A paragraph that is
/// only a media link (a bare URL, `[text](url)` or an uploaded `![img](id)`
/// from [media]) becomes that media, without its link text; media linked
/// inside a sentence follows its paragraph. At most [maxMedia] media items.
func bodySegments(_ body: String, _ media: [String: String], _ maxMedia: Int) -> [BodySegment] {
    // Uploaded media refs become their own paragraphs holding the real URL.
    let expanded = mediaRefRe.replace(body) { m in
        let ref = m.groups[1]
        if let url = media[ref] ?? giphyUrl(ref) { return "\n\n\(url)\n\n" }
        return m.value
    }
    // No media at all (most bodies): the text exactly as written. Splitting it
    // into paragraphs could only lose markdown structure (indented code, nested
    // list paragraphs, blank lines inside fenced code).
    if expanded == body, extractMediaLinks(body).isEmpty {
        return body.isBlank ? [] : [.text(body)]
    }
    var out: [BodySegment] = []
    var text = ""
    var seen = Set<String>()
    var count = 0
    func flush() {
        // Only surrounding blank lines go: leading spaces are markdown (an
        // indented code block's first line).
        if !text.isBlank { out.append(.text(text.trimming("\n\r").trimmedEnd)) }
        text = ""
    }
    func addMedia(_ u: URL) {
        if count >= maxMedia || !seen.insert(u.absoluteString).inserted { return }
        count += 1
        out.append(.media(u))
    }
    for para in paragraphRe.split(expanded) {
        let p = para.trimmed
        if p.isEmpty { continue }
        let loneUri = loneLink(p).flatMap { URL(string: $0) }.flatMap { $0.scheme != nil && isMediaUrl($0) ? $0 : nil }
        if let loneUri, count < maxMedia {
            flush()
            addMedia(inlineRedditVideo(loneUri) ?? loneUri)
            continue
        }
        if !text.isEmpty { text += "\n\n" }
        let kept = para.trimming("\n\r")
        text += kept.hasPrefix("    ") || kept.hasPrefix("\t") ? kept : kept.trimmedStart
        let inline = extractMediaLinks(p)
        if !inline.isEmpty {
            flush()
            inline.forEach(addMedia)
        }
    }
    flush()
    return out
}

/// [body] without its media-only paragraphs and uploaded-media refs: the text a feed card previews.
func textWithoutMedia(_ body: String) -> String {
    paragraphRe.split(mediaRefRe.replace(body, with: "")).map(\.trimmed).filter { p in
        if p.isEmpty { return false }
        guard let lone = loneLink(p) else { return true }
        guard let u = URL(string: lone), u.scheme != nil else { return true }
        return !isMediaUrl(u)
    }.joined(separator: "\n\n")
}
