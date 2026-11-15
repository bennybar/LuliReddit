import Foundation

/// When each thread was last opened (post id → millis), so comments posted
/// since can be highlighted on the next visit, and where you were in it (#179),
/// so it reopens there. Local, per-account, bounded, and only recorded while
/// history tracking is on.
@MainActor
final class ThreadVisits: UserScoped {
    private static let base = "thread_visits"
    private static let basePos = "thread_positions"
    private static let cap = 300

    private let prefs: Prefs
    private let settings: SettingsStore
    private var key = ThreadVisits.base
    private var visits = OrderedMap<Int>()
    private var posKey = ThreadVisits.basePos
    /// Post id → "<comment fullname> <offset>": the comment at the top of the screen when you left.
    private var positions = OrderedMap<String>()

    init(prefs: Prefs, settings: SettingsStore) {
        self.prefs = prefs
        self.settings = settings
    }

    func onUserChanged(_ username: String) {
        key = userScopedKey(prefs, username, ThreadVisits.base)
        posKey = userScopedKey(prefs, username, ThreadVisits.basePos)
        visits = OrderedMap()
        positions = OrderedMap()
        if let raw = prefs.getString(key), let o = parseJsonOrNull(raw).obj() {
            for (k, v) in o {
                if let t = v.long() { visits[k] = t }
            }
        }
        if let raw = prefs.getString(posKey), let o = parseJsonOrNull(raw).obj() {
            for (k, v) in o {
                if let p = v.str() { positions[k] = p }
            }
        }
    }

    /// Where you left [postId]: the comment then at the top of the screen and how far it was scrolled past.
    func lastPosition(_ postId: String) -> (fullname: String, offset: Int)? {
        guard let parts = positions[postId]?.split(separator: " "), parts.count == 2 else { return nil }
        return (String(parts[0]), Int(parts[1]) ?? 0)
    }

    /// Where you're leaving [postId]; a nil [fullname] (at the top) forgets it, so it opens at the top.
    func recordPosition(_ postId: String, fullname: String?, offset: Int) {
        if !settings.value.trackHistory { return }
        if let fullname {
            positions.removeValue(forKey: postId)
            positions[postId] = "\(fullname) \(offset)" // newest last
            while positions.count > ThreadVisits.cap { positions.removeFirst() }
        } else if positions.removeValue(forKey: postId) == nil {
            return
        }
        var o = JsonObject()
        for (k, p) in positions { o[k] = .string(p) }
        prefs.setString(posKey, o.encoded())
    }

    /// The previous visit to [postId] (millis), or nil on a first visit.
    func lastVisit(_ postId: String) -> Int? { visits[postId] }

    func clear() {
        visits = OrderedMap()
        positions = OrderedMap()
        prefs.remove(key)
        prefs.remove(posKey)
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
