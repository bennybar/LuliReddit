import AVFoundation
import SwiftUI

/// The state of a full-screen video. Built before the viewer opens and owned by its
/// controller, so leaving always releases the player, even mid-load.
@MainActor @Observable final class VideoViewerModel {
    let url: String
    let title: String?
    let downloadUrl: String?
    let externalUrl: String?
    let dismiss: DismissState
    @ObservationIgnored let player: AVPlayer
    /// The feed card's own player (see `InlineVideoPool.borrow`): given back on close, not torn down.
    @ObservationIgnored private let borrowed: Bool

    var muted = app.settings.value.viewerMuted
    var error: String?
    var ready = false
    var playing = false
    /// Stopped at the end (Loop videos off, #156): the play button replays.
    var ended = false
    var hideTick = 0
    var position = 0.0
    var duration = 0.0
    var buffered = 0.0

    /// Playing, or meant to be: what returning from the background restores.
    @ObservationIgnored private var wanted = true
    @ObservationIgnored private var resumeAfterBackground = false
    /// Paused only while the audio session switches (see `toggleMute`): still "playing".
    @ObservationIgnored private var switchingSession = false
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(url: String, title: String?, downloadUrl: String?, externalUrl: String?, gif: Bool = false, close: @escaping () -> Void) {
        self.url = url
        self.title = title
        self.downloadUrl = downloadUrl
        self.externalUrl = externalUrl
        dismiss = DismissState(close: close)
        let pool = app.media.inlinePlayer
        // The clip playing in the feed: carry on with it, from the same frame and with
        // nothing downloaded again.
        if let lent = pool.borrow(url) {
            player = lent
            borrowed = true
            ready = true
        } else {
            player = AVPlayer()
            borrowed = false
            player.actionAtItemEnd = .none
            observers.append(observeVideoEnd(of: player))
        }
        // Settings › Loop videos (#156); a GIF always loops. Off, it stops at the end
        // (a clip borrowed from the feed is rewound by the feed's loop; it stops there).
        if !gif && !app.settings.value.loopVideos {
            observers.append(NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self, note.object as? AVPlayerItem === self.player.currentItem else { return }
                    self.wanted = false
                    self.player.pause()
                    self.ended = true
                }
            })
        }
        player.isMuted = muted
        // Muted, it leaves the audio session alone, so the user's music keeps playing.
        VideoAudio.shared.setAudible(!muted)
        observe()
        if borrowed {
            player.play()
            hideTick += 1
            refreshTimes()
        } else if let asset = videoAsset(url) {
            let item = AVPlayerItem(asset: asset)
            // Carry on from where the feed card was.
            let at = pool.position(url)
            observations.append(item.observe(\.status) { [weak self] item, _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.itemStatusChanged(item, startAt: at) } }
            })
            player.replaceCurrentItem(with: item)
            player.play()
        } else {
            error = "Bad URL"
        }
    }

    private func observe() {
        observations.append(player.observe(\.timeControlStatus, options: [.initial]) { [weak self] player, _ in
            let on = player.timeControlStatus != .paused
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.playing = on } }
        })
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

    private func itemStatusChanged(_ item: AVPlayerItem, startAt: CMTime?) {
        switch item.status {
        case .failed:
            error = item.error?.localizedDescription ?? "Playback error"
        case .readyToPlay where !ready:
            if let startAt { player.seek(to: startAt, toleranceBefore: .zero, toleranceAfter: .zero) }
            ready = true
            hideTick += 1
            refreshTimes()
        default:
            break
        }
    }

    func refreshTimes() {
        guard let item = player.currentItem else { return }
        position = player.currentTime().seconds.finiteOrZero
        duration = item.duration.seconds.finiteOrZero
        buffered = item.loadedTimeRanges.last.map { CMTimeRangeGetEnd($0.timeRangeValue).seconds.finiteOrZero } ?? 0
    }

    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        position = seconds
        hideTick += 1
    }

    func seekBy(_ seconds: Double) {
        let max = duration > 0 ? duration : Double.greatestFiniteMagnitude
        seek(to: Swift.min(Swift.max(player.currentTime().seconds.finiteOrZero + seconds, 0), max))
    }

    func togglePlay() {
        if ended {
            ended = false
            wanted = true
            player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            player.play()
            hideTick += 1
            return
        }
        if player.rate != 0 || (wanted && switchingSession) {
            wanted = false
            player.pause()
        } else {
            wanted = true
            player.play()
        }
        hideTick += 1
    }

    func toggleMute() {
        muted.toggle()
        player.isMuted = muted
        // Muted gives the session back, so the user's music returns.
        switchingSession = true
        VideoAudio.shared.setAudible(!muted, player: player) { [weak self] in
            self?.switchingSession = false
            if self?.wanted == true { self?.player.play() }
        }
        hideTick += 1
    }

    /// The viewer is gone.
    func release() {
        observations.removeAll()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        if borrowed {
            app.media.inlinePlayer.giveBack()
        } else {
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
    }
}

private extension Double {
    var finiteOrZero: Double { isFinite ? self : 0 }
}

private func fmt(_ seconds: Double) -> String {
    let total = Int(max(seconds, 0))
    let (h, m, s) = (total / 3600, total / 60 % 60, total % 60)
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
}

/// Full-screen video player, with sound unless Settings → Open videos muted.
struct VideoViewer: View {
    let model: VideoViewerModel
    private var state: DismissState { model.dismiss }
    private var link: String { model.externalUrl ?? model.url }
    private var controls: Bool { state.showControls && abs(state.drag) < 8 }

    /// What restarts the auto-hide.
    private struct HideKey: Hashable {
        let controls, playing: Bool
        let tick: Int
    }

    var body: some View {
        ZStack {
            DismissBackground(state: state)
            if let _ = model.error {
                errorView
            } else {
                // Tapping the video only toggles the overlay: it never changes play state.
                VideoSurface(player: model.player, state: state, onShowControls: { model.hideTick += 1 })
                    .opacity(model.ready ? 1 : 0)
                    .ignoresSafeArea()
                if !model.ready { ProgressView().tint(.white).controlSize(.large) }
            }

            // Playback controls overlay (tap the video to show/hide).
            if model.error == nil, model.ready {
                Color.black.opacity(0.26).ignoresSafeArea().allowsHitTesting(false)
                    .opacity(controls ? 1 : 0)
                centreButtons.opacity(controls ? 1 : 0).allowsHitTesting(controls)
                VStack {
                    Spacer()
                    bottomBar
                }
                .opacity(controls ? 1 : 0)
                .allowsHitTesting(controls)
            }

            VStack {
                ViewerControls(
                    title: model.title,
                    sourceUrl: link,
                    // A direct mp4 for saving (an HLS playlist can't be saved).
                    downloadUrl: model.downloadUrl.flatMap { $0.contains(".m3u8") ? nil : $0 },
                    downloadIsVideo: true,
                    close: state.close
                )
                Spacer()
            }
            .opacity(controls || model.error != nil ? 1 : 0)
            .allowsHitTesting(controls || model.error != nil)
        }
        .animation(.easeOut(duration: 0.15), value: controls)
        .accessibilityAction(.escape) { state.close() }
        // Position for the time labels / scrubber, while the controls are up.
        .task(id: controls && model.ready) {
            guard controls && model.ready else { return }
            while !Task.isCancelled {
                model.refreshTimes()
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        // Only auto-hide while playing; keep controls up when paused.
        .task(id: HideKey(controls: controls, playing: model.playing, tick: model.hideTick)) {
            guard controls, model.playing else { return }
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { state.showControls = false }
        }
    }

    private var errorView: some View {
        VStack(spacing: 14) {
            Image(systemName: "video.slash")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.54))
            Text("This video can't be played in the app: its format isn't supported on this device.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.7))
            Button("Open in browser", systemImage: "safari") { openExternally(link) }
                .buttonStyle(.glassProminent)
                .padding(.top, 6)
        }
        .padding(28)
    }

    private var centreButtons: some View {
        GlassEffectContainer(spacing: 28) {
            HStack(spacing: 28) {
                ViewerButton(icon: "gobackward.10", label: "Back 10 seconds", size: 56, iconSize: 24) { model.seekBy(-10) }
                ViewerButton(icon: model.ended ? "arrow.counterclockwise" : model.playing ? "pause.fill" : "play.fill", label: model.ended ? "Replay" : "Play/pause", size: 72, iconSize: 32) {
                    model.togglePlay()
                }
                ViewerButton(icon: "goforward.10", label: "Forward 10 seconds", size: 56, iconSize: 24) { model.seekBy(10) }
            }
        }
    }

    /// Bottom: time + draggable scrubber + mute.
    private var bottomBar: some View {
        HStack(spacing: 10) {
            Text(fmt(model.position)).monospacedDigit()
            Scrubber(position: model.position, duration: model.duration, buffered: model.buffered) { model.seek(to: $0) }
            Text(fmt(model.duration)).monospacedDigit()
            Button(action: model.toggleMute) {
                Image(systemName: model.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(model.muted ? "Unmute" : "Mute")
        }
        .font(.caption)
        .foregroundStyle(.white)
        .tint(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}

private struct VideoSurface: UIViewRepresentable {
    let player: AVPlayer
    let state: DismissState
    let onShowControls: () -> Void

    final class Surface: DismissableContentView {
        let playerLayer = AVPlayerLayer()
        var onShowControls: () -> Void = {}

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.frame = contentRoot.bounds
            CATransaction.commit()
        }

        override func tappedContent() {
            super.tappedContent()
            if state.showControls { onShowControls() }
        }
    }

    func makeUIView(context: Context) -> Surface {
        let view = Surface(state: state)
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.contentRoot.layer.addSublayer(view.playerLayer)
        view.onShowControls = onShowControls
        return view
    }

    func updateUIView(_ view: Surface, context: Context) {}
}

/// An ~8pt thick progress bar you can tap or drag to seek.
private struct Scrubber: View {
    let position: Double
    let duration: Double
    let buffered: Double
    let onSeek: (Double) -> Void

    @State private var dragFraction: Double?

    private func fraction(_ value: Double) -> Double {
        duration > 0 ? min(max(value / duration, 0), 1) : 0
    }

    var body: some View {
        let played = dragFraction ?? fraction(position)
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.24))
                Capsule().fill(.white.opacity(0.38)).frame(width: width * fraction(buffered))
                Capsule().fill(.white).frame(width: width * played)
            }
            .frame(height: 8)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { dragFraction = min(max($0.location.x / max(width, 1), 0), 1) }
                    .onEnded { _ in
                        if let f = dragFraction, duration > 0 { onSeek(f * duration) }
                        dragFraction = nil
                    }
            )
        }
        .frame(height: 26)
        // A seek bar for screen readers: position read out, swipe up / down to seek.
        .accessibilityElement()
        .accessibilityLabel("Video position")
        .accessibilityValue("\(Int(played * 100)) percent")
        .accessibilityAdjustableAction { direction in
            guard duration > 0 else { return }
            let step = direction == .increment ? 0.1 : -0.1
            onSeek(min(max(fraction(position) + step, 0), 1) * duration)
        }
    }
}
