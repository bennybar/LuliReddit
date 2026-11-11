import Foundation
import Observation

/// A locally-stored record of a viewed post. History is on-device only.
struct HistoryEntry: Equatable, Sendable {
    let id: String
    let subreddit: String
    let title: String
    let permalink: String
    var viewedAt: Int = 0 // millis since epoch; 0 = legacy/unknown
    // For "Hide NSFW posts"; absent in older entries (unknown: shown).
    var nsfw: Bool = false
    // The community's picture (#155); absent in older entries.
    var icon: String? = nil
}

/// Viewed posts, newest first, per account (prefs `history_<user>`, a JSON
/// string list). The History page shows the newest `cap`; which posts were read
/// is kept much longer in a compact id list (`readIds_<user>`, "id:secs"
/// comma-joined, newest first, the same as Android) so "Hide read posts" and the
/// read dimming don't forget a post after a few days of marking read as you
/// scroll (#148).
@MainActor @Observable
final class HistoryStore: UserScoped {
    private static let base = "history"
    private static let cap = 500
    private static let readBase = "readIds"
    private static let readCap = 5000

    @ObservationIgnored private let prefs: Prefs
    @ObservationIgnored private var key = HistoryStore.base
    @ObservationIgnored private var readKey = HistoryStore.readBase
    // (id, viewed at in seconds), newest first.
    @ObservationIgnored private var read: [(id: String, at: Int)] = []
    private(set) var state: [HistoryEntry] = []

    /// Ids for O(1) "seen?" checks (feeds dim read posts).
    private(set) var ids: Set<String> = []

    init(prefs: Prefs) { self.prefs = prefs }

    func onUserChanged(_ username: String) {
        key = userScopedKey(prefs, username, HistoryStore.base)
        let list: [HistoryEntry] = (prefs.getStringList(key) ?? []).compactMap { s in
            guard let j = parseJsonOrNull(s) else { return nil }
            return HistoryEntry(
                id: j["id"].str() ?? "",
                subreddit: j["sub"].str() ?? "",
                title: j["title"].str() ?? "",
                permalink: j["permalink"].str() ?? "",
                viewedAt: j["ts"].long() ?? 0,
                nsfw: j["nsfw"].isTrue(),
                icon: j["icon"].str()
            )
        }
        readKey = userScopedKey(prefs, username, HistoryStore.readBase)
        if let stored = prefs.getString(readKey) {
            read = stored.split(separator: ",").compactMap { pair in
                guard let i = pair.firstIndex(of: ":"), i > pair.startIndex else { return nil }
                return (String(pair[..<i]), Int(pair[pair.index(after: i)...]) ?? 0)
            }
        } else {
            // First run with the long list: start it from history.
            read = list.map { ($0.id, $0.viewedAt / 1000) }
        }
        publish(list)
    }

    func contains(_ id: String) -> Bool { ids.contains(id) }

    func markViewed(_ p: Post) {
        let entry = HistoryEntry(id: p.id, subreddit: p.subreddit, title: p.title, permalink: p.permalink, viewedAt: nowMillis(), nsfw: p.over18, icon: p.subredditIcon)
        read = [(p.id, entry.viewedAt / 1000)] + read.lazy.filter { $0.id != p.id }.prefix(HistoryStore.readCap - 1)
        publish(Array(([entry] + state.filter { $0.id != p.id }).prefix(HistoryStore.cap)))
        persist()
    }

    func removeViewed(_ id: String) {
        read.removeAll { $0.id == id }
        publish(state.filter { $0.id != id })
        persist()
    }

    /// Undo of `removeViewed` (#154): the entry back in its place, by when it was read.
    func restore(_ e: HistoryEntry) {
        if ids.contains(e.id) { return }
        let at = e.viewedAt / 1000
        let i = read.firstIndex { $0.at <= at } ?? read.endIndex
        read.insert((e.id, at), at: i)
        publish(Array((state + [e]).sorted { $0.viewedAt > $1.viewedAt }.prefix(HistoryStore.cap)))
        persist()
    }

    /// Removes entries older than [ageMillis]; legacy entries (no timestamp) count as old.
    func clearOlderThan(_ ageMillis: Int) {
        let cutoff = nowMillis() - ageMillis
        read.removeAll { $0.at * 1000 < cutoff }
        publish(state.filter { $0.viewedAt >= cutoff })
        persist()
    }

    func clear() {
        read = []
        publish([])
        persist()
    }

    private func publish(_ list: [HistoryEntry]) {
        state = list
        ids = Set(read.map(\.id)).union(list.map(\.id))
    }

    private func persist() {
        prefs.setString(readKey, read.map { "\($0.id):\($0.at)" }.joined(separator: ","))
        prefs.setStringList(key, state.map { e in
            var o: JsonObject = [
                "id": .string(e.id), "sub": .string(e.subreddit), "title": .string(e.title),
                "permalink": .string(e.permalink), "ts": .int(e.viewedAt),
            ]
            // Only when set: SFW entries keep the shape older versions wrote.
            if e.nsfw { o["nsfw"] = .bool(true) }
            if let icon = e.icon { o["icon"] = .string(icon) }
            return JsonElement.object(o).encoded()
        })
    }
}
