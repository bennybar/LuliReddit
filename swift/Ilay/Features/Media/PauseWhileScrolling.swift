import UIKit

/// Whether a list is scrolling right now: UIKit keeps the main run loop in tracking
/// mode while a scroll view is dragged or decelerates. Needs no wiring from the list
/// (Kotlin's `LocalListScrolling`), and hosted cells couldn't read an environment
/// from their list anyway.
@MainActor func isListScrolling() -> Bool { RunLoop.main.currentMode == .tracking }

/// An animated image (GIF, animated WebP) stops on its current frame while the
/// surrounding list scrolls, and plays again when it stops. These animate on the
/// render server's own clock, out of step with the scroll, which made Android drop
/// about one frame in six in a thread with GIFs. Call from `updateUIView` for an
/// image view inside a list; not for the full-screen viewers.
@MainActor enum PauseWhileScrolling {
    private static let views = NSHashTable<UIImageView>.weakObjects()
    private static var timer: Timer?
    private static var paused = false

    static func attach(_ view: UIImageView) {
        guard !views.contains(view) else { return }
        views.add(view)
        if paused { pause(view.layer) }
        guard timer == nil else { return }
        // Common modes: the default mode doesn't run during the scroll this looks for.
        let tick = Timer(timeInterval: 0.1, repeats: true) { _ in MainActor.assumeIsolated { update() } }
        RunLoop.main.add(tick, forMode: .common)
        timer = tick
    }

    private static func update() {
        let moving = isListScrolling()
        if moving != paused {
            paused = moving
            for view in views.allObjects {
                if moving { pause(view.layer) } else { resume(view.layer) }
            }
        }
        if views.allObjects.isEmpty {
            timer?.invalidate()
            timer = nil
        }
    }

    private static func pause(_ layer: CALayer) {
        guard layer.speed != 0 else { return }
        let now = layer.convertTime(CACurrentMediaTime(), from: nil)
        layer.speed = 0
        layer.timeOffset = now
    }

    private static func resume(_ layer: CALayer) {
        guard layer.speed == 0 else { return }
        let pausedAt = layer.timeOffset
        layer.speed = 1
        layer.timeOffset = 0
        layer.beginTime = 0
        layer.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) - pausedAt
    }
}
