import Foundation
import Observation

/// A subreddit you opened, with what it takes to list it again without asking Reddit.
struct RecentSubreddit: Equatable, Sendable {
    let name: String
    let namePrefixed: String
    let iconUrl: String?
    let subscribers: Int
    let visitedAt: Int

    func asSubreddit() -> Subreddit {
        Subreddit(name: name, namePrefixed: namePrefixed, title: "", description: "", subscribers: subscribers, iconUrl: iconUrl)
    }
}

/// The subreddits you opened last, newest first, per account and on-device only
/// (prefs `recent_subreddits_<user>`, a JSON string list). Whether you're
/// subscribed doesn't matter (#63).
@MainActor @Observable
final class RecentSubreddits: UserScoped {
    private static let base = "recent_subreddits"
    private static let cap = 5

    @ObservationIgnored private let prefs: Prefs
    @ObservationIgnored private var key = RecentSubreddits.base
    private(set) var state: [RecentSubreddit] = []

    init(prefs: Prefs) { self.prefs = prefs }

    func onUserChanged(_ username: String) {
        key = userScopedKey(prefs, username, RecentSubreddits.base)
        state = (prefs.getStringList(key) ?? []).compactMap { s in
            let j = parseJsonOrNull(s)
            guard let name = j["name"].str(), let prefixed = j["prefixed"].str() else { return nil }
            return RecentSubreddit(name: name, namePrefixed: prefixed, iconUrl: j["icon"].str(), subscribers: j["members"].int() ?? 0, visitedAt: j["ts"].long() ?? 0)
        }
    }

    func visit(_ s: Subreddit) {
        let entry = RecentSubreddit(name: s.name, namePrefixed: s.namePrefixed, iconUrl: s.iconUrl, subscribers: s.subscribers, visitedAt: nowMillis())
        publish(RecentSubreddits.visited(state, entry))
    }

    /// Removes entries older than [ageMillis], with History's own clear options.
    func clearOlderThan(_ ageMillis: Int) {
        let cutoff = nowMillis() - ageMillis
        publish(state.filter { $0.visitedAt >= cutoff })
    }

    func clear() { publish([]) }

    private func publish(_ list: [RecentSubreddit]) {
        state = list
        prefs.setStringList(key, list.map { e in
            let j: JsonElement = [
                "name": .string(e.name), "prefixed": .string(e.namePrefixed), "icon": .of(e.iconUrl),
                "members": .int(e.subscribers), "ts": .int(e.visitedAt),
            ]
            return j.encoded()
        })
    }

    /// [list] with [entry] first, once, whatever case its name came in.
    nonisolated static func visited(_ list: [RecentSubreddit], _ entry: RecentSubreddit) -> [RecentSubreddit] {
        Array(([entry] + list.filter { $0.name.lowercased() != entry.name.lowercased() }).prefix(cap))
    }
}
