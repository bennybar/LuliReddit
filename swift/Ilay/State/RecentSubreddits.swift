import Foundation
import Observation

/// A subreddit you opened, with what it takes to list it again without asking Reddit.
struct RecentSubreddit: Equatable, Sendable {
    let name: String
    let namePrefixed: String
    let iconUrl: String?
    let subscribers: Int
    let visitedAt: Int
    var visits = 1 // times opened, for the count and the "Most visited" order (#92)

    func asSubreddit() -> Subreddit {
        Subreddit(name: name, namePrefixed: namePrefixed, title: "", description: "", subscribers: subscribers, iconUrl: iconUrl)
    }
}

/// The subreddits you opened last, newest first, per account and on-device only
/// (prefs `recent_subreddits_<user>`, a JSON string list, each with its visit
/// count). Whether you're subscribed doesn't matter (#63).
///
/// More are remembered than listed, so with [byVisits] ("Most visited", #92) a
/// subreddit you open often keeps its count and its place while others come and go.
@MainActor @Observable
final class RecentSubreddits: UserScoped {
    private static let base = "recent_subreddits"
    private static let cap = 5 // listed
    private static let keep = 100 // remembered, with their counts

    @ObservationIgnored private let prefs: Prefs
    @ObservationIgnored private let byVisits: () -> Bool
    @ObservationIgnored private var key = RecentSubreddits.base
    @ObservationIgnored private var all: [RecentSubreddit] = []
    /// The ones to list, in the order Settings picked.
    private(set) var state: [RecentSubreddit] = []

    init(prefs: Prefs, byVisits: @escaping () -> Bool) {
        self.prefs = prefs
        self.byVisits = byVisits
    }

    func onUserChanged(_ username: String) {
        key = userScopedKey(prefs, username, RecentSubreddits.base)
        all = (prefs.getStringList(key) ?? []).compactMap { s in
            let j = parseJsonOrNull(s)
            guard let name = j["name"].str(), let prefixed = j["prefixed"].str() else { return nil }
            return RecentSubreddit(
                name: name, namePrefixed: prefixed, iconUrl: j["icon"].str(), subscribers: j["members"].int() ?? 0, visitedAt: j["ts"].long() ?? 0,
                // Saved before visits were counted: once.
                visits: j["visits"].int() ?? 1
            )
        }
        refresh()
    }

    /// Re-applies the order after Settings changed it.
    func refresh() {
        state = RecentSubreddits.shown(all, byVisits: byVisits())
    }

    func visit(_ s: Subreddit) {
        let entry = RecentSubreddit(name: s.name, namePrefixed: s.namePrefixed, iconUrl: s.iconUrl, subscribers: s.subscribers, visitedAt: nowMillis())
        publish(RecentSubreddits.visited(all, entry))
    }

    /// Removes entries older than [ageMillis], with History's own clear options.
    func clearOlderThan(_ ageMillis: Int) {
        let cutoff = nowMillis() - ageMillis
        publish(all.filter { $0.visitedAt >= cutoff })
    }

    func clear() { publish([]) }

    /// Drops one subreddit from the list (#123).
    func remove(_ name: String) { publish(all.filter { $0.name.lowercased() != name.lowercased() }) }

    private func publish(_ list: [RecentSubreddit]) {
        all = list
        refresh()
        prefs.setStringList(key, list.map { e in
            let j: JsonElement = [
                "name": .string(e.name), "prefixed": .string(e.namePrefixed), "icon": .of(e.iconUrl),
                "members": .int(e.subscribers), "ts": .int(e.visitedAt), "visits": .int(e.visits),
            ]
            return j.encoded()
        })
    }

    /// [list] with [entry] first, once, whatever case its name came in, its visits counted.
    nonisolated static func visited(_ list: [RecentSubreddit], _ entry: RecentSubreddit) -> [RecentSubreddit] {
        var first = entry
        first.visits = (list.first { $0.name.lowercased() == entry.name.lowercased() }?.visits ?? 0) + 1
        return Array(([first] + list.filter { $0.name.lowercased() != entry.name.lowercased() }).prefix(keep))
    }

    /// The [cap] to list: newest first, or most visited first (ties: newest first).
    nonisolated static func shown(_ list: [RecentSubreddit], byVisits: Bool) -> [RecentSubreddit] {
        // Stable, as Kotlin's sortedByDescending: equal counts keep their order.
        let ordered = byVisits ? list.enumerated().sorted { ($0.element.visits, $1.offset) > ($1.element.visits, $0.offset) }.map(\.element) : list
        return Array(ordered.prefix(cap))
    }
}
