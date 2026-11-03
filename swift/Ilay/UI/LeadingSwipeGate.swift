import UIKit

/// Shares the rightward swipe between a row's leading swipe action and going back, the way
/// Apollo does: from the screen's left edge it goes back (or brings out the side bar at the
/// root); started on a row that has a leading action, away from the edge, it's the action.
/// iOS 26's swipe-back from anywhere (`interactiveContentPopGestureRecognizer`) would
/// otherwise take the row's swipe, and an edge swipe could start the row's.
///
/// Each gate recognizes the moment such a touch lands, which fails the gestures made to wait
/// on it. It never delays or cancels touches and runs alongside everything else, so taps,
/// scrolling and the swipes themselves are untouched. A touch anywhere else (a header, a row
/// without a leading action, swipe actions off) fails it, and swipe-back works as usual;
/// screens without these gates keep it everywhere.
final class LeadingSwipeGate: UIGestureRecognizer, UIGestureRecognizerDelegate {
    /// Roughly the system's edge-swipe zone.
    private static let edgeWidth: CGFloat = 24

    /// The edge gate holds back the row's swipe; the other one, the content swipe-back.
    private let atEdge: Bool
    private let hasLeadingAction: (IndexPath) -> Bool

    /// Adds both gates to `list`. `hasLeadingAction` is asked per touch, so settings apply at once.
    static func install(on list: UICollectionView, hasLeadingAction: @escaping (IndexPath) -> Bool) {
        list.addGestureRecognizer(LeadingSwipeGate(atEdge: true, hasLeadingAction: hasLeadingAction))
        list.addGestureRecognizer(LeadingSwipeGate(atEdge: false, hasLeadingAction: hasLeadingAction))
    }

    private init(atEdge: Bool, hasLeadingAction: @escaping (IndexPath) -> Bool) {
        self.atEdge = atEdge
        self.hasLeadingAction = hasLeadingAction
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesEnded = false
        delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let list = view as? UICollectionView, let touch = touches.first,
              (touch.location(in: nil).x < Self.edgeWidth) == atEdge,
              let indexPath = list.indexPathForItem(at: touch.location(in: list)), hasLeadingAction(indexPath) else {
            state = .failed
            return
        }
        state = .recognized
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        if atEdge {
            // The row's swipe: the list's own pans other than scrolling.
            return other is UIPanGestureRecognizer && other.view === view && other !== (view as? UIScrollView)?.panGestureRecognizer
        }
        var responder = view?.next
        while let r = responder, !(r is UINavigationController) { responder = r.next }
        return other === (responder as? UINavigationController)?.interactiveContentPopGestureRecognizer
    }
}
