import Foundation
import Observation

/// A per-account set of ids that each expire [ttl] (read each time, so a
/// setting can change it) after being added,
/// persisted as "id:millis" strings under [baseKey]. Local only — nothing is
/// sent to Reddit. Used for posts swiped away ("Dismiss", a day) and
/// subreddits hidden from Home / For You ("Hide r/… for 7 days").
@MainActor @Observable
final class ExpiringIds: UserScoped {
    @ObservationIgnored private let prefs: Prefs
    @ObservationIgnored private let baseKey: String
    @ObservationIgnored private let ttl: () -> Int
    @ObservationIgnored private var key: String
    @ObservationIgnored private var since = OrderedMap<Int>()
    // Wakes up when the next entry expires, so it un-hides while the app stays open.
    @ObservationIgnored private var expiryJob: Task<Void, Never>?

    private(set) var ids: Set<String> = []

    init(prefs: Prefs, baseKey: String, ttl: @escaping () -> Int) {
        self.prefs = prefs
        self.baseKey = baseKey
        self.ttl = ttl
        key = baseKey
    }

    func add(_ id: String) {
        since[id] = nowMillis()
        save()
    }

    func remove(_ id: String) {
        if since.removeValue(forKey: id) != nil { save() }
    }

    /// Re-applies the expiry (the time-to-live setting changed).
    func refresh() { save() }

    private func save() {
        let now = nowMillis()
        let ttlMillis = ttl()
        for (k, t) in since where now - t > ttlMillis { since.removeValue(forKey: k) }
        prefs.setStringList(key, since.map { "\($0.key):\($0.value)" })
        ids = Set(since.keys)
        expiryJob?.cancel()
        expiryJob = nil
        guard let next = since.values.min() else { return }
        expiryJob = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(max(next + ttlMillis - nowMillis(), 0) + 1_000))
            if !Task.isCancelled { self?.save() }
        }
    }

    func onUserChanged(_ username: String) {
        key = userScopedKey(prefs, username, baseKey)
        since = OrderedMap()
        for row in prefs.getStringList(key) ?? [] {
            guard let i = row.lastIndex(of: ":"), let t = Int(row[row.index(after: i)...]), i > row.startIndex else { continue }
            since[String(row[..<i])] = t
        }
        save() // drops the expired ones
    }
}
