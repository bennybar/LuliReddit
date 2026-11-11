import AVFoundation
import SwiftUI

/// The media posts of a feed for the media browser (#103), in the feed's order and with
/// its filters (it's given the posts the list shows), from the post at the top of the
/// screen on. New pages only add to it: posts it already knows are never shown twice,
/// and posts the list drops meanwhile (hidden, auto-hidden as read) stay where they are.
struct MediaBrowseFeed: Equatable {
    /// What a page shows: an image (a pager of one), a gallery, or a clip.
    enum Media: Equatable {
        case images([String])
        /// `redgifs`: look up its HD file (with sound) first, as `openPostVideo` does.
        case video(String, redgifs: Bool)
    }

    /// Pages in a row with no media before it stops asking for more: a feed of text posts
    /// would otherwise be fetched to its end.
    static let maxBarrenPages = 5

    private(set) var posts: [Post]
    private var known: Set<String>
    private var loaded: Int
    private var barren = 0

    /// `visible`: the posts the list shows; `loaded`: how many the feed has fetched, filtered or not.
    init(visible: [Post], loaded: Int, startId: String?) {
        let start = startId.flatMap { id in visible.firstIndex { $0.id == id } } ?? 0
        posts = visible[start...].filter { Self.media($0) != nil }
        known = Set(visible.map(\.id))
        self.loaded = loaded
    }

    /// Takes in a new state of the list; true when anything changed.
    @discardableResult mutating func update(_ visible: [Post], loaded: Int) -> Bool {
        let fresh = visible.filter { !known.contains($0.id) }
        known.formUnion(fresh.map(\.id))
        let media = fresh.filter { Self.media($0) != nil }
        posts += media
        let grew = loaded > self.loaded
        self.loaded = loaded
        if !media.isEmpty {
            barren = 0
        } else if grew {
            barren += 1
        }
        return !media.isEmpty || grew
    }

    /// Whether to ask the feed for another page with `index` on screen: three pages from
    /// the end, so a page arrives before a quick swiper gets there.
    func wantsMore(at index: Int) -> Bool {
        index >= posts.count - 3 && barren < Self.maxBarrenPages
    }

    /// nil: nothing to browse (text, links, YouTube and other videos that play elsewhere).
    /// The same media as tapping the post opens (`PostActions.openMedia`).
    static func media(_ p: Post) -> Media? {
        switch p.type {
        case .image: .images([p.previewUrl ?? p.url])
        // Reddit's mp4 variant (small, loops); else the animated .gif.
        case .gif: p.gifMp4Url.map { .video($0, redgifs: false) } ?? .images([p.url])
        case .gallery: p.gallery.isEmpty ? nil : .images(p.gallery.map(\.url))
        case .video:
            isExternalVideo(p) ? nil : .video(postVideoUrl(p), redgifs: p.hlsUrl == nil && p.fallbackVideoUrl == nil && Redgifs.id(p.url) != nil)
        case .link, .selfPost: nil
        }
    }
}

/// The media browser's state: the posts, the page on screen, and the one player its
/// video pages share.
@MainActor @Observable final class MediaBrowserModel {
    private(set) var feed: MediaBrowseFeed
    /// The page that settled last.
    private(set) var index = 0
    /// The pages' taps (overlay on / off), zoom (no paging while zoomed) and edge swipe (close).
    let dismiss: DismissState
    var muted = app.settings.value.viewerMuted
    private(set) var playing = false
    /// Stopped at the end (Loop videos off, #156): the play button replays.
    private(set) var ended = false
    /// The clip on screen starts over at the end: a GIF, or Loop videos on (#156).
    @ObservationIgnored private var loops = true
    /// Each gallery's page, so a gallery swiped back to opens where it was left.
    var galleryPages: [String: Int] = [:]
    /// NSFW / spoiler posts tapped to view; like the feed, only while the browser is open.
    var revealed: Set<String> = []
    var titleExpanded = false

    @ObservationIgnored let player = AVPlayer()
    /// Moves the pager (VoiceOver's next / previous post); set by the pager.
    @ObservationIgnored var scrollTo: (Int) -> Void = { _ in }
    @ObservationIgnored private let controller: FeedController
    @ObservationIgnored private let onClosed: (String?) -> Void
    /// The post it opened on: closed there, the list is already in place.
    @ObservationIgnored private let startPostId: String?
    @ObservationIgnored private weak var host: UIViewController?
    /// A clip is playing, or meant to be: what returning from the background restores.
    @ObservationIgnored private var wanted = false
    @ObservationIgnored private var resumeAfterBackground = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var observation: NSKeyValueObservation?

    var post: Post? { feed.posts.indices.contains(index) ? feed.posts[index] : nil }

    var isVideo: Bool {
        if let post, case .video = MediaBrowseFeed.media(post) { true } else { false }
    }

    /// Still looking for media further down the feed.
    var searching: Bool { feed.wantsMore(at: index) && controller.ui.state?.hasMore == true }

    /// `onClosed` gets the post on screen at the end, for the list to scroll to; nil when
    /// that's still the one it opened on.
    init(visible: [Post], loaded: Int, startId: String?, controller: FeedController, onClosed: @escaping (String?) -> Void) {
        let feed = MediaBrowseFeed(visible: visible, loaded: loaded, startId: startId)
        self.feed = feed
        startPostId = feed.posts.first?.id
        self.controller = controller
        self.onClosed = onClosed
        var closer: (() -> Void)?
        dismiss = DismissState { closer?() }
        closer = { [weak self] in self?.close() }
        player.actionAtItemEnd = .none
        observers.append(NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, note.object as? AVPlayerItem === self.player.currentItem else { return }
                if self.loops {
                    self.player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                } else {
                    self.wanted = false
                    self.player.pause()
                    self.ended = true
                }
            }
        })
        observation = player.observe(\.timeControlStatus, options: [.initial]) { [weak self] player, _ in
            let on = player.timeControlStatus != .paused
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.playing = on } }
        }
        let center = NotificationCenter.default
        // Pause in the background; resume if it was playing.
        observers.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.resumeAfterBackground = self.wanted
                self.player.pause()
            }
        })
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                if self?.resumeAfterBackground == true { self?.player.play() }
            }
        })
        observers.append(observeAudioInterruptions(
            muted: { [weak self] in self?.muted ?? true },
            resume: { [weak self] in
                if self?.wanted == true { self?.player.play() }
            }
        ))
    }

    /// Over the whole app, like the other viewers.
    func present() {
        // The feed's own clip pauses beneath.
        app.media.inlinePlayer.setCovered(true)
        let host = MediaViewerController(root: AnyView(MediaBrowser(model: self))) { [self] in released() }
        self.host = host
        topViewController()?.present(host, animated: true)
    }

    /// `then` runs once it's gone (opening the thread, the post's menu).
    func close(then next: (() -> Void)? = nil) {
        guard let host, host.presentingViewController != nil else { return }
        host.dismiss(animated: true) { next?() }
    }

    private func released() {
        stopVideo()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        observation = nil
        app.media.inlinePlayer.setCovered(false)
        // Scrolling the list to the post it opened on would only jump it, by the
        // gap above the card, after the browser has gone (#107).
        onClosed(post?.id == startPostId ? nil : post?.id)
    }

    /// The list changed under the browser (a new page, mostly).
    func feedChanged(_ visible: [Post], loaded: Int) {
        var next = feed
        if next.update(visible, loaded: loaded) { feed = next }
        askForMore()
    }

    private func askForMore() {
        guard feed.wantsMore(at: index), let s = controller.ui.state, s.hasMore, !s.loadingMore else { return }
        controller.loadMore()
    }

    /// A page came to rest on screen: it counts as viewing that media.
    func settled(_ i: Int) {
        index = i
        titleExpanded = false
        askForMore()
        guard let post else { return }
        // Viewing media is engagement for For You, as when it's opened from the feed.
        app.feed.engines?.learner.viewMedia(post)
        // A page on screen is certainly seen: "Mark read on scroll" counts it, as in the feed.
        let s = app.settings.value
        if s.markReadOnScroll, s.trackHistory { app.history.markViewed(post) }
    }

    func play(_ asset: AVURLAsset) {
        loops = post?.type == .gif || app.settings.value.loopVideos
        ended = false
        player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
        player.isMuted = muted
        wanted = true
        // Muted, it leaves the audio session alone, so the user's music keeps playing.
        VideoAudio.shared.setAudible(!muted, player: player) { [weak self] in
            if self?.wanted == true { self?.player.play() }
        }
    }

    func stopVideo() {
        wanted = false
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    func togglePlay() {
        if ended {
            ended = false
            wanted = true
            player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            player.play()
            return
        }
        if player.rate != 0 {
            wanted = false
            player.pause()
        } else if player.currentItem != nil {
            wanted = true
            player.play()
        }
    }

    func toggleMute() {
        muted.toggle()
        player.isMuted = muted
        // Muted gives the session back, so the user's music returns.
        VideoAudio.shared.setAudible(!muted, player: player) { [weak self] in
            if self?.wanted == true { self?.player.play() }
        }
    }
}

// MARK: - Pages (UIKit)

/// Vertical paging: swipe up for the next post, down for the one before. Keeps the page
/// on screen and its two neighbours alive (loaded, so a swipe lands on a ready page) and
/// nothing further, as `ZoomablePager` does sideways.
final class MediaBrowserPager: UIView, UIScrollViewDelegate {
    private let model: MediaBrowserModel
    private let scroll = UIScrollView()
    private var pages: [Int: MediaBrowserPage] = [:]
    private var index: Int
    private var settledAt: Int?
    private var count = 0
    private var laidOutFor = CGSize.zero

    init(model: MediaBrowserModel) {
        self.model = model
        index = model.index
        super.init(frame: .zero)
        backgroundColor = .black
        scroll.delegate = self
        scroll.isPagingEnabled = true
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.scrollsToTop = false
        addSubview(scroll)
        model.scrollTo = { [weak self] in self?.go(to: $0) }
        track()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// New posts, and zoom: paging is off while an image is zoomed, so its pan is the zoom's.
    private func track() {
        withObservationTracking {
            _ = model.feed.posts.count
            _ = model.dismiss.zoomed
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.modelChanged()
                    self?.track()
                }
            }
        }
    }

    private func modelChanged() {
        scroll.isScrollEnabled = !model.dismiss.zoomed
        let n = model.feed.posts.count
        guard n != count, laidOutFor.height > 0 else { return }
        count = n
        scroll.contentSize = CGSize(width: laidOutFor.width, height: laidOutFor.height * CGFloat(n))
        tile()
        settle() // The first posts may only now have come.
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != laidOutFor, bounds.width > 0 else { return }
        laidOutFor = bounds.size
        count = model.feed.posts.count
        // Rotation: same page, new geometry. Setting the offset below mustn't read as a swipe.
        scroll.delegate = nil
        scroll.frame = bounds
        scroll.contentSize = CGSize(width: laidOutFor.width, height: laidOutFor.height * CGFloat(count))
        scroll.contentOffset = CGPoint(x: 0, y: laidOutFor.height * CGFloat(index))
        scroll.delegate = self
        for (i, page) in pages { page.frame = frame(ofPage: i) }
        tile()
        settle()
    }

    private func frame(ofPage i: Int) -> CGRect {
        CGRect(x: 0, y: laidOutFor.height * CGFloat(i), width: laidOutFor.width, height: laidOutFor.height)
    }

    private func tile() {
        guard count > 0 else { return }
        index = min(index, count - 1)
        let wanted = max(index - 1, 0)...min(index + 1, count - 1)
        for (i, page) in pages where !wanted.contains(i) {
            page.isCurrent = false
            page.removeFromSuperview()
            pages[i] = nil
        }
        // Decoded to the screen, not the photo's full size.
        let pixels = Int(max(laidOutFor.width, laidOutFor.height) * traitCollection.displayScale)
        for i in wanted where pages[i] == nil {
            let page = MediaBrowserPage(post: model.feed.posts[i], model: model, pixels: pixels)
            page.frame = frame(ofPage: i)
            scroll.addSubview(page)
            pages[i] = page
        }
    }

    /// The page at rest: its clip plays, the others stop.
    private func settle() {
        guard index < count else { return }
        for (i, page) in pages where i != index { page.isCurrent = false }
        if settledAt != index {
            settledAt = index
            model.settled(index)
        }
        pages[index]?.isCurrent = true
    }

    private func go(to i: Int) {
        guard (0..<count).contains(i), i != index, laidOutFor.height > 0 else { return }
        scroll.setContentOffset(CGPoint(x: 0, y: laidOutFor.height * CGFloat(i)), animated: !UIAccessibility.isReduceMotionEnabled)
        if UIAccessibility.isReduceMotionEnabled { settle() }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard laidOutFor.height > 0, count > 0 else { return }
        let page = min(max(Int((scrollView.contentOffset.y / laidOutFor.height).rounded()), 0), count - 1)
        guard page != index else { return }
        index = page
        tile()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { settle() }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { settle() }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) { settle() }

    // VoiceOver's three-finger swipe moves between posts.
    override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
        let next = switch direction {
        case .up, .next: index + 1
        case .down, .previous: index - 1
        default: index
        }
        guard (0..<count).contains(next), next != index else { return false }
        go(to: next)
        UIAccessibility.post(notification: .pageScrolled, argument: "Post \(next + 1) of \(count)")
        return true
    }
}

/// One post's page: its images (zoomable; a gallery pages sideways) or its clip, under
/// a cover while it's NSFW (with Blur NSFW on) or a spoiler, as in the feed.
final class MediaBrowserPage: UIView {
    let post: Post
    private let model: MediaBrowserModel
    private var video: MediaBrowserVideo?
    private var cover: UIView?

    var isCurrent = false {
        didSet { video?.setActive(isCurrent && cover == nil) }
    }

    init(post: Post, model: MediaBrowserModel, pixels: Int) {
        self.post = post
        self.model = model
        super.init(frame: .zero)
        clipsToBounds = true
        let content: DismissableContentView
        switch MediaBrowseFeed.media(post) {
        case let .images(urls):
            content = ZoomablePager(urls: urls, initialIndex: model.galleryPages[post.id] ?? 0, state: model.dismiss, maxPixelSize: pixels) { [weak model] page in
                model?.galleryPages[post.id] = page
            }
        case let .video(url, redgifs):
            let clip = MediaBrowserVideo(post: post, url: url, redgifs: redgifs, model: model, pixels: pixels)
            video = clip
            content = clip
        case nil:
            content = DismissableContentView(state: model.dismiss)
        }
        // Vertical swipes page here, so they can't also be the swipe-to-dismiss.
        content.pan.isEnabled = false
        content.frame = bounds
        content.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(content)
        let nsfw = post.over18 && app.settings.value.blurNsfw
        if nsfw || post.spoiler, !model.revealed.contains(post.id) { addCover(label: nsfw ? "NSFW" : "Spoiler") }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func addCover(label: String) {
        let cover = UIView(frame: bounds)
        cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cover.backgroundColor = .darkGray
        // Reddit's pre-blurred copy when there is one: a live blur would redraw the media.
        if let url = post.blurredPreviewUrl.flatMap(URL.init(string:)) {
            let blurred = UIImageView(frame: cover.bounds)
            blurred.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            blurred.contentMode = .scaleAspectFill
            cover.addSubview(blurred)
            Task { [weak blurred] in blurred?.image = await ImageLoader.shared.image(url: url, maxPixelSize: 400) }
        }
        let dim = UIView(frame: cover.bounds)
        dim.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dim.backgroundColor = UIColor.black.withAlphaComponent(0.25)
        cover.addSubview(dim)
        let icon = UIImageView(image: UIImage(systemName: "eye.slash.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 28)))
        let text = UILabel()
        text.text = "\(label) · tap to view"
        text.font = .preferredFont(forTextStyle: .headline)
        text.adjustsFontForContentSizeCategory = true
        let stack = UIStackView(arrangedSubviews: [icon, text])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 8
        stack.tintColor = .white
        text.textColor = .white
        stack.translatesAutoresizingMaskIntoConstraints = false
        cover.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: cover.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: cover.centerYAnchor),
        ])
        cover.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(reveal)))
        cover.isAccessibilityElement = true
        cover.accessibilityLabel = "\(label), hidden"
        cover.accessibilityHint = "Double-tap to view."
        cover.accessibilityTraits = .button
        addSubview(cover)
        self.cover = cover
    }

    @objc private func reveal() {
        cover?.removeFromSuperview()
        cover = nil
        model.revealed.insert(post.id)
        video?.setActive(isCurrent)
    }
}

/// A clip's page: its preview image until the shared player is on it and has a frame.
/// Gets its stream ready ahead of its turn (RedGifs' HD file found, the playlist read).
final class MediaBrowserVideo: DismissableContentView {
    private let model: MediaBrowserModel
    private let playerLayer = AVPlayerLayer()
    private let poster = UIImageView()
    private var asset: AVURLAsset?
    private var active = false
    private var tasks: [Task<Void, Never>] = []
    private var readyObservation: NSKeyValueObservation?

    init(post: Post, url: String, redgifs: Bool, model: MediaBrowserModel, pixels: Int) {
        self.model = model
        super.init(state: model.dismiss)
        poster.contentMode = .scaleAspectFit
        contentRoot.addSubview(poster)
        playerLayer.videoGravity = .resizeAspect
        contentRoot.layer.addSublayer(playerLayer)
        if let posterUrl = post.previewUrl.flatMap(URL.init(string:)) {
            if let hit = ImageLoader.shared.cached(url: posterUrl, maxPixelSize: pixels) {
                poster.image = hit
            } else {
                tasks.append(Task { [weak self] in
                    let image = await ImageLoader.shared.image(url: posterUrl, maxPixelSize: pixels)
                    if !Task.isCancelled { self?.poster.image = image }
                })
            }
        }
        readyObservation = playerLayer.observe(\.isReadyForDisplay) { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.updatePoster() } }
        }
        tasks.append(Task { [weak self] in
            var src = url
            if redgifs, let hd = await Redgifs.shared.resolve(post.url) { src = hd }
            guard let asset = videoAsset(src) else { return }
            _ = try? await asset.load(.isPlayable)
            guard let self, !Task.isCancelled else { return }
            self.asset = asset
            if self.active { self.model.play(asset) }
        })
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { tasks.forEach { $0.cancel() } }

    override func layoutSubviews() {
        super.layoutSubviews()
        poster.frame = contentRoot.bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = contentRoot.bounds
        CATransaction.commit()
    }

    private func updatePoster() {
        poster.isHidden = playerLayer.player != nil && playerLayer.isReadyForDisplay
    }

    /// On screen and uncovered: the shared player moves here and plays (or as soon as the
    /// stream is ready). Off: it stops, so only one clip ever plays.
    func setActive(_ on: Bool) {
        guard on != active else { return }
        active = on
        if on {
            playerLayer.player = model.player
            if let asset { model.play(asset) }
        } else {
            model.stopVideo()
            playerLayer.player = nil
        }
        updatePoster()
    }
}

private struct MediaBrowserPages: UIViewRepresentable {
    let model: MediaBrowserModel

    func makeUIView(context: Context) -> MediaBrowserPager { MediaBrowserPager(model: model) }

    func updateUIView(_ view: MediaBrowserPager, context: Context) {}
}

// MARK: - Overlay (SwiftUI)

/// Full-screen, vertically paged media from a feed (#103): every image, GIF, gallery and
/// clip in it, with the post's details and actions over it. Tap to hide them.
struct MediaBrowser: View {
    let model: MediaBrowserModel

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    private var controls: Bool { model.dismiss.showControls || voiceOver }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            MediaBrowserPages(model: model).ignoresSafeArea()
            if model.feed.posts.isEmpty {
                if model.searching {
                    ProgressView().tint(.white).controlSize(.large)
                } else {
                    Label("No images or videos below", systemImage: "photo.on.rectangle.angled")
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            MediaBrowserOverlay(model: model)
                .opacity(controls ? 1 : 0)
                .allowsHitTesting(controls)
        }
        .animation(.easeOut(duration: 0.15), value: controls)
        .accessibilityAction(.escape) { model.close() }
    }
}

private struct MediaBrowserOverlay: View {
    let model: MediaBrowserModel

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 0)
            if let post = model.post { details(post) }
        }
        .background(alignment: .top) {
            LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 120)
                .padding(.top, -60)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .background(alignment: .bottom) {
            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                .frame(height: 260)
                .padding(.bottom, -60)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    private var counter: String? {
        guard let post = model.post, post.type == .gallery, post.gallery.count > 1 else { return nil }
        return "\((model.galleryPages[post.id] ?? 0) + 1) / \(post.gallery.count)"
    }

    private var topBar: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                ViewerButton(icon: "xmark", label: "Close") { model.close() }
                Text(counter ?? "")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 3)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(counter.map { "Image \($0.replacingOccurrences(of: " / ", with: " of "))" } ?? "")
                if model.isVideo {
                    ViewerButton(icon: model.ended ? "arrow.counterclockwise" : model.playing ? "pause.fill" : "play.fill", label: model.ended ? "Replay" : model.playing ? "Pause" : "Play", action: model.togglePlay)
                    ViewerButton(icon: model.muted ? "speaker.slash.fill" : "speaker.wave.2.fill", label: model.muted ? "Unmute" : "Mute", action: model.toggleMute)
                } else {
                    // Keeps the counter centred.
                    Color.clear.frame(width: 44, height: 44)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    private func details(_ post: Post) -> some View {
        let a = PostActions(post: post)
        let ov = app.postOverrides.effective(post)
        let colors = IlayTheme.voteColors(dark: true)
        let tick = { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        let subreddit = post.subredditPrefixed.isEmpty ? "r/\(post.subreddit)" : post.subredditPrefixed
        return HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(subreddit) · u/\(post.author) · \(timeAgo(post.createdUtc))")
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                Text(post.title)
                    .font(.subheadline)
                    .lineLimit(model.titleExpanded ? 12 : 3)
                    .onTapGesture { withAnimation(.snappy) { model.titleExpanded.toggle() } }
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.6), radius: 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Swipe up or down with three fingers for the next or previous post.")
            .accessibilityAction(named: "Next post") { model.scrollTo(model.index + 1) }
            .accessibilityAction(named: "Previous post") { model.scrollTo(model.index - 1) }
            .accessibilityAction(named: model.titleExpanded ? "Collapse title" : "Expand title") { model.titleExpanded.toggle() }

            GlassEffectContainer(spacing: 10) {
                VStack(spacing: 6) {
                    ViewerButton(icon: "arrow.up", label: ov.likes == true ? "Remove upvote" : "Upvote", color: ov.likes == true ? colors.up : .white) {
                        tick()
                        a.vote(1)
                    }
                    .accessibilityAddTraits(ov.likes == true ? .isSelected : [])
                    Text(compactNumber(ov.score))
                        .font(.footnote.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(ov.likes == true ? colors.up : ov.likes == false ? colors.down : .white)
                        .shadow(color: .black.opacity(0.6), radius: 3)
                        .accessibilityLabel("Score \(ov.score)")
                    ViewerButton(icon: "arrow.down", label: ov.likes == false ? "Remove downvote" : "Downvote", color: ov.likes == false ? colors.down : .white) {
                        tick()
                        a.vote(-1)
                    }
                    .accessibilityAddTraits(ov.likes == false ? .isSelected : [])
                    ViewerButton(icon: "bubble.right", label: "Comments, \(ov.numComments)") {
                        model.close { a.openDetail() }
                    }
                    .padding(.top, 6)
                    Text(compactNumber(ov.numComments))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 3)
                        .accessibilityHidden(true)
                    ViewerButton(icon: ov.saved ? "bookmark.fill" : "bookmark", label: ov.saved ? "Unsave" : "Save") {
                        tick()
                        a.toggleSave()
                    }
                    .accessibilityAddTraits(ov.saved ? .isSelected : [])
                    ViewerButton(icon: "square.and.arrow.up", label: "Share") { a.share() }
                    // The post's sheet belongs to the screen beneath: it opens once the browser has gone.
                    ViewerButton(icon: "ellipsis", label: "More") { model.close { a.more() } }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}
