import Foundation
import Observation

/// A search kept to run again: its words, where (nil = all of Reddit), sort and time range.
struct SavedSearch: Equatable, Sendable {
    let query: String
    let subreddit: String?
    let sort: String
    let time: String

    var key: String { "\((subreddit ?? "").lowercased())|\(query.lowercased())|\(sort)|\(time)" }
}

/// Searches pinned from the search screen, per account (prefs `saved_searches_<user>`). Newest first.
@MainActor @Observable
final class SavedSearches {
    @ObservationIgnored private let prefs: Prefs
    @ObservationIgnored private let username: () -> String
    private(set) var items: [SavedSearch] = []

    init(prefs: Prefs, username: @escaping () -> String) {
        self.prefs = prefs
        self.username = username
    }

    private func prefKey() -> String { userScopedKey(prefs, username(), "saved_searches") }

    /// Re-reads this account's list (the search screen calls it when it opens).
    func refresh() {
        let rows = prefs.getString(prefKey()).flatMap(parseJsonOrNull).arr() ?? []
        items = rows.compactMap { j in
            guard let q = j["q"].str() else { return nil }
            return SavedSearch(query: q, subreddit: j["sr"].str(), sort: j["sort"].str() ?? "relevance", time: j["t"].str() ?? "all")
        }
    }

    func contains(_ s: SavedSearch) -> Bool { items.contains { $0.key == s.key } }

    func add(_ s: SavedSearch) { persist([s] + items.filter { $0.key != s.key }) }

    func remove(_ s: SavedSearch) { persist(items.filter { $0.key != s.key }) }

    private func persist(_ next: [SavedSearch]) {
        items = next
        let json = JsonElement.array(next.map { s in
            var o: JsonObject = ["q": .string(s.query)]
            if let sr = s.subreddit { o["sr"] = .string(sr) }
            o["sort"] = .string(s.sort)
            o["t"] = .string(s.time)
            return .object(o)
        })
        prefs.setString(prefKey(), json.encoded())
    }
}
