import Foundation
import Observation

/// One AI thread summary, kept with enough of its post to list it and open it again.
struct SavedSummary: Equatable, Sendable {
    let postId: String
    let subreddit: String
    let title: String
    let permalink: String
    let style: String
    let model: String
    let text: String
    let createdAt: Int

    // Same field names as the Flutter and Android builds' files.
    fileprivate var json: JsonElement {
        [
            "postId": .string(postId), "subreddit": .string(subreddit), "title": .string(title),
            "permalink": .string(permalink), "style": .string(style), "model": .string(model),
            "text": .string(text), "createdAt": .int(createdAt),
        ]
    }

    fileprivate init?(json m: JsonElement) {
        guard m.obj() != nil else { return nil }
        postId = m["postId"].str() ?? ""
        subreddit = m["subreddit"].str() ?? ""
        title = m["title"].str() ?? ""
        permalink = m["permalink"].str() ?? ""
        style = m["style"].str() ?? ""
        model = m["model"].str() ?? ""
        text = m["text"].str() ?? ""
        createdAt = m["createdAt"].long() ?? 0
    }

    init(postId: String, subreddit: String, title: String, permalink: String, style: String, model: String, text: String, createdAt: Int) {
        self.postId = postId
        self.subreddit = subreddit
        self.title = title
        self.permalink = permalink
        self.style = style
        self.model = model
        self.text = text
        self.createdAt = createdAt
    }
}

/// The posts you've summarized (newest first), per account, on this device
/// only — the "Summaries" list in the You tab. A post summarized again
/// replaces its older entry. Kept to the last [max].
@MainActor @Observable
final class SummaryStore: UserScoped {
    private static let max = 200

    // One writer at a time, in order: parallel writes could land out of order
    // or interleave and corrupt the file (which then loads as empty).
    @ObservationIgnored private let io = DispatchQueue(label: "ilay.summaries")
    @ObservationIgnored private let filesDir: URL
    @ObservationIgnored private var file: URL
    // The account's file hasn't loaded yet: summaries made meanwhile wait here,
    // so they're merged into it instead of overwriting it.
    @ObservationIgnored private var loaded = false
    @ObservationIgnored private var early: [SavedSummary] = []

    private(set) var items: [SavedSummary] = []

    init(filesDir: URL = FileLocations.files) {
        self.filesDir = filesDir
        file = filesDir.appendingPathComponent("summaries.json")
    }

    private static func with(_ list: [SavedSummary], _ s: SavedSummary) -> [SavedSummary] {
        Array(([s] + list.filter { $0.postId != s.postId }).prefix(max))
    }

    func add(_ s: SavedSummary) {
        items = SummaryStore.with(items, s)
        if !loaded {
            early.append(s)
            return
        }
        save()
    }

    func remove(_ postId: String) { removeAll([postId]) }

    func removeAll(_ postIds: Set<String>) {
        items = items.filter { !postIds.contains($0.postId) }
        save()
    }

    private func save() {
        let f = file
        let json = JsonElement.array(items.map(\.json)).encoded()
        io.async {
            // Atomic: written to a temp file and swapped in, so a crash mid-write can't truncate it.
            try? Data(json.utf8).write(to: f, options: .atomic)
        }
    }

    func onUserChanged(_ username: String) {
        let f = filesDir.appendingPathComponent(username.isEmpty ? "summaries.json" : "summaries_\(username.lowercased()).json")
        file = f
        items = []
        loaded = false
        early = []
        io.async { [weak self] in
            let rows = (try? Data(contentsOf: f)).flatMap { try? AppJson.parse($0) }.arr() ?? []
            let list = rows.compactMap(SavedSummary.init(json:))
            Task { @MainActor in
                guard let self, self.file == f else { return }
                self.loaded = true
                let pending = self.early
                self.early = []
                var merged = list
                for s in pending { merged = SummaryStore.with(merged, s) }
                self.items = merged
                if !pending.isEmpty { self.save() }
            }
        }
    }
}
