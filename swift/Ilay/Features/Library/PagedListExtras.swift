import SwiftUI
import UIKit

/// A post as a row of a `PagedList`: its card, and the hairline the rowed layouts have
/// (`PostListView` draws those as list separators; a `PagedList` has none).
struct PagedPostRow: View {
    let post: Post

    var body: some View {
        let card = PostCard(post: post)
        VStack(spacing: 0) {
            card
            if !card.row.config.isCarded { Divider().padding(.leading, 16) }
        }
    }
}

/// A pool of reused cells per kind of post (Kotlin's `post_<type>` contentType).
func pagedPostKind(_ post: Post) -> Int {
    switch post.type {
    case .selfPost: 0
    case .image: 1
    case .video: 2
    case .gif: 3
    case .gallery: 4
    case .link: 5
    }
}

/// Opens a comment's permalink (its thread, focused on it).
@MainActor func openPermalink(_ permalink: String) {
    guard !permalink.isEmpty, let url = URL(string: "https://reddit.com\(permalink)"), let route = routeForRedditUrl(url) else { return }
    app.navigator.push(route)
}

/// A card-like row's surface: it has to stand out from the page behind it, which is
/// plain or grouped by the post layout (see `PagedListHook`).
extension Color {
    @MainActor static var pagedCard: Color {
        Color(FeedRowConfig.current().isCarded ? .secondarySystemGroupedBackground : .secondarySystemBackground)
    }
}

/// Reaches the collection view of the `PagedList` this is the background
/// of: the page colour that goes with the post layout, room above its rows, and how far it
/// has scrolled. `generation` changes whenever the list may have been created (loading → rows).
struct PagedListHook: UIViewRepresentable {
    var generation: Int
    var topInset: CGFloat = 0
    /// How far the rows have scrolled, 0 at the top.
    var onScroll: ((CGFloat) -> Void)? = nil

    @MainActor final class Coordinator: NSObject {
        var hook: PagedListHook
        weak var view: UIView?
        weak var list: ListScrollView?
        var observations: [NSKeyValueObservation] = []
        /// Not touched yet: stays at the top through whatever arrives late (the header's real
        /// height, the bars' insets, the first rows), none of which is a scroll.
        var pinned = true
        init(hook: PagedListHook) {
            self.hook = hook
            super.init()
            // SwiftUI can put the list in the hierarchy after the look `updateUIView` asks
            // for (loading → rows): with no update after that, the list never got its
            // top room and its first rows sat under the profile's header and tabs.
            NotificationCenter.default.addObserver(self, selector: #selector(listAppeared), name: ListScrollView.didAppear, object: nil)
        }

        @objc private func listAppeared() {
            if let view { attach(from: view) }
        }

        func attach(from view: UIView) {
            guard let found = Coordinator.find(from: view) else { return }
            if found !== list {
                list = found
                pinned = true
                observations = [
                    found.observe(\.contentOffset, options: [.new]) { [weak self] scroll, _ in
                        MainActor.assumeIsolated { self?.scrolled(scroll) }
                    },
                    found.observe(\.contentSize, options: [.new]) { [weak self] scroll, _ in
                        MainActor.assumeIsolated { self?.keepAtTop(scroll) }
                    },
                ]
            }
            found.backgroundColor = FeedRowConfig.current().isCarded ? .systemGroupedBackground : .systemBackground
            if found.contentInset.top != hook.topInset {
                found.contentInset.top = hook.topInset
                found.verticalScrollIndicatorInsets.top = hook.topInset
            }
            keepAtTop(found)
            scrolled(found)
        }

        private func keepAtTop(_ scroll: UIScrollView) {
            guard pinned else { return }
            let top = -scroll.adjustedContentInset.top
            if scroll.contentOffset.y != top { scroll.contentOffset.y = top }
        }

        private func scrolled(_ scroll: UIScrollView) {
            if scroll.isTracking { pinned = false }
            hook.onScroll?(scroll.contentOffset.y + scroll.adjustedContentInset.top)
        }

        /// The nearest list on this screen: up to its hosting controller's view, never another tab's.
        private static func find(from view: UIView) -> ListScrollView? {
            var up = view.superview
            while let ancestor = up {
                if let list = search(ancestor) { return list }
                if ancestor.next is UIViewController { return nil }
                up = ancestor.superview
            }
            return nil
        }

        private static func search(_ view: UIView) -> ListScrollView? {
            if let list = view as? ListScrollView { return list }
            for sub in view.subviews {
                if let list = search(sub) { return list }
            }
            return nil
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(hook: self) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        context.coordinator.view = view
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        let coordinator = context.coordinator
        coordinator.hook = self
        // The list is laid out in this same pass: look once it's in the hierarchy.
        DispatchQueue.main.async { coordinator.attach(from: view) }
    }
}
