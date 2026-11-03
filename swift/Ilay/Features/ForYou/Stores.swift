import Foundation
import Observation

// The on-device For You model. All local and per account: every store keys
// its prefs entry with `userScopedKey` and reloads in [load] when the account
// changes. JSON formats are identical to the Flutter build's, so migrated
// data and backups carry over.
//
// The stores are main-actor state; the ranker runs off it, so it gets plain
// snapshots of them ([scorer], [topKeywordFinder], [idfFunction], [counter]).

private func readJson(_ prefs: Prefs, _ key: String) -> JsonObject {
    prefs.getString(key).flatMap(parseJsonOrNull).obj() ?? JsonObject()
}

private struct NotANumber: Error {}

private func num(_ e: JsonElement?) throws -> Double {
    guard let d = e.double() else { throw NotANumber() }
    return d
}

private func doublesObject(_ m: OrderedMap<Double>, extra: JsonObject = [:]) -> String {
    var o = JsonObject()
    for (k, v) in m { o[k] = .double(v) }
    for (k, v) in extra { o[k] = v }
    return o.encoded()
}

private func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(max(v, lo), hi) }

/// On-device interest model: a per-subreddit affinity score that learns from
/// the user's own actions (upvote / downvote / save / open / comment / share).
/// Entirely local — it never leaves the device and powers "For You".
/// Weights decay daily so the feed tracks your *current* taste.
@MainActor @Observable
final class InterestStore {
    private static let base = "interest_weights"
    private static let decayPerDay = 0.95

    @ObservationIgnored private let prefs: Prefs
    @ObservationIgnored private let trackHistory: () -> Bool
    @ObservationIgnored private var key = InterestStore.base
    @ObservationIgnored private var ts: Int? // when the weights were last decayed + saved
    private(set) var value = OrderedMap<Double>()

    init(prefs: Prefs, trackHistory: @escaping () -> Bool) {
        self.prefs = prefs
        self.trackHistory = trackHistory
    }

    func load(_ username: String) {
        key = userScopedKey(prefs, username, InterestStore.base)
        ts = nil
        value = OrderedMap()
        guard let raw = prefs.getString(key), let m = parseJsonOrNull(raw).obj() else { return }
        ts = m["_ts"].long()
        var w = OrderedMap<Double>()
        do {
            for (k, v) in m where !k.hasPrefix("_") { w[k] = try num(v) }
        } catch {
            return
        }
        value = decayed(w)
        if ts != nil { ts = nowMillis() } // decay owed is applied: don't apply it again
    }

    /// Applies the decay owed since the last save. Done on every change, not
    /// just at startup: an app left running for days used to save undecayed
    /// weights with a fresh timestamp, losing that decay for good.
    private func decayed(_ w: OrderedMap<Double>) -> OrderedMap<Double> {
        let f = decayFactor(ts, perDay: InterestStore.decayPerDay)
        if f > 0.999 { return w }
        var out = OrderedMap<Double>()
        for (k, v) in w where abs(v * f) >= 0.3 { out[k] = v * f }
        return out
    }

    func weightFor(_ subreddit: String) -> Double { value[subreddit.lowercased()] ?? 0.0 }

    func bump(_ subreddit: String, _ delta: Double) {
        if subreddit.isEmpty || delta == 0.0 { return }
        // Only learn when history/personalization tracking is enabled.
        if !trackHistory() { return }
        let k = subreddit.lowercased()
        var next = decayed(value)
        next[k] = clamp((next[k] ?? 0.0) + delta, -8.0, 40.0)
        persist(next)
    }

    /// Seeds affinity from the user's own history (cold start); never lowers.
    func seed(_ deltas: [String: Double]) {
        if deltas.isEmpty { return }
        let current = decayed(value)
        var next = current
        for (k, d) in deltas { next[k] = clamp((current[k] ?? 0.0) + d, -8.0, 40.0) }
        persist(next)
    }

    /// Top affinity subreddits above [min], strongest first.
    func top(_ n: Int, min minWeight: Double = 1.0) -> [String] {
        Array(value.filter { $0.value >= minWeight }.sorted { $0.value > $1.value }.prefix(n).map(\.key))
    }

    /// Forgets the learned affinity for one subreddit (used by the "Manage For
    /// You" screen to undo a "show less"/"show more"). Works regardless of the
    /// track-history setting.
    func reset(_ subreddit: String) {
        let k = subreddit.lowercased()
        guard value[k] != nil else { return }
        var next = value
        next.removeValue(forKey: k)
        persist(next)
    }

    func clear() {
        value = OrderedMap()
        prefs.remove(key)
    }

    private func persist(_ m: OrderedMap<Double>) {
        let now = nowMillis()
        ts = now
        value = m
        prefs.setString(key, doublesObject(m, extra: ["_ts": .int(now)]))
    }
}

/// Subreddits the user muted from the "For You" feed (local only).
@MainActor @Observable
final class MutedSubsStore {
    private static let base = "muted_subs"

    @ObservationIgnored private let prefs: Prefs
    @ObservationIgnored private var key = MutedSubsStore.base
    private(set) var value: [String] = []

    init(prefs: Prefs) { self.prefs = prefs }

    func load(_ username: String) {
        key = userScopedKey(prefs, username, MutedSubsStore.base)
        value = (prefs.getStringList(key) ?? []).uniqued()
    }

    func contains(_ sub: String) -> Bool { value.contains(sub.lowercased()) }

    func toggle(_ sub: String) {
        let k = sub.lowercased()
        if value.contains(k) { value.removeAll { $0 == k } } else { value.append(k) }
        prefs.setStringList(key, value)
    }
}

/// Learns which title keywords you engage with (upvote/save → +, downvote →
/// −). Powers within-subreddit taste ("F1 but not NBA") and keyword-matched
/// discovery. Local-only; decays like the interest store.
@MainActor @Observable
final class KeywordStore {
    private static let base = "keyword_weights"
    private static let cap = 400
    private static let decayPerDay = 0.97

    @ObservationIgnored private let prefs: Prefs
    @ObservationIgnored private let trackHistory: () -> Bool
    @ObservationIgnored private var key = KeywordStore.base
    @ObservationIgnored private var ts: Int?

    // When each word was last reinforced (days since epoch), so a full store
    // evicts what's weak *and* stale — not the word that just arrived.
    @ObservationIgnored private var lastUsed = OrderedMap<Int>()
    private(set) var value = OrderedMap<Double>()

    init(prefs: Prefs, trackHistory: @escaping () -> Bool) {
        self.prefs = prefs
        self.trackHistory = trackHistory
    }

    private func today() -> Int { nowMillis() / 86_400_000 }

    func load(_ username: String) {
        key = userScopedKey(prefs, username, KeywordStore.base)
        ts = nil
        lastUsed = OrderedMap()
        value = OrderedMap()
        guard let raw = prefs.getString(key), let m = parseJsonOrNull(raw).obj() else { return }
        ts = m["_ts"].long()
        var w = OrderedMap<Double>()
        do {
            if let lu = m["_lu"].obj() {
                for (k, v) in lu { lastUsed[k] = Int(try num(v)) }
            }
            for (k, v) in m where !k.hasPrefix("_") { w[k] = try num(v) }
        } catch {
            return
        }
        value = decayed(w)
        if ts != nil { ts = nowMillis() } // decay owed is applied: don't apply it again
    }

    private func decayed(_ w: OrderedMap<Double>) -> OrderedMap<Double> {
        let f = decayFactor(ts, perDay: KeywordStore.decayPerDay)
        if f > 0.999 { return w }
        var out = OrderedMap<Double>()
        for (k, v) in w where abs(v * f) >= 0.2 { out[k] = v * f }
        return out
    }

    /// Learns from a post title. [delta] applies per keyword (+1 up, −1 down).
    func bumpTitle(_ title: String, _ delta: Double) {
        if delta == 0.0 || !trackHistory() { return }
        let words = titleKeywords(title)
        if words.isEmpty { return }
        var next = decayed(value)
        let today = today()
        for w in words {
            next[w] = clamp((next[w] ?? 0.0) + delta, -10.0, 10.0)
            lastUsed[w] = today
        }
        evict(&next, keep: Set(words))
        persist(next)
    }

    /// Seeds weights for a batch of titles (cold start).
    func seedTitles<S: Sequence>(_ titles: S, _ delta: Double) where S.Element == String {
        var next = decayed(value)
        let today = today()
        for t in titles {
            for w in titleKeywords(t) {
                next[w] = clamp((next[w] ?? 0.0) + delta, -10.0, 10.0)
                lastUsed[w] = today
            }
        }
        evict(&next)
        persist(next)
    }

    // Bounded: drop the words with the least |weight| × recency.
    private func evict(_ m: inout OrderedMap<Double>, keep: Set<String> = []) {
        if m.count <= KeywordStore.cap { return }
        let today = today()
        func score(_ k: String, _ v: Double) -> Double {
            abs(v) * exp(-Double(today - (lastUsed[k] ?? (today - 60))) / 30.0)
        }
        let victims = m.filter { !keep.contains($0.key) }
            .sorted { score($0.key, $0.value) < score($1.key, $1.value) }
            .prefix(m.count - KeywordStore.cap).map(\.key)
        for k in victims {
            m.removeValue(forKey: k)
            lastUsed.removeValue(forKey: k)
        }
    }

    /// Total affinity of a title against the learned keywords, each word
    /// weighted by how distinctive it is ([idf], 1 = average).
    func scoreTitle(_ title: String, idf: ((String) -> Double)? = nil) -> Double {
        KeywordStore.score(value, title, idf)
    }

    /// The strongest learned keyword present in [title] (for explainability),
    /// preferring distinctive words over generic ones like "help".
    func topKeywordIn(_ title: String, idf: ((String) -> Double)? = nil) -> String? {
        KeywordStore.topKeyword(value, title, idf)
    }

    /// [scoreTitle] over a snapshot of the weights, callable off the main actor.
    func scorer(idf: ((String) -> Double)?) -> (String) -> Double {
        let weights = value
        return { KeywordStore.score(weights, $0, idf) }
    }

    /// [topKeywordIn] over a snapshot of the weights, callable off the main actor.
    func topKeywordFinder(idf: ((String) -> Double)?) -> (String) -> String? {
        let weights = value
        return { KeywordStore.topKeyword(weights, $0, idf) }
    }

    private nonisolated static func score(_ s: OrderedMap<Double>, _ title: String, _ idf: ((String) -> Double)?) -> Double {
        if s.isEmpty { return 0.0 }
        var sum = 0.0
        for w in titleKeywords(title) { sum += (s[w] ?? 0.0) * (idf?(w) ?? 1.0) }
        return clamp(sum, -6.0, 8.0)
    }

    private nonisolated static func topKeyword(_ s: OrderedMap<Double>, _ title: String, _ idf: ((String) -> Double)?) -> String? {
        var best: String?
        var bestW = 2.0 // only surface meaningful signals
        for w in titleKeywords(title) {
            let v = (s[w] ?? 0.0) * (idf?(w) ?? 1.0)
            if v > bestW {
                bestW = v
                best = w
            }
        }
        return best
    }

    /// Forgets one learned word (Manage For You → Topics → Reset).
    func reset(_ word: String) {
        guard value[word] != nil else { return }
        lastUsed.removeValue(forKey: word)
        var next = value
        next.removeValue(forKey: word)
        persist(next)
    }

    func clear() {
        value = OrderedMap()
        lastUsed = OrderedMap()
        prefs.remove(key)
    }

    private func persist(_ m: OrderedMap<Double>) {
        let now = nowMillis()
        ts = now
        value = m
        for k in lastUsed.keys where m[k] == nil { lastUsed.removeValue(forKey: k) }
        var lu = JsonObject()
        for (k, v) in lastUsed { lu[k] = .int(v) }
        prefs.setString(key, doublesObject(m, extra: ["_ts": .int(now), "_lu": .object(lu)]))
    }
}

/// Counts how many times each post was *seen* in the For You feed (≥60% on
/// screen for a second). The count fades — halving every 24h — so a post you
/// skimmed once isn't buried for good, and is counted at most once per app
/// session. Bounded (~600 ids), per-account, and only kept while history
/// tracking is on.
@MainActor @Observable
final class ImpressionStore {
    typealias Entry = (count: Double, at: Int)

    private static let base = "fy_impressions"
    private static let cap = 600

    @ObservationIgnored private let prefs: Prefs
    @ObservationIgnored private let trackHistory: () -> Bool
    @ObservationIgnored private var key = ImpressionStore.base
    @ObservationIgnored private var session = Set<String>() // ids already counted this app session
    @ObservationIgnored private var pending: [String] = []
    @ObservationIgnored private var flushScheduled = false
    private(set) var state = OrderedMap<Entry>()

    init(prefs: Prefs, trackHistory: @escaping () -> Bool) {
        self.prefs = prefs
        self.trackHistory = trackHistory
    }

    func load(_ username: String) {
        // Impressions waiting for the batched save belong to the account that
        // saw them: save them there before switching, not into the next one.
        flush()
        session = []
        key = userScopedKey(prefs, username, ImpressionStore.base)
        state = OrderedMap()
        guard let raw = prefs.getString(key), let o = parseJsonOrNull(raw).obj() else { return }
        let now = nowMillis()
        var out = OrderedMap<Entry>()
        do {
            for (k, v) in o {
                if let a = v.arr() {
                    guard a.count > 1 else { throw NotANumber() }
                    out[k] = (try num(a[0]), Int(try num(a[1])))
                } else {
                    out[k] = (try num(v), now) // legacy: plain count
                }
            }
            state = out
        } catch {}
    }

    /// How many times [postId] has been seen, faded (halves every 24h).
    func count(_ postId: String) -> Double { ImpressionStore.count(state, postId) }

    private nonisolated static func count(_ s: OrderedMap<Entry>, _ postId: String) -> Double {
        guard let v = s[postId] else { return 0.0 }
        return v.count * decayFactor(v.at, perDay: 0.5)
    }

    /// [count] over a snapshot, callable off the main actor.
    func counter() -> (String) -> Double {
        let snapshot = state
        return { ImpressionStore.count(snapshot, $0) }
    }

    /// Records one impression (cheap: batched, once per session per post).
    func record(_ postId: String) {
        if postId.isEmpty || !session.insert(postId).inserted { return }
        if !trackHistory() { return }
        pending.append(postId)
        if flushScheduled { return }
        flushScheduled = true
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.flush()
        }
    }

    private func flush() {
        flushScheduled = false
        if pending.isEmpty { return }
        let now = nowMillis()
        var next = state
        for id in pending {
            let c = count(id)
            next.removeValue(forKey: id) // re-insert last: insertion order = recency
            next[id] = (c + 1, now)
        }
        pending = []
        while next.count > ImpressionStore.cap { next.removeFirst() }
        state = next
        var o = JsonObject()
        for (k, v) in next { o[k] = [.double(v.count), .int(v.at)] }
        prefs.setString(key, o.encoded())
    }

    func clear() {
        state = OrderedMap()
        prefs.remove(key)
    }
}

/// "More / Less from r/x" and "More / Less about 'topic'": what the user
/// *asked* for, kept apart from learned behaviour. Doesn't fade, isn't wiped
/// by resetting a learned weight, and works with history tracking off —
/// explicit controls shouldn't depend on passive tracking.
struct ExplicitPrefs: Equatable, Sendable {
    var subs: OrderedMap<Int> = [:] // lowercase subreddit → +1 / −1
    var topics: OrderedMap<Int> = [:] // keyword (titleKeywords form) → +1 / −1

    var isEmpty: Bool { subs.isEmpty && topics.isEmpty }
}

@MainActor @Observable
final class ExplicitPrefsStore {
    private static let base = "fy_explicit"

    @ObservationIgnored private let prefs: Prefs
    @ObservationIgnored private var key = ExplicitPrefsStore.base
    private(set) var value = ExplicitPrefs()

    init(prefs: Prefs) { self.prefs = prefs }

    func load(_ username: String) {
        key = userScopedKey(prefs, username, ExplicitPrefsStore.base)
        let m = readJson(prefs, key)
        func g(_ k: String) throws -> OrderedMap<Int> {
            var out = OrderedMap<Int>()
            if let o = m[k].obj() {
                for (kk, v) in o { out[kk] = Int(try num(v)) }
            }
            return out
        }
        value = (try? ExplicitPrefs(subs: g("subs"), topics: g("topics"))) ?? ExplicitPrefs()
    }

    private func set(_ p: ExplicitPrefs) {
        value = p
        func object(_ m: OrderedMap<Int>) -> JsonElement {
            var o = JsonObject()
            for (k, v) in m { o[k] = .int(v) }
            return .object(o)
        }
        let json: JsonElement = ["subs": object(p.subs), "topics": object(p.topics)]
        prefs.setString(key, json.encoded())
    }

    /// [v] +1 (more), −1 (less) or 0 (forget).
    func setSub(_ sub: String, _ v: Int) {
        var next = value.subs
        next.removeValue(forKey: sub.lowercased())
        if v != 0 { next[sub.lowercased()] = v }
        set(ExplicitPrefs(subs: next, topics: value.topics))
    }

    func setTopic(_ topic: String, _ v: Int) {
        var next = value.topics
        next.removeValue(forKey: topic)
        if v != 0 { next[topic] = v }
        set(ExplicitPrefs(subs: value.subs, topics: next))
    }

    func clear() { set(ExplicitPrefs()) }
}

/// How often each subreddit's posts were seen in For You vs engaged with
/// (opened, read 30s+, voted). Lets the ranker learn *rates*: a subreddit you
/// keep scrolling past fades on its own, and a niche one you always open
/// rises even with few impressions. Decays like the interest model.
@MainActor @Observable
final class SubStatsStore {
    typealias Entry = (seen: Double, engaged: Double)

    static let defaultBase = "fy_substats"
    private static let decayPerDay = 0.95
    private static let cap = 400

    @ObservationIgnored private let prefs: Prefs
    @ObservationIgnored private let trackHistory: () -> Bool
    @ObservationIgnored private let base: String
    @ObservationIgnored private var key: String
    @ObservationIgnored private var ts: Int?
    private(set) var value = OrderedMap<Entry>()

    init(prefs: Prefs, trackHistory: @escaping () -> Bool, base: String = SubStatsStore.defaultBase) {
        self.prefs = prefs
        self.trackHistory = trackHistory
        self.base = base
        key = base
    }

    func load(_ username: String) {
        key = userScopedKey(prefs, username, base)
        let m = readJson(prefs, key)
        do {
            ts = m["_ts"].long()
            let f = decayFactor(ts, perDay: SubStatsStore.decayPerDay)
            var out = OrderedMap<Entry>()
            for (k, v) in m where !k.hasPrefix("_") {
                guard let a = v.arr(), a.count > 1 else { throw NotANumber() }
                out[k] = (try num(a[0]) * f, try num(a[1]) * f)
            }
            if ts != nil { ts = nowMillis() } // decay owed is applied: don't apply it again
            value = out
        } catch {
            ts = nil
            value = OrderedMap()
        }
    }

    private func add(_ sub: String, impr: Double, eng: Double) {
        if !trackHistory() { return }
        let f = decayFactor(ts, perDay: SubStatsStore.decayPerDay)
        var next = OrderedMap<Entry>()
        for (k, v) in value where v.seen * f >= 0.05 { next[k] = (v.seen * f, v.engaged * f) }
        let k = sub.lowercased()
        let cur = next.removeValue(forKey: k) ?? (0.0, 0.0)
        next[k] = (cur.seen + impr, cur.engaged + eng)
        while next.count > SubStatsStore.cap { next.removeFirst() }
        let now = nowMillis()
        ts = now
        value = next
        var o: JsonObject = ["_ts": .int(now)]
        for (kk, v) in next { o[kk] = [.double(v.seen), .double(v.engaged)] }
        prefs.setString(key, o.encoded())
    }

    func impression(_ sub: String) { add(sub, impr: 1.0, eng: 0.0) }
    func engaged(_ sub: String) { add(sub, impr: 0.0, eng: 1.0) }

    func clear() {
        value = OrderedMap()
        prefs.remove(key)
    }
}

/// How many candidate titles each word appeared in (decayed), so learned
/// keywords are weighted by how distinctive they are: "verstappen" says far
/// more about you than "help". Updated from every For You build.
@MainActor @Observable
final class DocFreqStore {
    private static let base = "fy_docfreq"
    private static let decayPerDay = 0.9
    private static let cap = 2000

    @ObservationIgnored private let prefs: Prefs
    @ObservationIgnored private var key = DocFreqStore.base
    @ObservationIgnored private var ts: Int?
    @ObservationIgnored private var docs = 0.0 // decayed number of titles seen
    private(set) var state = OrderedMap<Double>()

    init(prefs: Prefs) { self.prefs = prefs }

    func load(_ username: String) {
        key = userScopedKey(prefs, username, DocFreqStore.base)
        let m = readJson(prefs, key)
        do {
            ts = m["_ts"].long()
            let f = decayFactor(ts, perDay: DocFreqStore.decayPerDay)
            docs = (m["_n"].double() ?? 0.0) * f
            var out = OrderedMap<Double>()
            for (k, v) in m where !k.hasPrefix("_") { out[k] = try num(v) * f }
            if ts != nil { ts = nowMillis() } // decay owed is applied: don't apply it again
            state = out
        } catch {
            ts = nil
            docs = 0.0
            state = OrderedMap()
        }
    }

    func observe<S: Sequence>(_ titles: S) where S.Element == String {
        let f = decayFactor(ts, perDay: DocFreqStore.decayPerDay)
        var next = OrderedMap<Double>()
        for (k, v) in state { next[k] = v * f }
        var d = docs * f
        for t in titles {
            d += 1
            for w in titleKeywords(t).uniqued() {
                // The running count (already decayed above), +1 for this title:
                // the stored count used to be read for every title, so a word
                // in 100 titles of one batch was counted once.
                let c = next.removeValue(forKey: w) ?? 0.0
                next[w] = c + 1 // re-insert: recency order
            }
        }
        while next.count > DocFreqStore.cap { next.removeFirst() }
        let now = nowMillis()
        ts = now
        docs = d
        state = next
        prefs.setString(key, doublesObject(next, extra: ["_ts": .int(now), "_n": .double(d)]))
    }

    /// Rarity weight for [word], normalised so a typical word is ~1: rare words
    /// count up to 2×, very common ones as little as 0.2×.
    func idf(_ word: String) -> Double { DocFreqStore.idf(docs, state, word) }

    /// [idf] over a snapshot, callable off the main actor.
    func idfFunction() -> (String) -> Double {
        let (n, snapshot) = (docs, state)
        return { DocFreqStore.idf(n, snapshot, $0) }
    }

    private nonisolated static func idf(_ n: Double, _ s: OrderedMap<Double>, _ word: String) -> Double {
        if n < 50 { return 1.0 } // not enough data yet
        let v = log((n + 1) / ((s[word] ?? 0.0) + 1))
        let typical = log((n + 1) / 4) // seen in ~3 of N titles
        return clamp(v / typical, 0.2, 2.0)
    }

    func clear() {
        state = OrderedMap()
        docs = 0.0
        prefs.remove(key)
    }
}

/// Rolling 7-day counters of how For You performs (impressions, opens,
/// 30s+ reads, votes, More/Less taps, split by primary vs discovery and by
/// source). On-device only, never uploaded, and only kept while history
/// tracking is on. Shown on a hidden debug screen in Manage For You, and used
/// to adapt how much discovery the feed mixes in.
@MainActor @Observable
final class ForYouMetrics {
    private static let base = "fy_metrics"

    @ObservationIgnored private let prefs: Prefs
    @ObservationIgnored private let trackHistory: () -> Bool
    @ObservationIgnored private var key = ForYouMetrics.base
    private(set) var state: [String: [String: Int]] = [:]

    init(prefs: Prefs, trackHistory: @escaping () -> Bool) {
        self.prefs = prefs
        self.trackHistory = trackHistory
    }

    // yyyy-MM-dd, local date.
    private func day(_ daysAgo: Int) -> String {
        let cal = Calendar(identifier: .gregorian)
        let c = cal.dateComponents([.year, .month, .day], from: cal.date(byAdding: .day, value: -daysAgo, to: Date())!)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    func load(_ username: String) {
        key = userScopedKey(prefs, username, ForYouMetrics.base)
        let m = readJson(prefs, key)
        var out: [String: [String: Int]] = [:]
        do {
            for (d, v) in m {
                guard let o = v.obj() else { throw NotANumber() }
                var bucket: [String: Int] = [:]
                for (k, c) in o { bucket[k] = Int(try num(c)) }
                out[d] = bucket
            }
            state = out
        } catch {
            state = [:]
        }
    }

    func count(_ metric: String, _ n: Int = 1) {
        if !trackHistory() { return }
        let keep = Set((0..<7).map(day))
        let today = day(0)
        var next = state.filter { keep.contains($0.key) }
        next[today, default: [:]][metric, default: 0] += n
        state = next
        var o = JsonObject()
        for d in next.keys.sorted() {
            var b = JsonObject()
            for (k, c) in next[d]!.sorted(by: { $0.key < $1.key }) { b[k] = .int(c) }
            o[d] = .object(b)
        }
        prefs.setString(key, o.encoded())
    }

    /// Totals over the last 7 days.
    func totals() -> [String: Int] {
        var out: [String: Int] = [:]
        for d in state.values {
            for (k, v) in d { out[k, default: 0] += v }
        }
        return out
    }

    /// How often discovery posts get opened relative to primary ones (1 =
    /// same). Drives the adaptive discovery share; 1 until there's data.
    func discoveryAppetite() -> Double {
        let t = totals()
        let di = t["impr.discovery"] ?? 0
        let pi = t["impr.primary"] ?? 0
        if di < 30 || pi < 30 { return 1.0 }
        let dr = (Double(t["open.discovery"] ?? 0) + 1.0) / Double(di + 6)
        let pr = (Double(t["open.primary"] ?? 0) + 1.0) / Double(pi + 6)
        return dr / pr
    }

    func clear() {
        state = [:]
        prefs.remove(key)
    }
}

/// What the ranker knew about a post it placed: where it came from, whether
/// it was a discovery pick, and the factors behind its score (for "Why am I
/// seeing this?" and the metrics).
struct ForYouMeta: Equatable, Sendable {
    let source: String // best / rising / popular / favourite / interest / community
    let discovery: Bool
    let position: Int // 0-based slot on its page
    let why: [String]
}
