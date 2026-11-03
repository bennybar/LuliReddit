import AVFoundation
import SwiftUI

extension View {
    /// Marks media that opens the full-screen viewer: the viewer zooms out of it, and back
    /// into it on close, like Photos. An empty view behind the content, so taps and layout
    /// are untouched.
    func zoomSource() -> some View { background(ZoomSource()) }
}

private struct ZoomSource: UIViewRepresentable {
    func makeUIView(context: Context) -> ZoomSourceView { ZoomSourceView() }
    func updateUIView(_ view: ZoomSourceView, context: Context) {}
}

/// Where a viewer zooms from. SwiftUI's media aren't UIViews, and the viewer is opened from
/// many places (`AppNavigator.openImage` and friends), so rather than passing a view along,
/// the presenter picks the marked view under the last touch.
final class ZoomSourceView: UIView {
    /// Every marked view, weakly: a dropped cell takes its own with it.
    private static let all = NSHashTable<ZoomSourceView>.weakObjects()
    private static weak var recordingWindow: UIWindow?
    /// The last touch down, in window coordinates.
    fileprivate static var lastTouch: (point: CGPoint, time: Date)?

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        Self.all.add(self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // The first marked view on screen starts the recorder, before any of them can be tapped.
        if let window, window !== Self.recordingWindow {
            window.addGestureRecognizer(TouchRecorder())
            Self.recordingWindow = window
        }
    }

    /// The marked view just tapped inside `screen`, if any. Within a few seconds, so a viewer
    /// opened later (a RedGifs lookup, a link) doesn't zoom from a stale touch; the smallest
    /// match wins (a carousel image inside a card).
    static func tapped(in screen: UIView) -> ZoomSourceView? {
        guard let touch = lastTouch, Date().timeIntervalSince(touch.time) < 3 else { return nil }
        return all.allObjects
            .filter { $0.window != nil && $0.isDescendant(of: screen) && $0.convert($0.bounds, to: nil).contains(touch.point) }
            .min { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }
    }

    /// The zoom out of `source`, and back into it on close.
    static func transition(from source: ZoomSourceView) -> UIViewController.Transition {
        let options = UIViewController.Transition.ZoomOptions()
        // The viewer's own swipe-to-dismiss (fading to the screen beneath) stays the only one.
        options.interactiveDismissShouldBegin = { _ in false }
        // The media sits centred and fitted in the viewer: line the thumbnail up with that,
        // not with the whole screen.
        options.alignmentRectProvider = { context in
            AVMakeRect(aspectRatio: context.sourceView.bounds.size, insideRect: context.zoomedViewController.view.bounds)
        }
        // Gone (cell reused for another post, screen closed): no view, and UIKit doesn't zoom.
        return .zoom(options: options) { [weak source] _ in source?.window == nil ? nil : source }
    }
}

/// Notes each touch down in the window for `ZoomSourceView.tapped`. Fails at once, so it
/// never delays, cancels or blocks anything.
private final class TouchRecorder: UIGestureRecognizer {
    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first { ZoomSourceView.lastTouch = (touch.location(in: nil), Date()) }
        state = .failed
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
}
