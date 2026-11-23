import Foundation

// The Digest (docs/digest-spec.md): the notable posts of the last 24 hours in the
// communities you choose, kept per day. This file is the pure part (what gets picked,
// and how a refresh merges into the day), unit-tested like the Kotlin app's.

/// How long a digest is (Settings › Feed › Digest › Size). Persisted by index (`digestSize`).
enum DigestSize: Int, CaseIterable, Sendable {
    case brief, standard, everything

    static func of(_ i: Int) -> DigestSize { DigestSize(rawValue: i) ?? .standard }

    var items: Int { [5, 12, 30][rawValue] }
    var perCommunity: Int { [2, 3, 5][rawValue] }
    var label: String { ["Brief", "Standard", "Everything notable"][rawValue] }
    var description: String {
        ["About 5 posts, at most 2 from a community", "About 12 posts, at most 3 from a community", "Every notable post, up to 30"][rawValue]
    }
}

/// A post in a digest, with why it's there. `addedAt`: when this day's digest gained it.
struct DigestItem: Equatable, Sendable {
    var post: Post
    let why: String
    let notability: Double
    let addedAt: Int
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

    func isNew(_ item: DigestItem) -> Bool { item.addedAt > builtAt && item.addedAt > seenAt }
}

/// At or above this, a post is notable: twice what's usual in its community.
let digestNotable = 2.0
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
    let sub = "r/\(p.subreddit)"
    let comments = p.numComments > 0 ? " · \(compactNumber(p.numComments)) comments" : ""
    if top && notability < digestNotable { return "Top post today in \(sub)\(comments)" }
    let times: String
    if notability >= 10 {
        times = "\(Int(notability.rounded()))×"
    } else {
        let v = (notability * 10).rounded() / 10
        times = v == v.rounded() ? "\(Int(v))×" : "\(v)×"
    }
    return (top ? "Top post today in \(sub), \(times) a typical post" : "\(times) a typical post in \(sub)") + comments
}

/// Today's digest after a build or refresh (`prev`: the day so far, nil for a first build
/// or a rebuild). `candidates`: the communities' top posts of the day, already without
/// hidden and filtered ones; `readIds`: posts the user has read.
///
/// Posts judged earlier keep their verdict (a refresh only judges what's new), except one
/// not picked whose notability has since doubled: it gets one second look. Nothing
/// already in the digest goes away or moves; new picks go after it. The size is the
/// target for the day's first build; later ones add up to the per-community cap (and
/// Everything notable keeps its 30).
func mergeDigest(_ prev: DigestDay?, day: String, candidates: [Post], readIds: Set<String>, size: DigestSize, now: Int) -> DigestDay {
    let today = prev?.day == day ? prev : nil
    var seenIds = Set<String>()
    let fresh = candidates.filter {
        !$0.stickied && $0.createdUtc > 0 && now - $0.createdUtc <= dayMs && seenIds.insert($0.id).inserted
    }
    let notability = notabilityOf(fresh)
    // Each community's best post today is notable whatever its number.
    var tops = Set<String>()
    for group in Dictionary(grouping: fresh, by: { $0.subreddit.lowercased() }).values {
        if let best = group.max(by: { (notability[$0.id] ?? 0) < (notability[$1.id] ?? 0) }) { tops.insert(best.id) }
    }

    let byId = Dictionary(fresh.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    // What's shown stays, with today's numbers (points, comments).
    var items = (today?.items ?? []).map { item -> DigestItem in
        guard let p = byId[item.post.id] else { return item }
        var i = item
        i.post = p
        return i
    }
    let shown = Set(items.map(\.post.id))
    var judged = today?.judged ?? [:]

    // One copy of a link or a story: against what's shown, then each pick.
    var urls = Set(items.compactMap { normalisedUrl($0.post) })
    var stories = items.map { Set(titleKeywords($0.post.title)) }.filter { $0.count >= 3 }
    var perCommunity: [String: Int] = [:]
    for it in items { perCommunity[it.post.subreddit.lowercased(), default: 0] += 1 }
    let cap = today == nil || size == .everything ? size.items : Int.max

    let toJudge = fresh.filter { p in
        if shown.contains(p.id) { return false }
        guard let j = judged[p.id] else { return true }
        return !j.picked && !j.secondLook && (notability[p.id] ?? 0) >= 2 * j.notability
    }.sorted { (notability[$0.id] ?? 0) > (notability[$1.id] ?? 0) }

    for p in toJudge {
        let n = notability[p.id] ?? 0
        let again = judged[p.id] != nil
        let sub = p.subreddit.lowercased()
        let words = Set(titleKeywords(p.title))
        let url = normalisedUrl(p)
        let pick: Bool
        if !again && readIds.contains(p.id) {
            pick = false // read before it was ever judged: it shouldn't take a place
        } else if n < digestNotable && !tops.contains(p.id) {
            pick = false
        } else if items.count >= cap || perCommunity[sub, default: 0] >= size.perCommunity {
            pick = false
        } else if let url, urls.contains(url) {
            pick = false
        } else if words.count >= 3 && stories.contains(where: { sameStory($0, words) }) {
            pick = false
        } else {
            pick = true
        }
        judged[p.id] = Judged(picked: pick, notability: n, at: now, secondLook: again)
        if !pick { continue }
        items.append(DigestItem(post: p, why: digestWhy(p, notability: n, top: tops.contains(p.id)), notability: n, addedAt: now))
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
        judged: judged
    )
}

/// The items grouped by community for the screen, in the order the communities first
/// appear (a first build is by notability, so the community with the day's biggest post
/// leads; later picks join their community, or come last).
func groupByCommunity(_ items: [DigestItem]) -> [(community: String, items: [DigestItem])] {
    var order: [String] = []
    var groups: [String: [DigestItem]] = [:]
    for it in items {
        let k = it.post.subreddit.lowercased()
        if groups[k] == nil { order.append(k) }
        groups[k, default: []].append(it)
    }
    return order.map { (groups[$0]![0].post.subreddit, groups[$0]!) }
}
