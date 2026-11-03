import AVFoundation
import SwiftUI

/// True under a cover (e.g. an unrevealed NSFW blur): inline videos don't autoplay there.
extension EnvironmentValues {
    @Entry var mediaCovered = false
}

/// A card counts as on screen (and may play) once this much of it is visible.
private let visibleThreshold = 0.6

/// One card's claim on the shared player.
@MainActor @Observable final class InlineCard {
    /// Holding the player.
    fileprivate(set) var active = false
    /// The clip is prepared (the mute toggle shows from here).
    fileprivate(set) var ready = false
    /// The clip has drawn its first frame (until then the surface is blank).
    fileprivate(set) var firstFrame = false
    var muted = true

    @ObservationIgnored fileprivate var url = ""
    @ObservationIgnored fileprivate var fraction = 0.0
    @ObservationIgnored fileprivate weak var surface: UIView?
}

/// One AVPlayer shared by every inline feed video. Cards on screen register here; the
/// most visible one past the threshold gets the player, every other card shows its
/// poster. One decoder for the whole feed, instead of one per nearby card competing
/// while scrolling, which is what made long feeds stutter. Positions are remembered
/// per URL, so a clip scrolled away and back resumes where it was, and the full-screen
/// viewer borrows the playing clip itself (no second download, carries on from the
/// same frame, as on Flutter iOS). Main thread only.
///
/// Scrolling never pays for a clip change: what costs main-thread time is
/// `replaceCurrentItem`, so a new clip starts (and an old one is freed) only once the
/// list has settled. While it moves, the playing clip plays on, or just pauses if it
/// has left the screen.
@MainActor final class InlineVideoPool {
    private let player = AVPlayer()
    /// One layer, moved to whichever card plays: a new layer per card would rebuild
    /// the render pipeline each time.
    private let layer: AVPlayerLayer
    private var cards: [InlineCard] = []
    private var active: InlineCard?
    private var activeUrl: String?
    private var positions: [String: CMTime] = [:]
    private var positionOrder: [String] = [] // Oldest first.
    private var foreground = true
    /// A full-screen viewer is open over the feed (it stays alive beneath).
    private var covered = false
    /// The full-screen viewer has the player (see `borrow`).
    private var lent = false
    private var scrolling = false
    private var timer: Timer?
    private var loadTask: Task<Void, Never>?
    private var statusObservation: NSKeyValueObservation?
    private var displayObservation: NSKeyValueObservation?
    private var loopObserver: NSObjectProtocol?
    private var observers: [NSObjectProtocol] = []

    init() {
        player.actionAtItemEnd = .none // Looped below.
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.allowsExternalPlayback = false
        layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill // BoxFit.cover: centred, cropped by the card.
        loopObserver = observeVideoEnd(of: player)
        displayObservation = layer.observe(\.isReadyForDisplay) { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.updateFirstFrame() } }
        }
        let center = NotificationCenter.default
        // Pause with the app; resume the active clip on return.
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.foreground = false
                self?.applyPlay()
            }
        })
        observers.append(center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.foreground = true
                self?.applyPlay()
            }
        })
        observers.append(observeAudioInterruptions(
            muted: { [weak self] in self?.active?.muted ?? true },
            resume: { [weak self] in self?.applyPlay() }
        ))
    }

    // MARK: Cards

    fileprivate func add(_ card: InlineCard, url: String) {
        card.url = url
        card.fraction = 0
        if !cards.contains(where: { $0 === card }) { cards.append(card) }
        guard timer == nil else { return }
        // Hosted cells aren't told when their list moves them, so the pool looks: a few
        // rect conversions for the few cards on screen, ten times a second, only while
        // some are. Common modes: the default mode doesn't run during a scroll.
        let tick = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
        tick.tolerance = 0.03
        RunLoop.main.add(tick, forMode: .common)
        timer = tick
    }

    fileprivate func remove(_ card: InlineCard) {
        cards.removeAll { $0 === card }
        card.fraction = 0
        if active === card { recompute() }
        if cards.isEmpty {
            timer?.invalidate()
            timer = nil
        }
    }

    fileprivate func setMuted(_ card: InlineCard, _ muted: Bool) {
        card.muted = muted
        guard active === card, !lent else { return }
        player.isMuted = muted
        // Unmuted takes the audio session; muted gives it back so the music returns.
        VideoAudio.shared.setAudible(!muted, player: player) { [weak self] in self?.applyPlay() }
    }

    /// Pauses the feed clip while a media viewer covers it; resumes after.
    func setCovered(_ value: Bool) {
        guard covered != value else { return }
        covered = value
        guard !lent else { return }
        if value {
            applyPlay()
        } else {
            VideoAudio.shared.setAudible(active?.muted == false, player: player) { [weak self] in self?.applyPlay() }
        }
    }

    /// Where the feed's clip for `url` is (or was left), for the full-screen viewer to continue.
    func position(_ url: String) -> CMTime? {
        url == activeUrl && active?.ready == true ? player.currentTime() : positions[url]
    }

    /// The playing feed clip for `url`, handed to the full-screen viewer until
    /// `giveBack`; nil when the feed isn't playing that clip.
    func borrow(_ url: String) -> AVPlayer? {
        guard !lent, url == activeUrl, active?.ready == true, let item = player.currentItem else { return nil }
        lent = true
        layer.player = nil
        item.preferredMaximumResolution = .zero // Full screen wants every pixel again.
        return player
    }

    func giveBack() {
        guard lent else { return }
        lent = false
        layer.player = player
        if let card = active {
            player.isMuted = card.muted
            limitResolution(of: player.currentItem, to: card)
            // Paused while still covered: the viewer's setCovered(false) plays it.
            player.pause()
            card.firstFrame = false
            layer.opacity = 0
            updateFirstFrame()
        }
        // Cards may have come or gone meanwhile.
        recompute()
    }

    /// Choosing a card, apart so it can be tested. `current` is the one playing.
    nonisolated static func choose(_ fractions: [Double], current: Int?) -> Int? {
        var best: Int?
        var eligibleCurrent = false
        for (i, f) in fractions.enumerated() where f > visibleThreshold {
            if best == nil || f > fractions[best!] { best = i }
            if i == current { eligibleCurrent = true }
        }
        // Hysteresis: keep the playing card while it's (about) as visible as the best.
        if let current, eligibleCurrent, let b = best, fractions[current] >= fractions[b] - 0.05 { return current }
        return best
    }

    // MARK: Visibility

    private func tick() {
        guard !covered else { return } // Nothing beneath can change hands until it's back.
        let moving = isListScrolling()
        var changed = moving != scrolling
        scrolling = moving
        for card in cards {
            // Quantized, so scrolling doesn't recompute on every pixel.
            let f = ((Self.visibleFraction(of: card.surface) * 20).rounded()) / 20
            if f != card.fraction {
                card.fraction = f
                changed = true
            }
        }
        if changed { recompute() }
    }

    private static func visibleFraction(of view: UIView?) -> Double {
        guard let view, let window = view.window, view.bounds.height > 0 else { return 0 }
        var visible = view.convert(view.bounds, to: window).intersection(window.bounds)
        var ancestor = view.superview
        while let a = ancestor {
            // A reused cell waits hidden, wherever it last was.
            if a.isHidden || a.alpha < 0.01 { return 0 }
            if a.clipsToBounds { visible = visible.intersection(a.convert(a.bounds, to: window)) }
            ancestor = a.superview
        }
        return visible.isNull ? 0 : visible.height / view.bounds.height
    }

    private func recompute() {
        if lent { return } // The viewer has it; sorted out on giveBack.
        let currentIndex = cards.firstIndex { $0 === active }
        var best = Self.choose(cards.map(\.fraction), current: currentIndex).map { cards[$0] }
        if scrolling, best !== active {
            // No clip change mid-scroll: stay on the playing card if it still counts.
            best = currentIndex.flatMap { cards[$0].fraction > visibleThreshold ? cards[$0] : nil }
        }
        if best === active {
            // Nothing on screen: free the decoder, keep the player for the next card.
            if best == nil, !scrolling, player.currentItem != nil { player.replaceCurrentItem(with: nil) }
            return
        }
        stopActive()
        guard let best else {
            VideoAudio.shared.setAudible(false)
            if !scrolling { player.replaceCurrentItem(with: nil) }
            return
        }
        start(best)
    }

    private func stopActive() {
        guard let card = active else { return }
        loadTask?.cancel()
        statusObservation = nil
        if card.ready, let url = activeUrl {
            positions[url] = player.currentTime()
            positionOrder.removeAll { $0 == url }
            positionOrder.append(url)
            if positionOrder.count > 64 { positions[positionOrder.removeFirst()] = nil }
        }
        player.pause()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.removeFromSuperlayer()
        CATransaction.commit()
        card.active = false
        card.ready = false
        card.firstFrame = false
        active = nil
        activeUrl = nil
    }

    private func start(_ card: InlineCard) {
        active = card
        activeUrl = card.url
        card.active = true
        player.isMuted = card.muted
        VideoAudio.shared.setAudible(!card.muted)
        guard let asset = videoAsset(card.url) else { return }
        loadTask = Task { [weak self] in
            // Off the main thread: the HLS master playlist is fetched here rather than
            // by the player while the main thread waits. A failure shows in `status`.
            _ = try? await asset.load(.isPlayable)
            guard let self, !Task.isCancelled, self.active === card else { return }
            let item = AVPlayerItem(asset: asset)
            self.limitResolution(of: item, to: card)
            self.statusObservation = item.observe(\.status) { [weak self, weak card] item, _ in
                guard item.status == .readyToPlay else { return }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        if let self, let card { self.prepared(item, card) }
                    }
                }
            }
            self.player.replaceCurrentItem(with: item)
        }
    }

    private func prepared(_ item: AVPlayerItem, _ card: InlineCard) {
        guard active === card, player.currentItem === item, !card.ready else { return }
        let show: () -> Void = { [weak self, weak card] in
            guard let self, let card, self.active === card, !card.ready else { return }
            card.ready = true
            if let surface = card.surface {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                self.layer.frame = surface.bounds
                self.layer.opacity = 0
                surface.layer.addSublayer(self.layer)
                CATransaction.commit()
            }
            self.updateFirstFrame()
            self.applyPlay()
        }
        if let at = positions[card.url] {
            player.seek(to: at, toleranceBefore: .zero, toleranceAfter: .positiveInfinity) { _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { show() } }
            }
        } else {
            show()
        }
    }

    private func updateFirstFrame() {
        guard let card = active, card.ready, !lent, layer.isReadyForDisplay else { return }
        card.firstFrame = true
        // The fade is the layer's, not the surface view's: the pool reads a transparent
        // view as not on screen, and it would never get a clip to show.
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.15)
        layer.opacity = 1
        CATransaction.commit()
    }

    private func applyPlay() {
        guard !lent, let card = active, card.ready else { return }
        if foreground && !covered { player.play() } else { player.pause() }
    }

    /// No more pixels than the card shows: a feed slot doesn't need the top HLS variant.
    private func limitResolution(of item: AVPlayerItem?, to card: InlineCard) {
        guard let item, let surface = card.surface else { return }
        let scale = surface.window?.screen.scale ?? 3
        item.preferredMaximumResolution = CGSize(width: surface.bounds.width * scale, height: surface.bounds.height * scale)
    }
}

/// An AVPlayer asset that asks with the web User-Agent, as Android's data source does.
/// v.redd.it HLS (HLSPlaylist.m3u8) or a progressive mp4 (DASH_720.mp4, imgur, RedGifs…).
func videoAsset(_ url: String) -> AVURLAsset? {
    URL(string: url).map { AVURLAsset(url: $0, options: [AVURLAssetHTTPUserAgentKey: RedditConstants.webUserAgent]) }
}

/// Loop: back to the start when the item ends (Android's REPEAT_MODE_ONE). AVPlayerLooper
/// would queue copies of the item, more than a clip in a shared player is worth.
@MainActor func observeVideoEnd(of player: AVPlayer) -> NSObjectProtocol {
    NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main) { [weak player] note in
        MainActor.assumeIsolated {
            guard let player, note.object as? AVPlayerItem === player.currentItem else { return }
            player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }
}

/// Feed video: autoplays (muted, unless Autoplay with sound) + looping while visible,
/// pauses off-screen; tap = viewer. The player is attached only once the card is mostly
/// on screen (not when it's built: the list builds cards ahead of the viewport).
/// Respects Settings › autoplay media. For a hosted cell: give it its slot height and
/// it cleans up after itself as the cell leaves the screen.
struct InlineVideo: View {
    let url: String
    let height: CGFloat
    var poster: String? = nil
    let onTap: () -> Void

    var body: some View {
        // A reused cell keeps a view's state across posts: a new clip must be a new view.
        InlineVideoImpl(url: url, height: height, poster: poster, onTap: onTap).id(url)
    }
}

private struct InlineVideoImpl: View {
    let url: String
    let height: CGFloat
    let poster: String?
    let onTap: () -> Void

    @Environment(\.mediaCovered) private var covered
    @State private var card = InlineCard()

    private var canPlay: Bool { app.settings.value.autoplayMedia && !covered }

    var body: some View {
        ZStack {
            // The poster stays underneath; the video fades in on top once it has a frame.
            if let poster, let posterUrl = URL(string: poster) {
                RemoteImage(url: posterUrl)
            } else {
                Color.black.opacity(0.07)
            }
            if canPlay {
                InlineVideoSurface(card: card)
                    .allowsHitTesting(false)
                    .onAppear {
                        // Muted unless Settings › Autoplay with sound.
                        card.muted = !app.settings.value.autoplaySound
                        app.media.inlinePlayer.add(card, url: url)
                    }
                    .onDisappear { app.media.inlinePlayer.remove(card) }
            } else {
                Image(systemName: "play.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(.black.opacity(0.5), in: Circle())
                    .accessibilityLabel("Play")
            }
            if card.active, !card.firstFrame {
                ProgressView().tint(.white)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            // Mute / unmute toggle. A plain dimmed circle, not glass: this one scrolls
            // with the list, and glass would resample what's beneath it on every frame.
            if card.ready {
                Button {
                    app.media.inlinePlayer.setMuted(card, !card.muted)
                } label: {
                    Image(systemName: card.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(.black.opacity(0.5), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(card.muted ? "Unmute" : "Mute")
                .padding(8)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

private struct InlineVideoSurface: UIViewRepresentable {
    let card: InlineCard

    final class Surface: UIView {
        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.sublayers?.forEach { $0.frame = bounds }
            CATransaction.commit()
        }
    }

    func makeUIView(context: Context) -> Surface {
        let view = Surface()
        view.isUserInteractionEnabled = false
        view.clipsToBounds = true
        card.surface = view
        return view
    }

    func updateUIView(_ view: Surface, context: Context) {
        card.surface = view
    }
}
