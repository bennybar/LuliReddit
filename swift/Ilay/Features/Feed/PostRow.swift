import SwiftUI

/// What a card's look depends on, besides its post. Rows are rebuilt only when this
/// changes, so a card's body never reads the settings store.
struct FeedRowConfig: Equatable {
    var display: PostDisplay
    var midResThumbnails: Bool
    var blurNsfw: Bool
    var autoplayMedia: Bool
    var feedGalleryCarousel: Bool
    var subredditIcons: Bool
    var trackHistory: Bool
    var dimReadTextOnly: Bool
    var seedColor: Int
    var textScale: Double
    /// The whole list's width.
    var width: CGFloat
    var scale: CGFloat

    /// Default and Mini are plain rows with hairlines; the others are cards on a grouped page.
    var isCarded: Bool { display != .large && display != .mini }
    /// The page margin around a card.
    var cardInset: CGFloat { isCarded ? 12 : 0 }
    /// A card's content margin (a plain row's, from the screen edge).
    var contentInset: CGFloat { isCarded ? 14 : 16 }

    /// How wide media is: Calm cards' runs from one edge of the card to the other.
    var mediaWidth: CGFloat {
        let w = width - 2 * cardInset
        return display == .calmCards ? w : w - 2 * contentInset
    }

    @MainActor static func current(width: CGFloat? = nil) -> FeedRowConfig {
        let s = app.settings.value
        let screen = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.screen
        return FeedRowConfig(
            display: s.postDisplay,
            midResThumbnails: s.midResThumbnails,
            blurNsfw: s.blurNsfw,
            autoplayMedia: s.autoplayMedia,
            feedGalleryCarousel: s.feedGalleryCarousel,
            subredditIcons: s.subredditIcons,
            trackHistory: s.trackHistory,
            dimReadTextOnly: s.dimReadTextOnly,
            seedColor: s.seedColor,
            textScale: s.textScale,
            width: width ?? screen?.bounds.width ?? 402,
            scale: screen?.scale ?? 3
        )
    }
}

/// Feed preview URL, mid-resolution when the data-saver setting is on.
func cardImage(_ p: Post, midRes: Bool) -> String? {
    if let preview = midRes ? (p.previewMedUrl ?? p.previewUrl) : p.previewUrl { return preview }
    // Direct image links (preview.redd.it / i.redd.it / i.imgur.com) carry no
    // preview block — use the URL itself.
    if p.type == .image || p.type == .gif { return p.url }
    return nil
}

/// The image URL a full-width card shows (shared with the list's prefetcher).
func feedImageUrl(_ p: Post, midRes: Bool) -> String? {
    cardImage(p, midRes: midRes) ?? p.gallery.first?.url
}

/// Decode size for a cover-cropped slot: enough for an image of its known shape to still
/// cover the slot, in whole steps so near-identical slots share a cache entry. An image of
/// unknown shape gets the slot's longest side and half again (as `RemoteImage`).
func feedDecodePixels(slot: CGSize, scale: CGFloat, imageWidth: Int? = nil, imageHeight: Int? = nil) -> Int {
    let longest = max(slot.width, slot.height)
    var wanted = longest * 1.5
    if let w = imageWidth, let h = imageHeight, w > 0, h > 0 {
        let cover = max(slot.width / CGFloat(w), slot.height / CGFloat(h))
        // A very long image would need a huge decode just to fill its width: the crop
        // shows a sliver of it anyway.
        wanted = min(CGFloat(max(w, h)) * cover, longest * 2)
    }
    return Int((wanted * scale / 64).rounded(.up)) * 64
}

/// A slot's small floating label ("GIF", "3", "YouTube ↗").
struct MediaPillInfo: Equatable {
    let label: String
    var symbol: String? = nil
    var leading = false
}

/// One card's media, worked out once when the post loads, its slot size fixed so the
/// cell never resizes once images arrive.
enum FeedMedia: Equatable {
    case none
    case image(url: URL?, height: CGFloat, pixels: Int, play: Bool, pill: MediaPillInfo?)
    case video(url: String, poster: String?, height: CGFloat)
    case gallery(carouselHeight: CGFloat?, height: CGFloat?)
    case link(thumb: URL?, thumbPixels: Int, hero: URL?, heroHeight: CGFloat, heroPixels: Int)
    case thumbnail(url: URL?, pixels: Int, symbol: String, play: Bool)
}

/// A piece of a flair, for a row of text and images (`Kotlin's rememberFlairText`).
struct FlairRun: Equatable {
    let text: String?
    let emoji: URL?
}

/// Reuse pools: cells with the same tree of views, so reuse is a cheap update.
enum PostCellKind: Int, CaseIterable {
    case text, image, video, gallery, link, thumbnail
}

/// A post worked out for its card: everything a card's `body` would otherwise format,
/// parse or measure, done once when the posts load.
struct PostRow: Identifiable, Equatable {
    let post: Post
    let config: FeedRowConfig
    let subredditLabel: String
    let authorLabel: String
    let timeLabel: String
    let snippet: String
    let flair: [FlairRun]
    /// A flair with no images gets an icon matching its words in Calm.
    let flairSymbol: String?
    let media: FeedMedia
    let blur: Bool
    let blurLabel: String
    let avatarUrl: URL?
    let avatarPixels: Int
    /// Calm's avatar colour, picked per subreddit so a sub keeps its colour.
    let tone: Int
    /// For You's reason, without a trailing " · r/sub" (Calm's header already has the sub).
    let calmReason: String?
    let canShareMedia: Bool
    let externalVideoLabel: String?
    let prefetch: [Prefetch]

    struct Prefetch: Equatable {
        let url: URL
        let pixels: Int
    }

    var id: String { post.id }

    var kind: PostCellKind {
        switch media {
        case .none: .text
        case .image: .image
        case .video: .video
        case .gallery: .gallery
        case .link: .link
        case .thumbnail: .thumbnail
        }
    }

    static func == (a: PostRow, b: PostRow) -> Bool { a.post == b.post && a.config == b.config }

    @MainActor init(_ p: Post, config c: FeedRowConfig) {
        post = p
        config = c
        subredditLabel = p.subredditPrefixed.isEmpty ? "r/\(p.subreddit)" : p.subredditPrefixed
        authorLabel = "u/\(p.author)"
        timeLabel = timeAgo(p.createdUtc)
        snippet = p.snippet
        var runs: [FlairRun] = []
        for (i, part) in (p.linkFlair?.parts ?? []).enumerated() {
            if let emoji = part.emojiUrl {
                runs.append(FlairRun(text: nil, emoji: URL(string: emoji)))
            } else if let text = part.text {
                // A lone space beside an image is the row's spacing already.
                let tidy = i == 0 || p.linkFlair?.parts[i - 1].emojiUrl != nil ? text.trimmed : text
                if !tidy.isEmpty { runs.append(FlairRun(text: tidy, emoji: nil)) }
            }
        }
        flair = runs
        flairSymbol = p.linkFlair.flatMap { f in runs.contains { $0.emoji != nil } ? nil : Self.flairSymbol(f.text) }

        let over = p.over18 && c.blurNsfw
        blur = over || p.spoiler
        blurLabel = over ? "NSFW" : "Spoiler"
        media = Self.media(p, c, blur: blur)
        let avatarSize: CGFloat = c.display.isCalm ? 36 : 28
        avatarPixels = Int(avatarSize * c.scale)
        avatarUrl = c.subredditIcons ? p.subredditIcon.flatMap(URL.init(string:)) : nil
        // Java's String.hashCode, so Android and iOS agree on a subreddit's colour.
        let hash = p.subreddit.lowercased().utf16.reduce(Int32(0)) { $0 &* 31 &+ Int32($1) }
        tone = ((Int(hash) % 3) + 3) % 3
        calmReason = p.feedReason.map { r in
            for suffix in [" · r/\(p.subreddit)", " · \(p.subredditPrefixed)"] where r.hasSuffix(suffix) {
                return String(r.dropLast(suffix.count))
            }
            return r
        }
        canShareMedia = canShareAsMedia(p)
        externalVideoLabel = p.type == .video && isExternalVideo(p) ? externalVideoSource(p) : nil

        var ahead: [Prefetch] = []
        // Mini cards only show small thumbnails; not worth warming.
        if c.display != .mini {
            switch media {
            case let .image(url?, _, pixels, _, _):
                ahead.append(Prefetch(url: url, pixels: pixels))
            case let .video(_, poster, height):
                // The poster, at the size `InlineVideo`'s RemoteImage will ask for.
                if let poster, let url = URL(string: poster) {
                    let slot = CGSize(width: c.mediaWidth, height: height)
                    ahead.append(Prefetch(url: url, pixels: feedDecodePixels(slot: slot, scale: c.scale)))
                }
            case let .gallery(carouselHeight, height):
                if let first = p.gallery.first, let url = URL(string: first.url) {
                    let slot = carouselHeight.map { CGSize(width: 280, height: $0) }
                        ?? CGSize(width: c.mediaWidth, height: height ?? c.mediaWidth)
                    ahead.append(Prefetch(url: url, pixels: feedDecodePixels(slot: slot, scale: c.scale)))
                }
            case let .link(_, _, hero?, _, pixels):
                ahead.append(Prefetch(url: hero, pixels: pixels))
            default: break
            }
        }
        if let avatarUrl { ahead.append(Prefetch(url: avatarUrl, pixels: avatarPixels)) }
        prefetch = ahead
    }

    @MainActor private static func media(_ p: Post, _ c: FeedRowConfig, blur: Bool) -> FeedMedia {
        let width = c.mediaWidth
        if c.display == .mini {
            if p.type == .selfPost { return .none }
            let raw = cardImage(p, midRes: c.midResThumbnails) ?? p.gallery.first?.url ?? p.thumbnailUrl
            let symbol = blur ? "eye.slash" : p.type == .link ? "link" : "photo"
            // Cover-cropped into a square: 2× leaves room for a 2:1 image.
            return .thumbnail(url: blur ? nil : raw.flatMap(URL.init(string:)), pixels: Int(88 * c.scale * 2), symbol: symbol, play: p.type == .video)
        }
        if p.type == .selfPost { return .none }
        let img = feedImageUrl(p, midRes: c.midResThumbnails)
        if p.type == .link {
            if c.display.isCalm {
                let hero = (cardImage(p, midRes: c.midResThumbnails) ?? p.thumbnailUrl).flatMap(URL.init(string:))
                let height = width / 2
                let pixels = feedDecodePixels(slot: CGSize(width: width, height: height), scale: c.scale, imageWidth: p.previewWidth, imageHeight: p.previewHeight)
                return .link(thumb: nil, thumbPixels: 0, hero: hero, heroHeight: height, heroPixels: pixels)
            }
            return .link(thumb: p.thumbnailUrl.flatMap(URL.init(string:)), thumbPixels: Int(72 * c.scale * 2), hero: nil, heroHeight: 0, heroPixels: 0)
        }
        // The media's own shape where the layout keeps it (galleries often have no
        // preview size: use the first image's). Cards are a fixed banner.
        let first = p.gallery.first
        let w = c.display.isCalm ? (p.previewWidth ?? first?.width) : p.previewWidth
        let h = c.display.isCalm ? (p.previewHeight ?? first?.height) : p.previewHeight
        let fallback: CGFloat = c.display.isCalm ? 16.0 / 10.0 : 16.0 / 9.0
        let aspect = if let w, let h, h > 0 { min(max(CGFloat(w) / CGFloat(h), 0.5), 2) } else { fallback }
        let height = c.display == .card ? 180 : (width / aspect).rounded()

        if p.type == .gallery, !p.gallery.isEmpty {
            // Default gives a gallery its own height (the first image's shape) when one at a time.
            let own: CGFloat? = c.display == .large ? nil : height
            if c.feedGalleryCarousel && p.gallery.count > 1 {
                return .gallery(carouselHeight: min(max(own ?? 300, 220), 340), height: nil)
            }
            return .gallery(carouselHeight: nil, height: own)
        }
        // Inline autoplay for videos (when enabled and not NSFW-blurred).
        if p.type == .video, !blur, c.autoplayMedia, !isExternalVideo(p) {
            let url = postVideoUrl(p)
            if !url.isEmpty, !url.lowercased().hasSuffix(".gif") {
                return .video(url: url, poster: img, height: height)
            }
        }
        let pill: MediaPillInfo? = switch p.type {
        case .gif: MediaPillInfo(label: "GIF", leading: c.display == .large)
        case .gallery: MediaPillInfo(label: "\(p.gallery.count)", symbol: "photo.on.rectangle")
        case .video where isExternalVideo(p): MediaPillInfo(label: externalVideoSource(p), symbol: "arrow.up.right")
        default: nil
        }
        let pixels = feedDecodePixels(slot: CGSize(width: width, height: height), scale: c.scale, imageWidth: w ?? p.previewWidth, imageHeight: h ?? p.previewHeight)
        let play = p.type == .video || (p.type == .gif && c.display != .large)
        return .image(url: img.flatMap(URL.init(string:)), height: height, pixels: pixels, play: play, pill: pill)
    }

    /// A small icon matching common flair words, for a flair with no images.
    private static func flairSymbol(_ text: String) -> String {
        let t = text.lowercased()
        if t.contains("discuss") { return "bubble.left" }
        if t.contains("question") || t.contains("help") { return "questionmark.circle" }
        if t.contains("news") { return "newspaper" }
        if t.contains("meme") || t.contains("humor") || t.contains("funny") { return "face.smiling" }
        if t == "oc" || t.contains("image") || t.contains("photo") || t.contains("art") { return "photo" }
        if t.contains("video") { return "play" }
        return "tag"
    }
}

/// The posts a feed shows of what it has loaded (Kotlin's `FeedList`). Its inputs are
/// compared, so it's only worked out again when one of them changes.
struct FeedVisibility: Equatable {
    var posts: [Post]
    /// Auto-hide already-read items in the For You feed (live: updates when history
    /// changes). Only watched while the option is on. Not in Reddit Home: its
    /// recommended posts carry Reddit's reason too, and opening one made it vanish on return.
    var seen: Set<String>?
    /// Posts hidden (Hide / swipe-to-hide).
    var hiddenIds: Set<String>
    /// Home / For You: posts dismissed with the "Dismiss" swipe (kept a day).
    var dismissedIds: Set<String>
    /// Subreddits hidden for 7 days: anywhere on the front page (Home, For You and Best / Hot / New).
    var hiddenSubs: Set<String>
    var filters: ContentFilters
    /// A subreddit feed still shows that subreddit's own posts.
    var viewing: String?

    func visible() -> [Post] {
        var list = posts
        if let seen { list = list.filter { !($0.feedReason != nil && seen.contains($0.id)) } }
        if !hiddenIds.isEmpty { list = list.filter { !hiddenIds.contains($0.id) } }
        if !dismissedIds.isEmpty { list = list.filter { !dismissedIds.contains($0.id) } }
        if !hiddenSubs.isEmpty { list = list.filter { !hiddenSubs.contains($0.subreddit.lowercased()) } }
        // User content filters (keywords / domains / flairs / subreddits).
        if !filters.isEmpty { list = list.filter { !filters.hides($0, viewingSubreddit: viewing) } }
        // A page boundary can repeat a post that moved up meanwhile; the list needs unique keys.
        var ids = Set<String>()
        return list.filter { ids.insert($0.id).inserted }
    }
}

/// When a card has really been seen. A card flung past mid-scroll wasn't: counting it
/// would bury posts the user never had a chance to read. Only a card that sits ≥60%
/// visible for a second counts as shown, once per time it comes into view.
struct VisibilityDwell {
    var minDuration: TimeInterval = 1
    var minFraction = 0.6
    private var since: [String: TimeInterval] = [:]
    private var fired: Set<String> = []

    /// `fractions`: how visible each card on screen is. Returns those seen just now.
    mutating func update(fractions: [String: Double], now: TimeInterval) -> [String] {
        let visible = fractions.filter { $0.value >= minFraction }.keys
        for id in since.keys where fractions[id].map({ $0 < minFraction }) ?? true {
            since[id] = nil
            fired.remove(id)
        }
        var seen: [String] = []
        for id in visible {
            let start = since[id] ?? now
            since[id] = start
            if now - start >= minDuration, fired.insert(id).inserted { seen.append(id) }
        }
        return seen
    }
}
