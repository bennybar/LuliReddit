import Foundation

/// A post fetched for For You, and the request it came from.
struct Candidate: Sendable {
    let post: Post
    let source: String // best / rising / popular / favourite / interest / community / explore / home / carry
    /// Blend: where Reddit placed it in your Home batch, 0 = top … 1 = bottom.
    var homePos: Double = 1.0
}

/// Interest at or above this counts a subreddit as one you engage with — for
/// both primary membership and the "Because you engage" label (they used to
/// disagree: 2 vs 4).
let kEngagedInterest = 2.0

/// Everything the ranker knows about the user, snapshotted from the local
/// stores. Pure data, so ranking is deterministic and unit-testable.
struct RankInputs {
    var favourites: Set<String> = [] // lowercase
    var subscribed: Set<String> = [] // lowercase
    var interest: [String: Double] = [:]
    var subStats: [String: (Double, Double)] = [:] // sub → (seen, engaged)
    var explicit = ExplicitPrefs()
    var keywordScore: ((String) -> Double)? = nil // idf-weighted, −6…8
    var topKeyword: ((String) -> String?)? = nil
    var muted: Set<String> = []
    var openedAt: [String: Int] = [:] // post id → millis
    var impressions: ((String) -> Double)? = nil // faded count
    var previousTop: Set<String> = [] // the top 10 before this refresh
    var previousTitles: [String] = [] // titles already on earlier pages
    var readTitles: [String] = [] // titles of posts opened in the last 36h
    var discoveryAppetite = 1.0 // discovery vs primary open rate
    var discoveryMix = 0 // Settings → Familiar (-2) ↔ Discover (+2)
    var typeStats: [String: (Double, Double)] = [:] // post type (postTypeKey) → (seen, engaged)
    var blendReddit = 1 // Blend: Reddit ↔ Ilay — 0 mostly Ilay, 1 balanced, 2 mostly Reddit
    var now = nowMillis() // millis

    /// The same inputs once the subscription list has arrived.
    func withSubscriptions(favourites: Set<String>, subscribed: Set<String>) -> RankInputs {
        var c = self
        c.favourites = favourites
        c.subscribed = subscribed
        return c
    }
}

struct RankResult: Sendable {
    let ranked: [Post]
    let leftovers: [Candidate] // carried into the next page's pool
    let meta: OrderedMap<ForYouMeta>
}

// Identity semantics on purpose (pools and the dropped set compare by instance).
private final class Scored {
    let c: Candidate
    let score: Double
    let discovery: Bool
    let reason: String
    let why: [String]
    let story: Set<String> // title keywords, for same-story detection
    let topical: Double // keyword match, freshness-discounted: what a discovery slot picks by first

    init(c: Candidate, score: Double, discovery: Bool, reason: String, why: [String], story: Set<String>, topical: Double) {
        self.c = c
        self.score = score
        self.discovery = discovery
        self.reason = reason
        self.why = why
        self.story = story
        self.topical = topical
    }
}

private final class Story {
    let words: Set<String>
    var count: Int
    var lastPos: Int

    init(_ words: Set<String>, _ count: Int, _ lastPos: Int) {
        self.words = words
        self.count = count
        self.lastPos = lastPos
    }
}

private func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(max(v, lo), hi) }
private func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int { min(max(v, lo), hi) }
private func roundToInt(_ v: Double) -> Int { Int(v.rounded()) }

/// "For You" ranking.
///
/// score = additive · community · affinity · explicit · keywords · quality ·
///         fatigue — every factor positive, so nothing can flip sign (a
///         negative keyword sum used to turn the multipliers upside down:
///         opened posts and favourites ranking *below* others).
func rankForYou(_ pool: [Candidate], _ i: RankInputs, pageSize: Int = 50) -> RankResult {
    // Global open rate, the baseline each subreddit's rate is compared with.
    var seenAll = 0.0
    var engAll = 0.0
    for v in i.subStats.values {
        seenAll += v.0
        engAll += v.1
    }
    let globalCtr = (engAll + 1) / (seenAll + 6)

    func ageHours(_ p: Post) -> Double { max(Double((i.now - p.createdUtc) / 60_000) / 60.0, 1.0) }
    // A Reddit Home card whose date didn't parse has createdUtc 0: its age is
    // unknown, not 56 years. It gets neutral recency and velocity (0.5) and
    // stays out of the percentiles, instead of ranking as ancient and flat.
    let dated = pool.filter { $0.post.createdUtc > 0 }

    // Per-subreddit velocity percentile, so small communities aren't drowned
    // out by raw point counts ("a top post *for this sub*" is what matters).
    var vels: [String: [Double]] = [:]
    for c in dated { vels[c.post.subreddit, default: []].append(Double(c.post.score) / ageHours(c.post)) }
    for k in vels.keys { vels[k]!.sort() }
    func velPct(_ p: Post) -> Double {
        if p.createdUtc <= 0 { return 0.5 }
        let v = vels[p.subreddit]!
        if v.count == 1 { return 0.5 }
        let x = Double(p.score) / ageHours(p)
        // Average rank among equals: ties (a sub's brand-new posts, all at
        // 1 point) used to share the lowest percentile, 0.
        var lo = 0
        while lo < v.count, v[lo] < x { lo += 1 }
        var hi = lo
        while hi < v.count, v[hi] == x { hi += 1 }
        let rank = Double(lo + max(hi - 1, lo)) / 2.0
        let raw = rank / Double(v.count - 1)
        // A sub with few candidates says little about how good a post is for
        // it: pulled toward the middle (a single candidate is 0.5, was 0.7).
        let trust = Double(v.count - 1) / (Double(v.count) + 2.0)
        return 0.5 + (raw - 0.5) * trust
    }

    // How often you engage with each kind of post (image, video, text…) that
    // For You shows, against your overall rate: learns what you like to see.
    var typeSeen = 0.0
    var typeEng = 0.0
    for v in i.typeStats.values {
        typeSeen += v.0
        typeEng += v.1
    }
    let typeCtr = (typeEng + 1) / (typeSeen + 6)
    func typeMult(_ p: Post) -> Double {
        guard let st = i.typeStats[postTypeKey(p)], st.0 >= 8 else { return 1.0 }
        let lift = clamp(log(((st.1 + 1) / (st.0 + 6)) / typeCtr), -0.5, 0.5)
        return exp(0.6 * lift) // ×0.74 … ×1.35
    }

    // Discussion: comments per hour, as a percentile in this pool (a busy
    // thread and a silent one used to rank alike).
    let talk = dated.map { Double($0.post.numComments) / ageHours($0.post) }.sorted()
    func talkPct(_ p: Post) -> Double {
        if talk.count < 2 || p.createdUtc <= 0 { return 0.5 }
        let x = Double(p.numComments) / ageHours(p)
        var lo = 0
        while lo < talk.count, talk[lo] < x { lo += 1 }
        return Double(lo) / Double(talk.count - 1)
    }

    // Points per hour as a percentile across the whole pool: how big a post is
    // on Reddit right now, whatever its community (velPct is within one).
    let speed = dated.map { Double($0.post.score) / ageHours($0.post) }.sorted()
    func speedPct(_ p: Post) -> Double {
        if speed.count < 2 || p.createdUtc <= 0 { return 0.5 }
        let x = Double(p.score) / ageHours(p)
        var lo = 0
        while lo < speed.count, speed[lo] < x { lo += 1 }
        return Double(lo) / Double(speed.count - 1)
    }

    // Blend presets: how strong Reddit's pick counts, and how often a Home
    // post gets a guaranteed slot (0 = never; it then competes on score alone).
    let homeBoost = [1.1, 1.25, 1.5][clamp(i.blendReddit, 0, 2)]
    let homeEvery = [0, 5, 3][clamp(i.blendReddit, 0, 2)]

    // Stories you opened in the last 36h: another post about one is demoted
    // (×0.3), not dropped — a follow-up can still matter.
    let readStories = i.readTitles.map { Set(titleKeywords($0)) }.filter { $0.count >= 3 }

    func pct(_ f: Double) -> String {
        let digits = f >= 10 ? 0 : f >= 1 ? 1 : 2
        return "×" + String(format: "%.\(digits)f", f)
    }

    func score(_ c: Candidate) -> Scored? {
        let p = c.post
        let sub = p.subreddit.lowercased()
        if p.stickied || i.muted.contains(sub) { return nil }
        let opened = i.openedAt[p.id]
        // Opened more than 12h ago: done with it.
        if let opened, i.now - opened > 12 * 3600 * 1000 { return nil }

        let fav = i.favourites.contains(sub)
        let subd = i.subscribed.contains(sub)
        let explicitSub = i.explicit.subs[sub] ?? 0

        // Affinity: learned interest plus how often you actually open this
        // subreddit compared with everything else (rate, not count).
        var lift = 0.0
        if let st = i.subStats[sub], st.0 >= 3 {
            let ctr = (st.1 + 1) / (st.0 + 6)
            lift = clamp(log(ctr / globalCtr), -1.5, 1.5)
        }
        let a = (i.interest[sub] ?? 0.0) + 4 * lift
        // Two-sided and non-saturating: "less" and downvotes now demote (they
        // were clamped away), heavy use keeps ordering instead of capping out.
        let wInterest = a >= 0 ? 1 + 0.6 * log(1 + a / 3) : exp(a / 4)

        // Blend: a post from your Reddit Home is Reddit's own pick for you. That
        // boosts it (one bounded multiplier, set by Reddit ↔ Ilay, plus up to 30%
        // for being near the top of your Home: Reddit's order counts; it was 10%,
        // which barely moved anything) but doesn't make its community
        // familiar: Reddit's picks from communities you don't follow stay
        // discovery, under Familiar ↔ Discover. (It used to be primary with a
        // higher base too — ~4.6× plain discovery.)
        // Discovery's base grows with how fast the post is rising across the
        // pool (0.4 … 1.2): a flat 0.4 was 6–10× under what you follow, so only
        // the forced discovery slots ever showed anything new.
        // A community you engage with but don't follow starts above discovery,
        // growing with your engagement up to a subscription's 2.5: it counted as
        // primary yet kept a stranger's base, so it lost to everything you follow.
        let fromHome = c.source == "home"
        let primary = fav || subd || a >= kEngagedInterest || explicitSub > 0
        let discoveryBase = 0.4 + 0.8 * speedPct(p)
        let base = fav ? 4.0 : subd || explicitSub > 0 ? 2.5
            : a >= kEngagedInterest ? max(discoveryBase, min(2.5, 0.8 + 0.25 * a)) : discoveryBase
        let homeMult = fromHome ? homeBoost * (1 + 0.3 * (1 - clamp(c.homePos, 0.0, 1.0))) : 1.0
        let eSub = explicitSub > 0 ? 1.6 : explicitSub < 0 ? 0.3 : 1.0

        let kw = i.keywordScore?(p.title) ?? 0.0
        // Keywords lead discovery (×0.41 … ×3.3 there): in a community you don't
        // follow, the topic is what makes a post yours, not its points.
        let kwMult = exp((primary ? 0.08 : 0.15) * kw) // ×0.62 … ×1.9
        let words = titleKeywords(p.title)
        let story = Set(words)
        var likedTopic: String?
        var dislikedTopic: String?
        for w in words {
            guard let v = i.explicit.topics[w] else { continue }
            if v < 0 { dislikedTopic = dislikedTopic ?? w }
            if v > 0 { likedTopic = likedTopic ?? w }
        }
        let eTopic = dislikedTopic != nil ? 0.3 : likedTopic != nil ? 1.6 : 1.0

        let vp = velPct(p)
        let age = ageHours(p)
        let recency = p.createdUtc > 0 ? 1 / (1 + age / 24) : 0.5
        let additive = max(1.0, vp * 30 + recency * 30 + 15)
        // A missing ratio (Home page cards, GraphQL without it) counts as a
        // typical post's: read as 0 it cost Blend's Home posts ×0.35.
        let quality = 0.5 + (p.upvoteRatio ?? 0.9)

        // Freshness: each faded impression (one per feed build it was seen in)
        // costs 45% — at 20% a post seen three times still led the feed; opened
        // posts mostly go; posts in the last top 10 (kept across launches) make
        // room on refresh.
        let shown = i.impressions?(p.id) ?? 0.0
        let fatigue = pow(0.55, shown)
        let openedPen = opened != nil ? 0.15 : 1.0
        let churn = i.previousTop.contains(p.id) ? 0.7 : 1.0
        // Same story as one you opened lately (the post itself is "opened" above).
        let alreadyRead = opened == nil && story.count >= 3 && readStories.contains { sameStory($0, story) }
        let readPen = alreadyRead ? 0.3 : 1.0

        let tMult = typeMult(p)
        let tp = talkPct(p)
        let discussion = 0.92 + 0.16 * tp // ×0.92 … ×1.08

        // In steps: one long product is slow for the type checker.
        var s = additive * base * wInterest * eSub
        s *= kwMult * eTopic * quality * fatigue
        s *= openedPen * churn * tMult * discussion * homeMult * readPen

        // Explanation from what actually moved the score.
        let topKw = i.topKeyword?(p.title)
        var drivers: [(Double, String)] = []
        if let likedTopic { drivers.append((log(1.6), "You asked for more about “\(likedTopic)”")) }
        if explicitSub > 0 { drivers.append((log(1.6), "You asked for more from r/\(p.subreddit)")) }
        if fav { drivers.append((log(4 / 2.5), "★ Favourite · r/\(p.subreddit)")) }
        if a >= kEngagedInterest { drivers.append((log(wInterest), "Because you engage with r/\(p.subreddit)")) }
        if let topKw, kw > 0 { drivers.append((log(kwMult), "Because you read about “\(topKw)”")) }
        drivers.sort { $0.0 > $1.0 }
        let reason: String
        if alreadyRead {
            reason = "You read about this already"
        } else if let d = drivers.first, d.0 > log(1.15) {
            reason = d.1
        } else if age < 6, p.score > 1000, vp > 0.8 {
            reason = "🔥 Trending on Reddit"
        } else if fromHome, subd { // Blend: say it came from your Reddit Home (yours, or Reddit's pick).
            reason = "In your Reddit Home · r/\(p.subreddit)"
        } else if fromHome {
            reason = "Recommended by Reddit · r/\(p.subreddit)"
        } else if subd {
            reason = "From r/\(p.subreddit)"
        } else if c.source == "community" {
            reason = "Discover · r/\(p.subreddit), near communities you visit"
        } else {
            reason = "Discover · r/\(p.subreddit)"
        }

        var why: [String] = []
        if fav {
            why.append("r/\(p.subreddit) is one of your favourites")
        } else if subd {
            why.append("You're subscribed to r/\(p.subreddit)")
        } else if a >= kEngagedInterest {
            why.append("Because you engage with r/\(p.subreddit) (you don't follow it)")
        } else if fromHome {
            why.append("Reddit recommends r/\(p.subreddit) to you (you don't follow it)")
        } else {
            why.append("Discovery: you don't follow r/\(p.subreddit)")
        }
        if fromHome { why.append("In your Reddit Home\(p.feedReason.map { ": “\($0)”" } ?? "") (\(pct(homeMult)))") }
        if explicitSub != 0 {
            why.append("You asked for \(explicitSub > 0 ? "more" : "less") from r/\(p.subreddit) (\(pct(eSub)))")
        }
        if abs(wInterest - 1) > 0.05 { why.append("Your activity in r/\(p.subreddit) (\(pct(wInterest)))") }
        if let likedTopic { why.append("You asked for more about “\(likedTopic)” (×1.6)") }
        if let dislikedTopic { why.append("You asked for less about “\(dislikedTopic)” (×0.3)") }
        if abs(kwMult - 1) > 0.05 {
            why.append("Topics you read\(topKw.map { ", like “\($0)”" } ?? "") (\(pct(kwMult)))")
        }
        if vp > 0.8 { why.append("Doing well in r/\(p.subreddit) right now") }
        if abs(tMult - 1) > 0.05 {
            why.append("\(tMult > 1 ? "You often open" : "You rarely open") \(postTypeKey(p)) posts (\(pct(tMult)))")
        }
        if tp > 0.85, p.numComments >= 20 { why.append("Lively discussion: \(p.numComments) comments (\(pct(discussion)))") }
        if shown >= 0.5 { why.append("Seen \(roundToInt(shown))× before (\(pct(fatigue)))") }
        if opened != nil { why.append("You already opened it (×0.15)") }
        if alreadyRead { why.append("You read about this already (×0.3)") }
        why.append("Source: \(sourceLabel(c.source))")

        let topical = max(0.0, kw) * fatigue * openedPen * eSub * eTopic * readPen
        return Scored(c: c, score: s, discovery: !primary, reason: reason, why: why, story: story, topical: topical)
    }

    let scored = pool.compactMap(score).sorted { $0.score > $1.score }

    // Same link in several places (crossposts, the same article): keep the
    // best-scoring one.
    var byUrl = Set<String>()
    var unique: [Scored] = []
    for s in scored {
        let key = normalisedUrl(s.c.post)
        if key == nil || byUrl.insert(key!).inserted { unique.append(s) }
    }

    // Same story told in different subreddits: the second copy is allowed at
    // least 15 slots after the first, a third never. Stories from earlier
    // pages count.
    var stories: [Story] = []
    func storyOf(_ words: Set<String>) -> Int? {
        if words.count < 3 { return nil }
        for k in stories.indices where sameStory(stories[k].words, words) { return k }
        return nil
    }
    // Earlier pages, newest first: copies of one story count together (each
    // used to be its own story, so a third copy got through), and the newest
    // keeps its real distance (j + 1 slots before this page) for the spacing.
    for (j, t) in i.previousTitles.enumerated() {
        let w = Set(titleKeywords(t))
        if w.count < 3 { continue }
        if let k = storyOf(w) { stories[k].count += 1 } else { stories.append(Story(w, 1, -(j + 1))) }
    }

    // Greedy placement: each slot takes the best remaining post after a
    // diversity discount (same subreddit in the last 8, same media type in
    // the last 4), alternating in discovery at an adaptive rate.
    var primaryPool = unique.filter { !$0.discovery }
    var discoveryPool = unique.filter { $0.discovery }
    // A discovery post every ~6 slots, adapted to how often you open them;
    // the Familiar ↔ Discover setting scales that (Familiar: ~1 in 15, a
    // floor so the feed never closes in on itself; Discover: ~1 in 3). The
    // middle keeps the adaptive 4–10 range.
    let mix = [0.3, 0.6, 1.0, 1.4, 2.0][clamp(i.discoveryMix, -2, 2) + 2]
    let appetite = clamp(i.discoveryAppetite, 0.6, 1.5)
    let every = i.discoveryMix == 0 ? clamp(roundToInt(6 / appetite), 4, 10) : clamp(roundToInt(6 / (appetite * mix)), 3, 15)
    var placed: [Scored] = []
    var dropped = Set<ObjectIdentifier>()

    // A discovery slot goes to the best keyword match first, then the best
    // score (velocity, freshness): a topical post in a niche community beats a
    // generic r/popular hit there.
    func pick(_ from: [Scored], topicalFirst: Bool = false) -> Scored? {
        var best: Scored?
        var bestT = -1.0
        var bestV = -1.0
        let recentSubs = placed.suffix(8).map(\.c.post.subreddit)
        let recentTypes = placed.suffix(4).map(\.c.post.type)
        for s in from {
            if dropped.contains(ObjectIdentifier(s)) { continue }
            if let k = storyOf(s.story), stories[k].count >= 2 || placed.count - stories[k].lastPos < 15 {
                if stories[k].count >= 2 { dropped.insert(ObjectIdentifier(s)) }
                continue
            }
            let sameSub = recentSubs.filter { $0 == s.c.post.subreddit }.count
            let sameType = recentTypes.filter { $0 == s.c.post.type }.count
            let diversity = pow(0.6, Double(sameSub)) * pow(0.85, Double(sameType))
            let v = s.score * diversity
            let t = topicalFirst ? s.topical * diversity : 0.0
            if t > bestT || (t == bestT && v > bestV) {
                bestT = t
                bestV = v
                best = s
            }
        }
        return best
    }

    while placed.count < pageSize {
        let wantDiscovery = (placed.count + 1) % every == 0
        // Blend: every homeEvery-th slot goes to the best Reddit Home post —
        // one from a community you don't follow only if Familiar ↔ Discover
        // isn't at its most familiar.
        let wantHome = !wantDiscovery && homeEvery > 0 && (placed.count + 1) % homeEvery == 0
        var chosen: Scored?
        if wantHome {
            let homes = primaryPool.filter { $0.c.source == "home" }
                + (i.discoveryMix > -2 ? discoveryPool.filter { $0.c.source == "home" } : [])
            chosen = pick(homes)
        }
        if chosen == nil, wantDiscovery { chosen = pick(discoveryPool, topicalFirst: true) }
        if chosen == nil { chosen = pick(primaryPool) }
        if chosen == nil { chosen = pick(discoveryPool) }
        guard let s = chosen else { break }
        if s.discovery { discoveryPool.removeAll { $0 === s } } else { primaryPool.removeAll { $0 === s } }
        if let k = storyOf(s.story) {
            stories[k].count += 1
            stories[k].lastPos = placed.count
        } else if s.story.count >= 3 {
            stories.append(Story(s.story, 1, placed.count))
        }
        placed.append(s)
    }

    // Unplaced posts aren't thrown away: the best carry over to the next page
    // (the per-subreddit cap used to discard them for good).
    let leftovers = (primaryPool + discoveryPool)
        .filter { !dropped.contains(ObjectIdentifier($0)) }
        .sorted { $0.score > $1.score }
        .prefix(120)
        .map(\.c)

    var meta = OrderedMap<ForYouMeta>()
    var ranked: [Post] = []
    ranked.reserveCapacity(placed.count)
    for (k, s) in placed.enumerated() {
        ranked.append(s.c.post.with { $0.feedReason = s.reason })
        meta[s.c.post.id] = ForYouMeta(source: s.c.source, discovery: s.discovery, position: k, why: s.why)
    }
    return RankResult(ranked: ranked, leftovers: leftovers, meta: meta)
}

/// Same story: at least 3 shared title keywords, half of both titles' keywords.
private func sameStory(_ a: Set<String>, _ b: Set<String>) -> Bool {
    let shared = a.intersection(b).count
    return shared >= 3 && Double(shared) / Double(a.union(b).count) >= 0.5
}

private func sourceLabel(_ source: String) -> String {
    switch source {
    case "best": return "your subscriptions (Best)"
    case "rising": return "rising in your subscriptions"
    case "popular": return "r/popular"
    case "favourite": return "a favourite community"
    case "interest": return "a community you engage with"
    case "community": return "a community you've visited"
    case "explore": return "today's top posts across Reddit"
    case "carry": return "held over from the previous page"
    case "home": return "your Reddit Home (Blend)"
    default: return source
    }
}

private let leadingWww = Re(#"^www\."#)

/// A link post's URL without scheme, `www.`, tracking parameters or
/// fragment — to spot the same link posted in several places. Nil for text
/// posts (their URL is their own permalink).
func normalisedUrl(_ p: Post) -> String? {
    if p.isSelf || p.url.isEmpty { return nil }
    guard let u = URLComponents(string: p.url), let scheme = u.scheme?.lowercased(), scheme == "http" || scheme == "https",
          let rawHost = u.host, !rawHost.isEmpty else { return nil }
    let host = leadingWww.replace(rawHost.lowercased(), with: "")
    var last = OrderedMap<String>()
    for item in u.queryItems ?? [] where !item.name.hasPrefix("utm_") { last[item.name] = item.value ?? "null" }
    let q = last.keys.sorted().map { "\($0)=\(last[$0]!)" }.joined(separator: "&")
    let path = u.percentEncodedPath.isEmpty ? "/" : u.percentEncodedPath
    return "\(host)\(path)\(q.isEmpty ? "" : "?\(q)")"
}

/// The kind of post, for learning which kinds you open (galleries count as images, GIFs as videos).
func postTypeKey(_ p: Post) -> String {
    switch p.type {
    case .image, .gallery: return "image"
    case .video, .gif: return "video"
    case .link: return "link"
    case .selfPost: return "text"
    }
}
