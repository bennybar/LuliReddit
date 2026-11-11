import SwiftUI

/// A full-screen media viewer. Not a pushed route: viewers are drawn as a
/// transparent overlay above the current screen (the Flutter build's
/// non-opaque fade route), so swipe-to-dismiss reveals the feed underneath.
enum MediaViewer: Hashable, Codable {
    case image(url: String, title: String? = nil)
    case gallery(urls: [String], widths: [Int] = [], heights: [Int] = [], title: String? = nil, initialIndex: Int = 0)
    case video(url: String, title: String? = nil, downloadUrl: String? = nil, externalUrl: String? = nil, gif: Bool = false) // gif: always loops (#156)
}

/// The open viewers, bottom to top. Each fades in (220ms) and out (180ms) before
/// it leaves: `MediaViewerHost` gives its entries `.transition(.opacity)` and these
/// mutations carry the animation.
@MainActor @Observable final class ViewerStack {
    struct Entry: Identifiable {
        let viewer: MediaViewer
        let id: Int
    }

    private var nextId = 0
    private(set) var entries: [Entry] = []

    var isOpen: Bool { !entries.isEmpty }

    /// Back after the system ended the app: already open, no fade.
    func restore(_ viewers: [MediaViewer]) {
        for viewer in viewers {
            entries.append(Entry(viewer: viewer, id: nextId))
            nextId += 1
        }
    }

    func open(_ viewer: MediaViewer) {
        let entry = Entry(viewer: viewer, id: nextId)
        nextId += 1
        withAnimation(.easeOut(duration: 0.22)) { entries.append(entry) }
    }

    /// Fades out the top viewer; false when none is open.
    @discardableResult func closeTop() -> Bool {
        guard !entries.isEmpty else { return false }
        withAnimation(.easeIn(duration: 0.18)) { _ = entries.removeLast() }
        return true
    }

    func clear() { entries.removeAll() }
}
