import Foundation

// The Digest (docs/digest-spec.md): the notable posts of the last 24 hours in the
// communities you choose, kept per day. This file is the pure part (what gets picked,
// and how a refresh merges into the day), unit-tested like the Kotlin app's.

/// How long a digest is (Settings › Feed › Digest › Size). Persisted by index (`digestSize`).
enum DigestSize: Int, CaseIterable, Sendable {
    case brief, standard, everything

    static func of(_ i: Int) -> DigestSize { DigestSize(rawValue: i) ?? .standard }

    var items: Int { [5, 12, 30][rawValue] }
    var perCommunity: Int { [2, 2, 5][rawValue] }
    var label: String { ["Brief", "Standard", "Everything notable"][rawValue] }
    var description: String {
        ["About 5 posts, at most 2 from a community", "About 12 posts, at most 2 from a community", "Every notable post, up to 30"][rawValue]
    }
}

/// A post in a digest, with why it's there. `addedAt`: when this day's digest gained it;
/// `importance`: the AI's 1–5 rating (0: picked without AI).
struct DigestItem: Equatable, Sendable {
    var post: Post
    let why: String
    let notability: Double
    let addedAt: Int
    var importance = 0
}

/// Settings › Digest › Order by (`digestOrder`). `ai`: the AI's importance, without it as `notable`.
enum DigestOrder: Int, CaseIterable, Sendable {
    case notable, upvoted, newest, ai

    static func of(_ i: Int) -> DigestOrder { DigestOrder(rawValue: i) ?? .notable }

    var label: String { ["Most notable", "Most upvoted", "Newest", "AI's assessment"][rawValue] }
    var description: String {
        ["How much a post stands out in its own community", "The most points first", "The most recent first", "How important the AI rated it, then how notable"][rawValue]
    }
}

/// The AI's answer for a build: an overview (when asked for) and its verdicts, by post id.
struct DigestAi: Equatable, Sendable {
    let overview: String?
    let verdicts: [String: AiVerdict]
}

/// `importance`: 1–5; under 2 is never shown.
struct AiVerdict: Equatable, Sendable {
    let importance: Int
    let why: String
}

/// A candidate's verdict for the day, kept so a refresh doesn't judge it again (nor send
/// it to the AI again). `secondLook`: it already had its one re-check.
struct Judged: Equatable, Sendable {
    let picked: Bool
    let notability: Double
    let at: Int
    var secondLook = false
}

/// One day's digest (`day`: the local date, yyyy-MM-dd). `builtAt`: its first build;
/// `refreshedAt`: the last fetch; `seenAt`: when it was last looked at (an item added
/// after both is "New").
struct DigestDay: Equatable, Sendable {
    let day: String
    let builtAt: Int
    let refreshedAt: Int
    var seenAt: Int
    let items: [DigestItem]
    let judged: [String: Judged]
    /// The AI's paragraph about the day (its first build, when asked for).
    var overview: String? = nil
    /// The last build wanted the AI and couldn't have it: picked by activity instead.
    var aiFailed = false
    /// The last AI call for this day (0: none), for the automatic builds' 12-hour guard.
    var aiAt = 0

    func isNew(_ item: DigestItem) -> Bool { item.addedAt > builtAt && item.addedAt > seenAt }
}

/// At or above this, a post is notable: twice what's usual in its community.
let digestNotable = 2.0
/// A community's best post of the day counts even under `digestNotable`, but only above this.
let digestTopMin = 1.3
/// Fewer points and the numbers never pick it, however it compares in a quiet community.
let digestMinPoints = 10
private let dayMs = 24 * 60 * 60_000

/// How a post stands out in its own community, in this batch: its points against the
/// community's median, and (less) its comments against theirs. 1 = a typical post.
/// Relative, so a small community's big day counts as much as a big one's.
func notabilityOf(_ posts: [Post]) -> [String: Double] {
    var out: [String: Double] = [:]
    for group in Dictionary(grouping: posts, by: { $0.subreddit.lowercased() }).values {
        let score = max(median(group.map { Double($0.score) }), 1)
        let comments = max(median(group.map { Double($0.numComments) }), 1)
        for p in group {
            let points: Double = Double(max(p.score, 0)) / score
            let talk: Double = Double(p.numComments) / comments
            out[p.id] = 0.7 * points + 0.3 * talk
        }
    }
    return out
}

private func median(_ v: [Double]) -> Double {
    if v.isEmpty { return 0 }
    let s = v.sorted()
    return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
}

/// The line under a post saying why it's in the digest, from the numbers.
func digestWhy(_ p: Post, notability: Double, top: Bool) -> String {
    let comments = p.numComments > 0 ? " · \(compactNumber(p.numComments)) comments" : ""
    if top && notability < digestNotable { return "Top post today in r/\(p.subreddit)\(comments)" }
    let times: String
    if notability >= 10 {
        times = "\(Int(notability.rounded()))×"
    } else {
        let v = (notability * 10).rounded() / 10
        times = v == v.rounded() ? "\(Int(v))×" : "\(v)×"
    }
    return (top ? "Top post today in r/\(p.subreddit) · \(times) a typical post" : "\(times) a typical post there") + comments
}

/// The candidates of a build, as both the AI request and the merge see them.
private struct Batch {
    let today: DigestDay?
    let fresh: [Post]
    let notability: [String: Double]
    let tops: Set<String>
    let toJudge: [Post]
}

private func batch(_ prev: DigestDay?, day: String, candidates: [Post], now: Int, shownBefore: Set<String>) -> Batch {
    let today = prev?.day == day ? prev : nil
    var seenIds = Set<String>()
    // (Shown on an earlier day: a morning digest doesn't repeat last night's posts.)
    let fresh = candidates.filter {
        !$0.stickied && $0.createdUtc > 0 && now - $0.createdUtc <= dayMs && !shownBefore.contains($0.id) && seenIds.insert($0.id).inserted
    }
    let notability = notabilityOf(fresh)
    // Each community's best post today counts too, when it stands out a little.
    var tops = Set<String>()
    for group in Dictionary(grouping: fresh, by: { $0.subreddit.lowercased() }).values {
        if let best = group.max(by: { (notability[$0.id] ?? 0) < (notability[$1.id] ?? 0) }),
           (notability[best.id] ?? 0) >= digestTopMin {
            tops.insert(best.id)
        }
    }
    let shown = Set((today?.items ?? []).map(\.post.id))
    let judged = today?.judged ?? [:]
    // Not judged yet, or not picked and twice as notable as then (one second look).
    let toJudge = fresh.filter { p in
        if shown.contains(p.id) { return false }
        guard let j = judged[p.id] else { return true }
        return !j.picked && !j.secondLook && (notability[p.id] ?? 0) >= 2 * j.notability
    }.sorted { (notability[$0.id] ?? 0) > (notability[$1.id] ?? 0) }
    return Batch(today: today, fresh: fresh, notability: notability, tops: tops, toJudge: toJudge)
}

/// How many posts the AI is shown: the most notable, not the final picks (it chooses).
let digestAiCandidates = 40

/// What a build would send the AI: the posts to judge (never one read before it was
/// judged), most notable first, at most `max`. Empty: no AI call.
func digestPending(_ prev: DigestDay?, day: String, candidates: [Post], readIds: Set<String>, now: Int, max: Int = digestAiCandidates, shownBefore: Set<String> = []) -> [Post] {
    let b = batch(prev, day: day, candidates: candidates, now: now, shownBefore: shownBefore)
    let judged = b.today?.judged ?? [:]
    return Array(b.toJudge.filter { judged[$0.id] != nil || !readIds.contains($0.id) }.prefix(max))
}

/// Today's digest after a build or refresh (`prev`: the day so far, nil for a first build
/// or a rebuild). `candidates`: the communities' top posts of the day, already without
/// hidden and filtered ones; `readIds`: posts the user has read.
///
/// Posts judged earlier keep their verdict (a refresh only judges what's new), except one
/// not picked whose notability has since doubled: it gets one second look. Nothing
/// already in the digest goes away; new picks go after it. The size is the target for
/// the day's first build; later ones add up to the per-community cap (and Everything
/// notable keeps its 30).
///
/// With `ai` (the AI's verdicts on `digestPending`'s posts), it picks instead of the
/// numbers: the posts it rated 2 or more, most important first, with its "why"; a post it
/// didn't rate isn't picked. `aiFailed`: the AI was wanted and failed, so this is by the
/// numbers and the screen says so.
func mergeDigest(_ prev: DigestDay?, day: String, candidates: [Post], readIds: Set<String>, size: DigestSize, now: Int, ai: DigestAi? = nil, aiFailed: Bool = false, shownBefore: Set<String> = []) -> DigestDay {
    let b = batch(prev, day: day, candidates: candidates, now: now, shownBefore: shownBefore)
    let today = b.today
    let notability = b.notability
    let tops = b.tops

    let byId = Dictionary(b.fresh.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    // What's shown stays, with today's numbers (points, comments).
    var items = (today?.items ?? []).map { item -> DigestItem in
        guard let p = byId[item.post.id] else { return item }
        var i = item
        i.post = p
        return i
    }
    var judged = today?.judged ?? [:]

    // One copy of a link or a story: against what's shown, then each pick.
    var urls = Set(items.compactMap { normalisedUrl($0.post) })
    var stories = items.map { Set(titleKeywords($0.post.title)) }.filter { $0.count >= 3 }
    var perCommunity: [String: Int] = [:]
    for it in items { perCommunity[it.post.subreddit.lowercased(), default: 0] += 1 }
    let cap = today == nil || size == .everything ? size.items : Int.max

    let verdicts = ai?.verdicts
    let toJudge: [Post]
    if let verdicts {
        toJudge = b.toJudge.sorted { a, c in
            let ia = verdicts[a.id]?.importance ?? 0, ic = verdicts[c.id]?.importance ?? 0
            return ia != ic ? ia > ic : (notability[a.id] ?? 0) > (notability[c.id] ?? 0)
        }
    } else {
        toJudge = b.toJudge
    }

    for p in toJudge {
        let n = notability[p.id] ?? 0
        let again = judged[p.id] != nil
        let sub = p.subreddit.lowercased()
        let words = Set(titleKeywords(p.title))
        let url = normalisedUrl(p)
        let verdict = verdicts?[p.id]
        var pick: Bool
        if !again && readIds.contains(p.id) {
            pick = false // read before it was ever judged: it shouldn't take a place
        } else if verdicts != nil {
            pick = (verdict?.importance ?? 0) >= 2 // the AI chooses: under 2, or unrated, stays out
        } else {
            pick = p.score >= digestMinPoints && (n >= digestNotable || tops.contains(p.id))
        }
        if pick {
            if items.count >= cap || perCommunity[sub, default: 0] >= size.perCommunity {
                pick = false
            } else if let url, urls.contains(url) {
                pick = false
            } else if words.count >= 3 && stories.contains(where: { sameStory($0, words) }) {
                pick = false
            }
        }
        judged[p.id] = Judged(picked: pick, notability: n, at: now, secondLook: again)
        if !pick { continue }
        let why = verdict.map(\.why).flatMap { $0.isEmpty ? nil : $0 } ?? digestWhy(p, notability: n, top: tops.contains(p.id))
        items.append(DigestItem(post: p, why: why, notability: n, addedAt: now, importance: verdict?.importance ?? 0))
        perCommunity[sub, default: 0] += 1
        if let url { urls.insert(url) }
        if words.count >= 3 { stories.append(words) }
    }
    return DigestDay(
        day: day,
        builtAt: today?.builtAt ?? now,
        refreshedAt: now,
        seenAt: today?.seenAt ?? now,
        items: items,
        judged: judged,
        // The overview is about the day's first build; a refresh keeps it.
        overview: today?.overview ?? ai?.overview.flatMap { $0.isEmpty ? nil : $0 },
        aiFailed: aiFailed,
        aiAt: ai != nil || aiFailed ? now : today?.aiAt ?? 0
    )
}

/// `day` with the AI's lines for the posts it was shown (picked by the numbers, so its
/// ratings don't count) and its overview, when the day has none yet.
func explainDigest(_ day: DigestDay, ai: DigestAi, now: Int) -> DigestDay {
    var out = day
    out = DigestDay(
        day: day.day, builtAt: day.builtAt, refreshedAt: day.refreshedAt, seenAt: day.seenAt,
        items: day.items.map { item in
            guard let why = ai.verdicts[item.post.id]?.why, !why.isEmpty else { return item }
            return DigestItem(post: item.post, why: why, notability: item.notability, addedAt: item.addedAt, importance: item.importance)
        },
        judged: day.judged,
        overview: day.overview ?? ai.overview.flatMap { $0.isEmpty ? nil : $0 },
        aiFailed: false,
        aiAt: now
    )
    return out
}

/// The items in `order`: one list across communities (each card says its community).
func orderDigest(_ items: [DigestItem], _ order: DigestOrder) -> [DigestItem] {
    switch order {
    case .notable: items.sorted { $0.notability > $1.notability }
    case .upvoted: items.sorted { $0.post.score > $1.post.score }
    case .newest: items.sorted { $0.post.createdUtc > $1.post.createdUtc }
    case .ai: items.sorted { $0.importance != $1.importance ? $0.importance > $1.importance : $0.notability > $1.notability }
    }
}
