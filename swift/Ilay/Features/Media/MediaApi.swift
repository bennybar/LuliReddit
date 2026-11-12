import SwiftUI

/// A video post's playable URL, without any network lookup: Reddit's own stream when it
/// hosts the video, a direct file link as-is, and otherwise Reddit's mp4 copy of the
/// embed (e.g. RedGifs), whose own URL is a web page.
func postVideoUrl(_ p: Post) -> String {
    if let own = p.hlsUrl ?? p.fallbackVideoUrl { return own }
    let direct = resolveVideoUrl(p.url)
    if let uri = URL(string: direct), isVideoUrl(uri) { return direct }
    return p.gifMp4Url ?? direct
}

/// A video post Ilay can't play itself: a YouTube / Vimeo / other embed with no
/// Reddit-hosted copy or direct file. It opens in its own app or the browser (it used
/// to land on a "can't be played" error screen).
func isExternalVideo(_ p: Post) -> Bool {
    if p.type != .video || p.hlsUrl != nil || p.fallbackVideoUrl != nil || p.gifMp4Url != nil { return false }
    if Redgifs.id(p.url) != nil { return false }
    guard let u = URL(string: resolveVideoUrl(p.url)) else { return true }
    return !isVideoUrl(u)
}

/// Where an external video plays, for its feed label ("YouTube").
func externalVideoSource(_ p: Post) -> String {
    var d = p.domain.lowercased()
    if d.hasPrefix("www.") { d.removeFirst(4) }
    if d.hasPrefix("m.") { d.removeFirst(2) }
    if d == "youtu.be" || d.hasSuffix("youtube.com") { return "YouTube" }
    if d.hasSuffix("vimeo.com") { return "Vimeo" }
    if d.hasSuffix("twitch.tv") { return "Twitch" }
    if d.hasSuffix("streamable.com") { return "Streamable" }
    return d.isEmpty ? "Video" : d
}

/// Opens a video post full-screen. RedGifs clips are resolved to their HD file (with
/// sound) first, falling back to Reddit's silent mp4 copy.
@MainActor func openPostVideo(_ nav: AppNavigator, _ post: Post) async {
    if isExternalVideo(post) {
        nav.openExternal(post.url)
        return
    }
    var src = postVideoUrl(post)
    var download = post.fallbackVideoUrl ?? src
    if post.hlsUrl == nil, post.fallbackVideoUrl == nil, Redgifs.id(post.url) != nil,
       let hd = await Redgifs.shared.resolve(post.url) {
        src = hd
        download = hd
    }
    nav.openVideo(src, title: post.title, downloadUrl: download, externalUrl: post.url)
}

/// Downloads a media file to Photos' "Ilay" album, with a cancellable progress dialog
/// showing downloaded / total size.
@MainActor func saveMediaToGallery(_ url: String, isVideo: Bool) async {
    await saveMedia(url, isVideo: isVideo)
}

/// A gallery as a carousel (#30), for the post screen: a large image with the next ones
/// peeking beside it, each opening the full-screen viewer at that image. Feeds use it
/// too unless Settings › Gallery carousel in feeds is off (then `GalleryCarousel`, one
/// image at a time). Kotlin's Material 3 carousel, kept as is on iOS.
struct GalleryM3Carousel: View {
    let images: [GalleryImage]
    var title: String? = nil
    var height: CGFloat = 300
    /// A spoiler / NSFW gallery's label (#165): each image gets its own cover, so you
    /// can still swipe through them; revealing one reveals them all.
    var cover: String? = nil

    @State private var revealed = false

    var body: some View {
        let covered = cover != nil && !revealed
        if !images.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                KeylineCarousel(
                    items: Array(images.indices),
                    height: height,
                    // One big image, a medium and a small one peeking.
                    keylines: { w in
                        let small: CGFloat = 40, medium = w * 0.2
                        return [w - medium - small - 16, medium, small]
                    },
                    onTap: { if covered { revealed = true } else { app.navigator.openGallery(images, title: title, initialIndex: $0) } },
                    label: { "Image \($0 + 1) of \(images.count)" }
                ) { i in
                    RemoteImage(url: URL(string: images[i].url)).zoomSource()
                        // Just the eye: the carousel lays every image out full size and masks
                        // the narrow ones, so a label would be cut off; the caption says it.
                        .overlay { if covered, let cover { MediaCover(label: cover, iconOnly: true) } }
                }
                Label(covered ? "\(cover ?? "") · \(images.count) images · tap one to view" : "\(images.count) images · tap one to view", systemImage: "photo.on.rectangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
        }
    }
}

/// An inline, swipeable gallery preview with a page counter and dot indicator. Tapping
/// any image opens the full-screen viewer at that index. With `height` it's a
/// fixed-height (cover-cropped) banner instead of sizing to the first image's aspect ratio.
struct GalleryCarousel: View {
    let images: [GalleryImage]
    var title: String? = nil
    var height: CGFloat? = nil
    var radius: CGFloat = 16
    /// A spoiler / NSFW gallery's label (#165): each image gets its own cover, so you
    /// can still swipe through them; revealing one reveals them all.
    var cover: String? = nil

    @State private var page: Int? = 0
    @State private var revealed = false

    private var aspect: CGFloat {
        guard let first = images.first, let w = first.width, let h = first.height, h > 0 else { return 16.0 / 9.0 }
        return min(max(CGFloat(w) / CGFloat(h), 0.5), 2)
    }

    var body: some View {
        if !images.isEmpty {
            pager
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .aspectRatio(height == nil ? aspect : nil, contentMode: .fit)
                .clipShape(.rect(cornerRadius: radius))
                .overlay(alignment: .topTrailing) {
                    Label("\((page ?? 0) + 1)/\(images.count)", systemImage: "photo.on.rectangle")
                        .labelStyle(.titleAndIcon)
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.54), in: .capsule)
                        .padding(8)
                }
                .overlay(alignment: .bottom) {
                    if images.count > 1 {
                        HStack(spacing: 4) {
                            ForEach(images.indices, id: \.self) { i in
                                Circle()
                                    .fill(i == (page ?? 0) ? Color.white : Color.white.opacity(0.54))
                                    .frame(width: 6, height: 6)
                            }
                        }
                        .padding(.bottom, 8)
                        .allowsHitTesting(false)
                    }
                }
        }
    }

    private var pager: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(images.indices, id: \.self) { i in
                    Button {
                        if cover != nil && !revealed { revealed = true } else { app.navigator.openGallery(images, title: title, initialIndex: i) }
                    } label: {
                        // Gallery images are full size (often 12MP photos): RemoteImage
                        // decodes them to the slot.
                        RemoteImage(url: URL(string: images[i].url)).zoomSource()
                            .overlay { if let cover, !revealed { MediaCover(label: cover) } }
                    }
                    .buttonStyle(.plain)
                    .containerRelativeFrame(.horizontal)
                    .id(i)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $page)
    }
}

/// Wraps media with a blur + "NSFW" label until tapped to reveal. When `blur` is false it
/// renders `content` unchanged.
///
/// Given Reddit's pre-blurred copy (`blurredImageUrl`) it just draws that: a live blur
/// re-renders the media on every frame, which is one of the most expensive things a
/// scrolling list can do. Without one it covers the media with a solid fill, for the
/// same reason. While covered, inline videos inside don't autoplay (`mediaCovered`).
///
/// `id` names the item shown (a post's id in a feed cell): a reveal belongs to that
/// id only, so a reused cell showing another post starts covered in the very same
/// frame, without `.id(...)` tearing down (and reloading) the media inside.
struct NsfwBlur<Content: View>: View {
    let blur: Bool
    var blurredImageUrl: String? = nil
    var label = "NSFW"
    var id = ""
    /// The media's own corner radius, so the cover's corners match it (#165).
    var radius: CGFloat = 16
    @ViewBuilder let content: () -> Content

    // Not persisted: like Flutter, an item scrolled away and back is blurred again.
    // Keyed by `id` rather than a plain Bool: cell reuse would otherwise carry a
    // reveal over to the next post in the same cell (and onChange would let it show
    // uncovered for a frame).
    @State private var revealedId: String?

    var body: some View {
        Group {
            if !blur || revealedId == id {
                content()
            } else {
                ZStack {
                    // Kept (hidden) for its size, and so the reveal paints at once.
                    content()
                        .environment(\.mediaCovered, true)
                        .hidden()
                    Group {
                        if let blurredImageUrl {
                            RemoteImage(url: URL(string: blurredImageUrl)) { Color.black }
                        } else {
                            Color(.darkGray)
                        }
                    }
                    Color.black.opacity(0.25)
                    CoverLabel(label: label)
                }
                .clipShape(.rect(cornerRadius: radius))
                .contentShape(Rectangle())
                .onTapGesture { revealedId = id }
            }
        }
        .onDisappear { revealedId = nil }
    }
}

/// The eye and "NSFW · tap to view" on covered media; just the eye where it doesn't fit.
private struct CoverLabel: View {
    let label: String
    var iconOnly = false

    var body: some View {
        if iconOnly {
            Image(systemName: "eye.slash.fill").font(.system(size: 28)).foregroundStyle(.white)
        } else {
            full
        }
    }

    private var full: some View {
        ViewThatFits {
            VStack(spacing: 8) {
                Image(systemName: "eye.slash.fill").font(.system(size: 28))
                Text("\(label) · tap to view").bold().multilineTextAlignment(.center)
            }
            Image(systemName: "eye.slash.fill").font(.system(size: 22))
        }
        .foregroundStyle(.white)
        .padding(8)
    }
}

/// A gallery image's cover (#165): a solid fill (a live blur per image would cost every
/// scroll frame) with the label.
private struct MediaCover: View {
    let label: String
    var iconOnly = false

    var body: some View {
        ZStack {
            Color(.darkGray)
            Color.black.opacity(0.25)
            CoverLabel(label: label, iconOnly: iconOnly)
        }
    }
}
