import Foundation

/// When each thread was last opened (post id → millis), so comments posted
/// since can be highlighted on the next visit. Local, per-account, bounded,
/// and only recorded while history tracking is on.
@MainActor
final class ThreadVisits: UserScoped {
    private static let base = "thread_visits"
    private static let cap = 300

    private let prefs: Prefs
    private let settings: SettingsStore
    private var key = ThreadVisits.base
    private var visits = OrderedMap<Int>()

    init(prefs: Prefs, settings: SettingsStore) {
        self.prefs = prefs
        self.settings = settings
    }

    func onUserChanged(_ username: String) {
        key = userScopedKey(prefs, username, ThreadVisits.base)
        visits = OrderedMap()
        guard let raw = prefs.getString(key), let o = parseJsonOrNull(raw).obj() else { return }
        for (k, v) in o {
            if let t = v.long() { visits[k] = t }
        }
    }

    /// The previous visit to [postId] (millis), or nil on a first visit.
    func lastVisit(_ postId: String) -> Int? { visits[postId] }

    func clear() {
        visits = OrderedMap()
        prefs.remove(key)
    }

    func record(_ postId: String) {
        if !settings.value.trackHistory { return }
        visits.removeValue(forKey: postId)
        visits[postId] = nowMillis() // newest last
        while visits.count > ThreadVisits.cap { visits.removeFirst() }
        var o = JsonObject()
        for (k, t) in visits { o[k] = .int(t) }
        prefs.setString(key, o.encoded())
    }
}
