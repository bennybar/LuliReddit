import Foundation
import Observation
import SwiftUI

/// The on-device For You engine + its stores (interest, keywords, doc-freq,
/// impressions, sub stats, explicit prefs, muted subs, metrics, meta), the
/// learner and the experimental Reddit Home loader.
@MainActor @Observable
final class ForYouModule: UserScoped, FeedEngines {
    @ObservationIgnored private let c: AppContainer

    @ObservationIgnored let interest: InterestStore
    @ObservationIgnored let muted: MutedSubsStore
    @ObservationIgnored let keywords: KeywordStore
    @ObservationIgnored let impressions: ImpressionStore
    @ObservationIgnored let explicit: ExplicitPrefsStore
    @ObservationIgnored let subStats: SubStatsStore
    /// The same per post type ("image", "video", "text", "link"): which kinds you open.
    @ObservationIgnored let typeStats: SubStatsStore
    @ObservationIgnored let docFreq: DocFreqStore
    @ObservationIgnored let metrics: ForYouMetrics

    /// Why each placed post is in the feed (not persisted; per session).
    var meta: [String: ForYouMeta] = [:]

    @ObservationIgnored private(set) lazy var forYouLearner = ForYouLearner(self)
    @ObservationIgnored private(set) lazy var engine = ForYouEngine(c, self)
    @ObservationIgnored private(set) lazy var redditHome = RedditHomeEngine(c, self)

    init(_ c: AppContainer) {
        self.c = c
        let track = { [unowned c] in c.settings.value.trackHistory }
        interest = InterestStore(prefs: c.prefs, trackHistory: track)
        muted = MutedSubsStore(prefs: c.prefs)
        keywords = KeywordStore(prefs: c.prefs, trackHistory: track)
        impressions = ImpressionStore(prefs: c.prefs, trackHistory: track)
        explicit = ExplicitPrefsStore(prefs: c.prefs)
        subStats = SubStatsStore(prefs: c.prefs, trackHistory: track)
        typeStats = SubStatsStore(prefs: c.prefs, trackHistory: track, base: "fy_typestats")
        docFreq = DocFreqStore(prefs: c.prefs)
        metrics = ForYouMetrics(prefs: c.prefs, trackHistory: track)
    }

    func onUserChanged(_ username: String) {
        interest.load(username)
        muted.load(username)
        keywords.load(username)
        impressions.load(username)
        explicit.load(username)
        subStats.load(username)
        typeStats.load(username)
        docFreq.load(username)
        metrics.load(username)
        meta = [:]
        forYouLearner.reset()
        engine.reset()
        redditHome.cancelBlend() // the other account's Home reads
    }

    // MARK: FeedEngines, the feed's way in

    var learner: FeedLearner { forYouLearner }

    func forYouPage(after: String?, loaded: [Post]) async throws -> Listing<Post> { try await engine.page(after: after, loaded: loaded) }
    func forYouCachedFirstPage() async throws -> Listing<Post>? { await engine.cachedFirstPage() }
    func forYouCachedFirstPageTime() async throws -> Int? { await engine.cachedFirstPageTime() }

    func homePage(after: String?, loaded: [Post]) async throws -> Listing<Post> { try await redditHome.page(after: after, loaded: loaded) }
    func homeCachedFirstPage() async throws -> Listing<Post>? { await redditHome.cachedFirstPage() }
    func homeCachedFirstPageTime() async throws -> Int? { await redditHome.cachedFirstPageTime() }

    var homeStatus: HomeStatus? {
        get { redditHome.status }
        set { redditHome.status = newValue }
    }
    var blendState: BlendState? { redditHome.blendState }
    var onHomeUpgrades: (([Post]) -> Void)? {
        get { redditHome.onUpgrades }
        set { redditHome.onUpgrades = newValue }
    }
    func homeViewing(_ postId: String) { redditHome.viewing(postId) }
    func disposeHome() { redditHome.dispose() }

    func loadingDeck(forYou: Bool) -> AnyView { AnyView(HomeLoadingDeck(forYou: forYou)) }
    func showTuneSheet(_ post: Post) { Ilay.showTuneSheet(post) }
}

/// The one place For You learns from what the user does. Every call site
/// used to bump the stores itself, with drift between them (the post-detail
/// vote never taught keywords; unsave reverted interest but not keywords;
/// re-voting kept adding up).
///
/// Learned signals respect the history-tracking switch (inside each store);
/// explicit More/Less choices live in `ExplicitPrefs` and always apply.
@MainActor
final class ForYouLearner: FeedLearner {
    private unowned let m: ForYouModule
    private var seen = Set<String>() // impressions counted this session
    private var engaged = Set<String>() // posts already counted as engaged
    private var passive = Set<String>() // "signal:postId" already learned this session

    init(_ m: ForYouModule) { self.m = m }

    /// Passive signals (open, media, reading time, bounce) count once per post
    /// per session: reopening the same thread kept adding interest. Votes,
    /// saves, comments and shares are deliberate and always count.
    private func once(_ p: Post, _ signal: String) -> Bool { passive.insert("\(signal):\(p.id)").inserted }

    func reset() {
        seen.removeAll()
        engaged.removeAll()
        passive.removeAll()
    }

    private func group(_ p: Post) -> String {
        guard let meta = m.meta[p.id] else { return "other" }
        return meta.discovery ? "discovery" : "primary"
    }

    private func learn(_ p: Post, _ subDelta: Double, _ titleDelta: Double) {
        m.interest.bump(p.subreddit, subDelta)
        if titleDelta != 0 { m.keywords.bumpTitle(p.title, titleDelta) }
    }

    /// Opened, read 30s+, or upvoted: counts once per post toward the
    /// subreddit's engagement rate — only for a post For You showed this
    /// session, so the rate is "liked what For You showed" (engagement from
    /// other feeds, with no matching impression, used to inflate it).
    private func engage(_ p: Post, _ event: String) {
        m.metrics.count("\(event).\(group(p))")
        if seen.contains(p.id), engaged.insert(p.id).inserted {
            m.subStats.engaged(p.subreddit)
            m.typeStats.engaged(postTypeKey(p))
        }
    }

    /// A For You card that stayed >=60% on screen for 1s.
    func impression(_ p: Post) {
        m.impressions.record(p.id)
        if !seen.insert(p.id).inserted { return }
        m.subStats.impression(p.subreddit)
        m.typeStats.impression(postTypeKey(p))
        let meta = m.meta[p.id]
        m.metrics.count("impr.\(group(p))")
        if let meta {
            m.metrics.count("src.\(meta.source)")
            if meta.position < 10 { m.metrics.count("impr.top10") }
        }
    }

    /// A vote changed from `from` to `to` (-1, 0, +1). Learns only the change,
    /// so up → none → up nets +1 vote, not +2, and switching up → down lands on
    /// a plain downvote.
    func vote(_ p: Post, from: Int, to: Int) {
        if from == to { return }
        func sub(_ d: Int) -> Double { d == 1 ? 2.0 : d == -1 ? -1.5 : 0.0 }
        func kw(_ d: Int) -> Double { d == 1 ? 1.0 : d == -1 ? -0.8 : 0.0 }
        learn(p, sub(to) - sub(from), kw(to) - kw(from))
        // A downvote isn't engagement (it counted as liking the subreddit).
        if to == 1 { engage(p, "vote") }
    }

    func save(_ p: Post, saved: Bool) { learn(p, saved ? 3.0 : -3.0, saved ? 1.5 : -1.5) }

    func open(_ p: Post) {
        if once(p, "open") { learn(p, 0.5, 0.0) }
        engage(p, "open")
    }

    func viewMedia(_ p: Post) {
        if once(p, "media") { learn(p, 1.0, 0.0) }
    }

    /// Commenting is the strongest engagement signal there is.
    func comment(_ p: Post) { learn(p, 2.5, 1.0) }

    func share(_ p: Post) { learn(p, 1.5, 0.75) }

    /// Time in the thread: 30s+ (`long` = 2min+, on top of it).
    func read(_ p: Post, long: Bool = false) {
        if once(p, long ? "read2m" : "read30") { learn(p, long ? 1.5 : 1.0, long ? 1.0 : 0.5) }
        if !long { engage(p, "read30") }
    }

    /// The "no" signals: hiding a post, the Dismiss swipe, hiding its subreddit
    /// for 7 days, filtering it out. They used to only remove things from view.
    /// `undo` reverses one (its snackbar's Undo).
    func hidePost(_ p: Post, undo: Bool = false) { learn(p, undo ? 2.0 : -2.0, undo ? 0.8 : -0.8) }

    func dismiss(_ p: Post, undo: Bool) { learn(p, undo ? 1.0 : -1.0, undo ? 0.4 : -0.4) }

    func hideSubreddit(_ p: Post, undo: Bool) { learn(p, undo ? 3.0 : -3.0, 0.0) }

    func filterOutSubreddit(_ p: Post, undo: Bool) { learn(p, undo ? 4.0 : -4.0, 0.0) }

    /// Upvoted a comment in `p`'s thread: interest in the thread's subreddit (once per post per session).
    func commentUpvote(_ p: Post) {
        if once(p, "commentvote") { learn(p, 0.75, 0.0) }
        engage(p, "commentvote")
    }

    /// Backed out within 3 seconds.
    func bounce(_ p: Post) {
        if once(p, "bounce") { learn(p, -0.5, 0.0) }
    }

    /// Explicit "More/Less from r/x" (+1 / -1 / 0 to clear).
    func subPreference(_ p: Post, _ value: Int) {
        m.explicit.setSub(p.subreddit, value)
        if value != 0 { m.metrics.count(value > 0 ? "more" : "less") }
    }

    /// Explicit "More/Less about 'topic'".
    func topicPreference(_ topic: String, _ value: Int) {
        m.explicit.setTopic(topic, value)
        if value != 0 { m.metrics.count(value > 0 ? "more" : "less") }
    }
}

/// One page of For You, plus what the next page and the UI need.
struct ForYouPage: Sendable {
    let listing: Listing<Post>
    let cursors: [String: String]
    let leftovers: [Candidate]
    let meta: OrderedMap<ForYouMeta>
    let candidateTitles: [String] // for word rarity (IDF)
}

/// Blend: what becomes of Home's cursor after a page. Its value counts misses in a
/// row. Still loading or a passing failure: try again on the next page (up to 3
/// failures, 2 empty batches, as Home allows); signed out: the rest of this feed is
/// For You's own, and says so. A nil `state` means "report how many were placed".
func blendNext(previous: String?, result: BlendResult?, firstPage: Bool) -> (cursor: String?, state: BlendState?) {
    let misses = previous.flatMap { Int($0.removePrefix("m")) } ?? 0
    switch result {
    case nil: return ("m\(misses)", firstPage ? .loading : nil) // still loading
    case .posts: return ("m0", nil)
    case .signedOut: return (nil, .unavailable(signedOut: true))
    case .empty, .failed:
        if case .empty = result, misses + 1 < 2 { return ("m\(misses + 1)", nil) }
        if case .failed = result, misses + 1 < 3 { return ("m\(misses + 1)", nil) }
        return (nil, .unavailable(signedOut: false))
    }
}

/// Stops `operation` after `millis`, returning nil; its own failures still throw.
func withTimeoutOrNil<T: Sendable>(_ millis: Int, _ operation: @escaping @Sendable () async throws -> T) async throws -> T? {
    try await withThrowingTaskGroup(of: T?.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .milliseconds(millis))
            return nil
        }
        defer { group.cancelAll() }
        return try await group.next() ?? nil
    }
}

/// "For You" — a transparent, client-side personalized feed.
///
/// Reddit's real Home ranking is server-side ML and is NOT exposed to the
/// API, so this approximates it: fetch candidates from the sources that
/// matter to the user, then rank them on-device (`rankForYou`).
@MainActor @Observable
final class ForYouEngine {
    @ObservationIgnored private let c: AppContainer
    @ObservationIgnored private unowned let m: ForYouModule
    /// Where candidates come from (tests put a stubbed one here).
    @ObservationIgnored var repo: RedditRepository

    // The previous page's unplaced candidates, and which candidate
    // communities to sample next (rotated each refresh).
    @ObservationIgnored private var leftovers: [Candidate] = []
    @ObservationIgnored private var communityTurn = 0
    @ObservationIgnored private var blendPlaced = 0 // Blend: Reddit Home posts placed in this feed

    /// Candidate posts gathered so far while the first page loads (for the loading deck).
    private(set) var progress = 0

    init(_ c: AppContainer, _ m: ForYouModule) {
        self.c = c
        self.m = m
        repo = c.repository
    }

    func reset() {
        leftovers = []
        communityTurn = 0
        blendPlaced = 0
    }

    /// First page when `after` is nil, else the page after that cursor.
    /// `loaded` = posts currently shown (excluded from later pages; a refresh
    /// demotes the old top 10). Posts carry feedReason.
    func page(after: String?, loaded: [Post]) async throws -> Listing<Post> {
        let firstPage = after == nil
        if firstPage { progress = 0 }
        if firstPage { await seedIfNeeded() }
        let page = try await getForYouFeed(
            inputs: rankInputs(firstPage: firstPage, loaded: loaded),
            communities: firstPage ? candidateCommunities() : [],
            cursors: after, // nil = first page; else the encoded cursor bundle
            excludeIds: firstPage ? [] : Set(loaded.map(\.id)),
            carryOver: firstPage ? [] : leftovers
        )
        leftovers = page.leftovers
        m.meta = firstPage ? page.meta.dictionary : m.meta.merging(page.meta.dictionary) { _, new in new }
        m.docFreq.observe(page.candidateTitles)
        for p in page.listing.items { m.metrics.count("src.ranked.\(page.meta[p.id]?.source ?? "other")") }
        let user = c.session.username
        if firstPage && !user.isEmpty {
            // In the background: the page is ready; saving it shouldn't hold it up.
            let (items, repo) = (page.listing.items, repo)
            Task.detached { await saveForYouPage(user: user, posts: items, raw: { repo.rawPost($0) }) }
        }
        return page.listing
    }

    private nonisolated static func subsSnapshotFile(_ user: String) -> URL {
        FileLocations.files.appendingPathComponent("fy_subs_\(user.lowercased()).json")
    }

    /// (favourites, subscribed), lowercase names, from the last fetched subscription list.
    private nonisolated static func loadSubsSnapshot(_ user: String) async -> (fav: [String], sub: [String])? {
        if user.isEmpty { return nil }
        guard let data = try? Data(contentsOf: subsSnapshotFile(user)),
              let o = try? AppJson.parse(data),
              let fav = o["fav"].arr(), let sub = o["sub"].arr() else { return nil }
        return (fav.compactMap { $0.str() }.uniqued(), sub.compactMap { $0.str() }.uniqued())
    }

    private nonisolated static func saveSubsSnapshot(_ user: String, _ subs: [Subreddit]) {
        if user.isEmpty { return }
        let json: JsonElement = [
            "fav": .array(subs.filter(\.userHasFavorited).map { .string($0.name.lowercased()) }),
            "sub": .array(subs.map { .string($0.name.lowercased()) }),
        ]
        try? Data(json.encoded().utf8).write(to: subsSnapshotFile(user), options: .atomic)
    }

    /// The last saved first page minus posts opened since, to paint instantly.
    func cachedFirstPage() async -> Listing<Post>? {
        let user = c.session.username
        if user.isEmpty { return nil }
        guard let posts = await loadForYouPage(user: user, opened: c.history.ids, feed: "foryou") else { return nil }
        return Listing(items: posts, after: nil)
    }

    func cachedFirstPageTime() async -> Int? {
        let user = c.session.username
        return user.isEmpty ? nil : await savedPageTime(user: user, feed: "foryou")
    }

    /// Snapshot of everything For You learned, for the ranker.
    private func rankInputs(firstPage: Bool, loaded: [Post]) -> RankInputs {
        let idf = m.docFreq.idfFunction()
        let settings = c.settings.value
        return RankInputs(
            interest: m.interest.value.dictionary,
            subStats: m.subStats.value.dictionary.mapValues { ($0.seen, $0.engaged) },
            explicit: m.explicit.value,
            keywordScore: m.keywords.scorer(idf: idf),
            topKeyword: m.keywords.topKeywordFinder(idf: idf),
            muted: Set(m.muted.value),
            openedAt: Dictionary(c.history.state.map { ($0.id, $0.viewedAt) }, uniquingKeysWith: { _, last in last }),
            impressions: m.impressions.counter(),
            // A refresh makes room: the old top 10 is demoted a little.
            previousTop: firstPage ? Set(loaded.prefix(10).map(\.id)) : [],
            // Stories already shown on earlier pages count toward repeats.
            previousTitles: firstPage ? [] : loaded.reversed().prefix(100).map(\.title),
            discoveryAppetite: m.metrics.discoveryAppetite(),
            discoveryMix: settings.forYouDiscovery,
            typeStats: m.typeStats.value.dictionary.mapValues { ($0.seen, $0.engaged) },
            blendReddit: settings.blendReddit
        )
    }

    /// Communities you've dipped into but don't follow (0.5 ≤ interest < 2),
    /// plus ones you asked for more of: three per refresh, rotating, as
    /// personalised discovery instead of r/popular alone.
    private func candidateCommunities() -> [String] {
        let explicitMore = m.explicit.value.subs.filter { $0.value > 0 }.map(\.key)
        let visited = m.interest.value
            .filter { $0.value >= 0.5 && $0.value < kEngagedInterest }
            .sorted { $0.value > $1.value }
            .map(\.key)
        let all = (explicitMore + visited).uniqued()
        if all.isEmpty { return [] }
        let start = (communityTurn * 3) % all.count
        communityTurn += 1
        return (0..<min(3, all.count)).map { all[(start + $0) % all.count] }
    }

    /// Cold start: the first time For You runs for an account, seed its model
    /// from the user's own Reddit activity (their upvoted and saved posts — data
    /// Reddit already holds for them, nothing third-party) plus local history,
    /// so day one already prefers what they actually like. Once per account,
    /// and only while history tracking is on.
    private func seedIfNeeded() async {
        if !c.settings.value.trackHistory { return }
        guard let session = c.session.session, !session.anonymous, !session.username.isEmpty else { return }
        let key = userScopedKey(c.prefs, session.username, "fy_seeded")
        if c.prefs.getBool(key) == true { return }
        c.prefs.setBool(key, true) // don't retry every page on failure

        let (repo, user) = (repo, session.username)
        async let up = try? repo.getUserPosts(user, where: "upvoted", limit: 100).items
        async let sv = try? repo.getUserSaved(user, limit: 100).items
        let upvoted = await up ?? []
        let saved = (await sv ?? []).compactMap { item -> Post? in
            if case let .post(p) = item { p } else { nil }
        }

        var deltas: [String: Double] = [:]
        func add(_ sub: String, _ d: Double) {
            let k = sub.lowercased()
            deltas[k] = min(max((deltas[k] ?? 0) + d, 0), 6)
        }
        for p in upvoted { add(p.subreddit, 1.0) }
        for p in saved { add(p.subreddit, 2.0) }
        for e in c.history.state { add(e.subreddit, 0.3) }
        m.interest.seed(deltas)
        m.keywords.seedTitles((upvoted + saved).map(\.title), 0.3)
    }

    /// Candidates: /best (subscriptions; paginated), rising and r/popular
    /// (paginated), and on the first page hot posts from favourites, the most
    /// engaged communities and a few `communities` the user has visited.
    /// `carryOver` is the previous page's unplaced pool.
    private func getForYouFeed(
        inputs: RankInputs,
        communities: [String],
        cursors: String?, // JSON cursor bundle from a previous page's `after`
        excludeIds: Set<String>,
        carryOver: [Candidate]
    ) async throws -> ForYouPage {
        var prev: [String: String?] = [:]
        if let cursors, !cursors.isEmpty, let o = parseJsonOrNull(cursors).obj() {
            for (k, v) in o { prev[k] = .some(v.str()) }
        }
        var page: ForYouPage!
        // An empty page (everything failed, or all muted/seen) retries the next
        // cursors once before ending the feed — it used to stop dead.
        for attempt in 0..<2 {
            // First page only without a cursor at all: once every source has run
            // out the cursor is empty ({}), and the leftovers page on from there.
            let first = (cursors ?? "").isEmpty && attempt == 0
            let pg = try await forYouPage(inputs, communities, prev, excludeIds, attempt == 0 ? carryOver : [], first)
            page = pg
            if !pg.listing.items.isEmpty || pg.cursors.isEmpty { break }
            prev = pg.cursors.mapValues { .some($0) }
        }
        return page
    }

    /// One source's outcome: nil listing = failed or timed out.
    private struct SourceResult: Sendable {
        let key: String
        let listing: Listing<Post>?
        let error: Error?
    }

    private func forYouPage(
        _ inputs: RankInputs,
        _ communities: [String],
        _ prev: [String: String?],
        _ excludeIds: Set<String>,
        _ carryOver: [Candidate],
        _ firstPage: Bool
    ) async throws -> ForYouPage {
        let repo = repo
        let muted = inputs.muted

        // Subreddits you engage with most (learned on-device), even if not
        // favourited. Local data, so known before any request goes out.
        let topInterest = Array(inputs.interest
            .filter { $0.value >= kEngagedInterest && !muted.contains($0.key) }
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map(\.key))

        // A cursor of "" means "start this source from the top" (its first
        // fetch failed); a missing key means the source is exhausted.
        func live(_ k: String) -> Bool { firstPage || prev.keys.contains(k) }
        func after(_ k: String) -> String? { (prev[k] ?? nil)?.nilIfEmpty }

        // Favourites and subscriptions: from the last snapshot when there is one,
        // so favourites go out with everything else instead of waiting ~2s for
        // the subscription list; the live list refreshes the snapshot for next time.
        let user = c.session.username
        let snapshot = await Task.detached { await Self.loadSubsSnapshot(user) }.value
        if snapshot != nil {
            Task.detached {
                if let subs = try? await repo.getSubscribedSubreddits() { Self.saveSubsSnapshot(user, subs) }
            }
        }

        // Blend (Beta): your Reddit Home is one more source, ranked with the
        // rest. It's slow to read (a hidden browser), so the first page waits
        // only so long for it; later pages read the next batch.
        let s = c.settings.value
        let blend = s.forYouFeed && s.blendHome && s.redditHomeAllowed
        let homeBatch = blend && (firstPage || prev.keys.contains("home")) ? m.redditHome.blendBatch(first: firstPage) : nil

        var favourites: [String] = snapshot?.fav ?? []
        var subscribed: [String] = snapshot?.sub ?? []
        let favRotation = userScopedKey(c.prefs, user, "fy_fav_rotation")
        let prefs = c.prefs

        // Inside a task group, so cancelling the page (a newer refresh) cancels every source.
        let results: [SourceResult] = await withTaskGroup(of: SourceResult.self) { group in
            // Each source: its listing, or nil if it failed / timed out. Secondary
            // sources get a short timeout so the slowest community doesn't decide how
            // long the page takes.
            func source(_ key: String, secondary: Bool = true, _ f: @escaping @Sendable () async throws -> Listing<Post>) {
                group.addTask { [weak self] in
                    do {
                        let listing = secondary ? try await withTimeoutOrNil(2500, f) : try await f()
                        if let listing, firstPage {
                            await MainActor.run { self?.progress += listing.items.count }
                        }
                        return SourceResult(key: key, listing: listing, error: nil)
                    } catch {
                        // A cancelled request isn't a failure to report.
                        let cancelled = error is CancellationError || (error as? URLError)?.code == .cancelled
                        return SourceResult(key: key, listing: nil, error: cancelled ? nil : error)
                    }
                }
            }

            if live("best") {
                let (limit, cursor) = (firstPage ? 100 : 50, after("best"))
                source("best", secondary: false) { try await repo.getPosts(sort: .best, after: cursor, limit: limit) }
            }
            if live("rising") {
                let cursor = after("rising")
                source("rising") { try await repo.getPosts(sort: .rising, after: cursor, limit: 25) }
            }
            if live("popular") {
                let (limit, cursor) = (firstPage ? 20 : 15, after("popular"))
                source("popular") { try await repo.getPosts(subreddit: "popular", sort: .hot, after: cursor, limit: limit) }
            }
            if firstPage {
                for (i, sub) in topInterest.enumerated() {
                    source("interest.\(i)") { try await repo.getPosts(subreddit: sub, sort: .hot, limit: 8) }
                }
                for (i, sub) in communities.filter({ !muted.contains($0) }).enumerated() {
                    source("community.\(i)") { try await repo.getPosts(subreddit: sub, sort: .hot, limit: 6) }
                }
            }

            if snapshot == nil {
                let mySubs = (try? await repo.getSubscribedSubreddits()) ?? []
                if !mySubs.isEmpty { Self.saveSubsSnapshot(user, mySubs) }
                favourites = mySubs.filter(\.userHasFavorited).map { $0.name.lowercased() }.uniqued()
                subscribed = mySubs.map { $0.name.lowercased() }
            }
            // Favourites go out the moment the list is known, while the rest is still
            // in flight. One already fetched as a top interest isn't fetched twice.
            // Eight per load; with more favourites than that, each load takes the
            // next eight in turn (only the first eight ever got fetched before).
            if firstPage {
                let favs = favourites.filter { !topInterest.contains($0) && !muted.contains($0) }
                var pick = favs
                if favs.count > 8 {
                    let turn = prefs.getInt(favRotation) ?? 0
                    let start = ((turn % favs.count) + favs.count) % favs.count
                    prefs.setInt(favRotation, start + 8)
                    pick = (0..<8).map { favs[(start + $0) % favs.count] }
                }
                for (i, sub) in pick.enumerated() {
                    source("favourite.\(i)") { try await repo.getPosts(subreddit: sub, sort: .hot, limit: 10) }
                }
            }

            var out: [SourceResult] = []
            for await r in group { out.append(r) }
            return out
        }
        try Task.checkCancellation()

        let byKey = Dictionary(results.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        func listing(_ key: String) -> Listing<Post>? { byKey[key]?.listing }

        var ids = excludeIds
        var pool: [Candidate] = []
        func add(_ l: Listing<Post>?, _ src: String) {
            for p in l?.items ?? [] where ids.insert(p.id).inserted { pool.append(Candidate(post: p, source: src)) }
        }

        // Blend: Reddit's Home batch first, so a post it also recommends counts
        // as Reddit's pick whichever source found it too (de-duplication used
        // to keep whichever came first and drop the Home signal). Wait only so
        // long — the first page shows the loading deck meanwhile, as Home
        // does; a batch still loading joins the next page instead.
        if let homeBatch {
            let deadline = nowMillis() + (firstPage ? 10_000 : 12_000)
            while homeBatch.result == nil, nowMillis() < deadline {
                try await Task.sleep(for: .milliseconds(100))
            }
        }
        let homeResult = homeBatch?.result
        if let homeBatch, homeResult == nil { m.redditHome.blendKeep(homeBatch) }
        if case let .posts(home) = homeResult {
            for (i, p) in home.enumerated() where ids.insert(p.id).inserted {
                pool.append(Candidate(post: p, source: "home", homePos: Double(i) / Double(max(home.count - 1, 1))))
            }
            if !home.isEmpty { m.redditHome.blendPrefetch() }
        }
        // Held over from the last page ("home" ones stay Reddit's picks).
        for cand in carryOver where ids.insert(cand.post.id).inserted {
            pool.append(cand.source == "home" ? cand : Candidate(post: cand.post, source: "carry"))
        }
        add(listing("best"), "best")
        add(listing("rising"), "rising")
        add(listing("popular"), "popular")
        for i in 0..<8 { add(listing("favourite.\(i)"), "favourite") }
        for i in 0..<5 { add(listing("interest.\(i)"), "interest") }
        for i in 0..<3 { add(listing("community.\(i)"), "community") }

        // Every source failed (offline, rate-limited…): say so, rather than
        // showing an empty feed that just ends.
        if pool.isEmpty, let firstError = results.lazy.compactMap(\.error).first { throw firstError }
        let ranked = inputs.withSubscriptions(favourites: Set(favourites), subscribed: Set(subscribed))
        let finalPool = pool
        let result = await Task.detached { rankForYou(finalPool, ranked) }.value

        // Next cursors. A source that failed keeps its place (it used to be
        // dropped for the rest of the session — one timeout on /best and the
        // feed quietly became r/popular); an exhausted one is left out.
        var next: [String: String] = [:]
        if homeBatch != nil {
            let (cursor, state) = blendNext(previous: prev["home"] ?? nil, result: homeResult, firstPage: firstPage)
            if let cursor { next["home"] = cursor }
            // "8 Reddit Home picks" in the header: placed in this feed so far.
            let placedHome = result.ranked.count { result.meta[$0.id]?.source == "home" }
            blendPlaced = (firstPage ? 0 : blendPlaced) + placedHome
            m.redditHome.blendState = state ?? .included(count: blendPlaced)
        }
        for key in ["best", "rising", "popular"] where live(key) {
            if let l = listing(key) {
                if let cursor = l.after, !cursor.isEmpty { next[key] = cursor }
            } else {
                next[key] = (prev[key] ?? nil) ?? ""
            }
        }
        // More while a source has a next page, or ranked posts are still waiting
        // (once every source ran out, its leftovers used to be unreachable).
        let hasMore = (!result.ranked.isEmpty || !result.leftovers.isEmpty) && (!next.isEmpty || !result.leftovers.isEmpty)
        var cursorJson = JsonObject()
        for k in next.keys.sorted() { cursorJson[k] = .string(next[k]!) }
        return ForYouPage(
            listing: Listing(items: result.ranked, after: hasMore ? cursorJson.encoded() : nil),
            cursors: next,
            leftovers: result.leftovers,
            meta: result.meta,
            candidateTitles: pool.map(\.post.title)
        )
    }
}
