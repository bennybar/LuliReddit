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

    var body: some View {
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
                    onTap: { app.navigator.openGallery(images, title: title, initialIndex: $0) },
                    label: { "Image \($0 + 1) of \(images.count)" }
                ) { i in
                    RemoteImage(url: URL(string: images[i].url))
                }
                Label("\(images.count) images · tap one to view", systemImage: "photo.on.rectangle")
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

    @State private var page: Int? = 0

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
                .clipShape(.rect(cornerRadius: 16))
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
                        app.navigator.openGallery(images, title: title, initialIndex: i)
                    } label: {
                        // Gallery images are full size (often 12MP photos): RemoteImage
                        // decodes them to the slot.
                        RemoteImage(url: URL(string: images[i].url))
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
/// scrolling list can do. While covered, inline videos inside don't autoplay
/// (`mediaCovered`).
struct NsfwBlur<Content: View>: View {
    let blur: Bool
    var blurredImageUrl: String? = nil
    var label = "NSFW"
    @ViewBuilder let content: () -> Content

    // Not persisted: like Flutter, an item scrolled away and back is blurred again.
    // That reset also matters to cell reuse, which would otherwise carry a reveal over
    // to the next post in the same cell.
    @State private var revealed = false

    var body: some View {
        Group {
            if !blur || revealed {
                content()
            } else {
                ZStack {
                    // Without a pre-blurred copy, blur the media itself.
                    content()
                        .environment(\.mediaCovered, true)
                        .blur(radius: blurredImageUrl == nil ? 24 : 0)
                    Group {
                        if let blurredImageUrl {
                            RemoteImage(url: URL(string: blurredImageUrl)) { Color.black }
                        }
                    }
                    Color.black.opacity(0.25)
                    VStack(spacing: 8) {
                        Image(systemName: "eye.slash.fill").font(.system(size: 28))
                        Text("\(label) · tap to view").bold()
                    }
                    .foregroundStyle(.white)
                }
                .clipShape(.rect(cornerRadius: 16))
                .contentShape(Rectangle())
                .onTapGesture { revealed = true }
            }
        }
        .onDisappear { revealed = false }
    }
}
