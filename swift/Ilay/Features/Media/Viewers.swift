import SwiftUI

/// Swipe-down-to-dismiss with a background fade, shared by every viewer.
@MainActor @Observable final class DismissState {
    var drag: CGFloat = 0
    var zoomed = false
    var showControls = true
    @ObservationIgnored let close: () -> Void

    init(close: @escaping () -> Void) { self.close = close }
}

/// The fade: gone at 500pt of drag.
private let dismissFade: CGFloat = 500
private let dismissDistance: CGFloat = 130
private let dismissVelocity: CGFloat = 800

/// A viewer's content in UIKit, whose recognizers can decide from velocity whether a drag
/// is a page or a dismiss. Moves `contentRoot` under the finger; `state.drag` fades the
/// SwiftUI background and controls.
class DismissableContentView: UIView, UIGestureRecognizerDelegate {
    let state: DismissState
    let contentRoot = UIView()
    let singleTap = UITapGestureRecognizer()
    let edgePan = UIScreenEdgePanGestureRecognizer()
    /// The swipe-to-dismiss; the media browser turns it off, as its vertical swipes page.
    let pan = UIPanGestureRecognizer()

    init(state: DismissState) {
        self.state = state
        super.init(frame: .zero)
        addSubview(contentRoot)
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        pan.addTarget(self, action: #selector(panned))
        addGestureRecognizer(pan)
        // A left-edge swipe-to-go-back, without stealing zoom pan / gallery paging.
        edgePan.edges = .left
        edgePan.addTarget(self, action: #selector(edgePanned))
        addGestureRecognizer(edgePan)
        pan.require(toFail: edgePan)
        singleTap.addTarget(self, action: #selector(tapped))
        addGestureRecognizer(singleTap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Through bounds and center, not frame: the transform may be set mid-rotation.
        contentRoot.bounds = bounds
        contentRoot.center = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    func tappedContent() {
        state.showControls.toggle()
    }

    @objc private func tapped() { tappedContent() }

    @objc private func edgePanned(_ gesture: UIScreenEdgePanGestureRecognizer) {
        // Flutter's fling threshold.
        if gesture.state == .ended, gesture.velocity(in: self).x > 80 { state.close() }
    }

    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        let drag = gesture.translation(in: self).y
        switch gesture.state {
        case .changed:
            contentRoot.transform = CGAffineTransform(translationX: 0, y: drag)
            state.drag = drag
        case .ended, .cancelled, .failed:
            if gesture.state == .ended, abs(drag) > dismissDistance || abs(gesture.velocity(in: self).y) > dismissVelocity {
                state.close()
            } else {
                UIView.animate(springDuration: 0.3) { contentRoot.transform = .identity }
                withAnimation(.spring(duration: 0.3)) { state.drag = 0 }
            }
        default:
            break
        }
    }

    override func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        guard gesture === pan else { return true }
        guard !state.zoomed else { return false }
        let v = pan.velocity(in: self)
        return abs(v.y) > abs(v.x)
    }
}

/// The black behind a viewer, in its own view so a drag redraws only this.
struct DismissBackground: View {
    let state: DismissState

    var body: some View {
        Color.black.opacity(max(min(1 - abs(state.drag) / dismissFade, 1), 0)).ignoresSafeArea()
    }
}

/// Floating controls (close + download + share + open) on system glass over a scrim.
struct ViewerControls: View {
    let title: String?
    let sourceUrl: String?
    var center: String? = nil
    var downloadUrl: String? = nil
    var downloadIsVideo = false
    let close: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                ViewerButton(icon: "xmark", label: "Close", action: close)
                Text(center ?? title ?? "")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 3)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let downloadUrl {
                    ViewerButton(icon: "arrow.down.to.line", label: "Download") {
                        Task { await saveMediaToGallery(downloadUrl, isVideo: downloadIsVideo) }
                    }
                }
                if let sourceUrl {
                    ViewerButton(icon: "square.and.arrow.up", label: "Share") {
                        app.navigator.share(sourceUrl)
                    }
                    ViewerButton(icon: "safari", label: "Open in browser") {
                        openExternally(sourceUrl)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 120)
                .padding(.top, -60)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}

struct ViewerButton: View {
    let icon: String
    let label: String
    var size: CGFloat = 44
    var iconSize: CGFloat = 17
    var color: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(label)
    }
}

/// Opens `url` in another app (browser / Reddit / player).
func openExternally(_ url: String) {
    guard let parsed = URL(string: url) else { return }
    UIApplication.shared.open(parsed) { opened in
        if !opened { app.navigator.showSnackbar("No app can open this link.") }
    }
}

/// Full-screen image viewer (zoom, swipe-to-dismiss, save/share), and gallery viewer
/// (pager + "i / n" counter) when given several.
struct ImageViewer: View {
    let urls: [String]
    let initialIndex: Int
    let title: String?
    let isGallery: Bool
    @State var state: DismissState
    @State private var page: Int

    init(urls: [String], initialIndex: Int = 0, title: String?, isGallery: Bool, close: @escaping () -> Void) {
        self.urls = urls
        self.initialIndex = initialIndex
        self.title = title
        self.isGallery = isGallery
        _state = State(initialValue: DismissState(close: close))
        _page = State(initialValue: min(max(initialIndex, 0), urls.count - 1))
    }

    private var controlsVisible: Bool { state.showControls && abs(state.drag) < 8 }

    var body: some View {
        ZStack(alignment: .top) {
            DismissBackground(state: state)
            ZoomablePagerView(urls: urls, initialIndex: initialIndex, state: state, page: $page)
                .ignoresSafeArea()
            ViewerControls(
                title: title,
                sourceUrl: urls[page],
                center: isGallery ? "\(page + 1) / \(urls.count)" : nil,
                downloadUrl: urls[page],
                close: state.close
            )
            .opacity(controlsVisible ? 1 : 0)
            .allowsHitTesting(controlsVisible)
            .animation(.easeOut(duration: 0.15), value: controlsVisible)
        }
        .accessibilityAction(.escape) { state.close() }
    }
}

private struct ZoomablePagerView: UIViewRepresentable {
    let urls: [String]
    let initialIndex: Int
    let state: DismissState
    @Binding var page: Int

    func makeUIView(context: Context) -> ZoomablePager {
        ZoomablePager(urls: urls, initialIndex: initialIndex, state: state) { page = $0 }
    }

    func updateUIView(_ view: ZoomablePager, context: Context) {}
}

// MARK: - Presenting

/// Hosts one viewer as a transparent modal over the whole app, above the tab bar and any
/// open sheet (Flutter's non-opaque fade route), so swipe-to-dismiss fades to the feed
/// underneath. Immersive: no status bar, the home indicator fades away.
final class MediaViewerController: UIHostingController<AnyView> {
    private let onClosed: () -> Void

    init(root: AnyView, onClosed: @escaping () -> Void) {
        self.onClosed = onClosed
        super.init(rootView: root)
        view.backgroundColor = .clear
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
        modalPresentationCapturesStatusBarAppearance = true
        overrideUserInterfaceStyle = .dark // Controls over media, whatever the app's theme.
    }

    @available(*, unavailable) required dynamic init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .allButUpsideDown }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || presentingViewController == nil { onClosed() }
    }
}

/// The screen on top of everything, to present from.
@MainActor func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    var top = (scene?.keyWindow ?? scene?.windows.first)?.rootViewController
    while let next = top?.presentedViewController, !next.isBeingDismissed { top = next }
    return top
}

/// Keeps the viewer modals in step with `ViewerStack`, which `AppNavigator` drives.
@MainActor private final class ViewerPresenter {
    static let shared = ViewerPresenter()
    private var presented: [(id: Int, controller: MediaViewerController)] = []

    func sync(with stack: ViewerStack) {
        let ids = Set(stack.entries.map(\.id))
        // Dismissing one takes those above it too.
        if let gone = presented.firstIndex(where: { !ids.contains($0.id) }) {
            let controller = presented[gone].controller
            presented.removeSubrange(gone...)
            controller.dismiss(animated: true) { [self] in sync(with: stack) }
            return
        }
        let shown = Set(presented.map(\.id))
        for entry in stack.entries where !shown.contains(entry.id) {
            // Before building the viewer: a video viewer borrows the paused feed clip.
            app.media.inlinePlayer.setCovered(true)
            let controller = makeController(entry.viewer, stack: stack)
            guard let top = topViewController() else { continue }
            // Zooms out of the tapped thumbnail when there is one, else the cross-dissolve.
            if let source = ZoomSourceView.tapped(in: top.view) {
                controller.preferredTransition = ZoomSourceView.transition(from: source)
            }
            presented.append((entry.id, controller))
            top.present(controller, animated: true)
        }
    }

    private func makeController(_ viewer: MediaViewer, stack: ViewerStack) -> MediaViewerController {
        let close: () -> Void = { stack.closeTop() }
        // The screen beneath stays alive, so its inline clip pauses meanwhile.
        var closed: () -> Void = {}
        let root: AnyView
        switch viewer {
        case let .image(url, title):
            root = AnyView(ImageViewer(urls: [url], title: title, isGallery: false, close: close))
        case let .gallery(urls, _, _, title, initialIndex):
            root = urls.isEmpty
                ? AnyView(Color.clear.onAppear(perform: close))
                : AnyView(ImageViewer(urls: urls, initialIndex: initialIndex, title: title, isGallery: true, close: close))
        case let .video(url, title, downloadUrl, externalUrl, gif):
            let model = VideoViewerModel(url: url, title: title, downloadUrl: downloadUrl, externalUrl: externalUrl, gif: gif, close: close)
            closed = { model.release() }
            root = AnyView(VideoViewer(model: model))
        }
        return MediaViewerController(root: root) { [weak self] in
            closed() // Hands back a borrowed clip first: setCovered(false) then plays it.
            if self?.presented.isEmpty ?? true { app.media.inlinePlayer.setCovered(false) }
        }
    }
}

/// Put this once over the app's root: it draws nothing itself, and presents the viewers
/// in `stack` as modals. Kotlin's `MediaViewerHost`.
struct MediaViewerHost: View {
    let stack: ViewerStack

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .onChange(of: stack.entries.map(\.id), initial: true) {
                ViewerPresenter.shared.sync(with: stack)
            }
    }
}
