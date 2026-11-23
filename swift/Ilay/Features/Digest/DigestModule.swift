import Foundation
import Observation

/// The Digest (docs/digest-spec.md): builds and refreshes today's digest from the top
/// posts of the day in the chosen communities, and keeps the last week of them.
@MainActor @Observable
final class DigestModule: UserScoped {
    static let maxCommunities = 15
    /// A build's Reddit requests: the combined listings, then top-ups up to this.
    static let maxRequests = 6
    static let upToDateMs = 2 * 60_000
    static let staleMs = 12 * 60 * 60_000

    @ObservationIgnored private unowned let c: AppContainer
    let store: DigestStore

    /// A build or refresh is running.
    private(set) var building = false
    /// What the running build is doing ("Loading posts (4/15)…"), for the screen.
    private(set) var progress: String?
    /// Posts shows the Digest (its chip picked). Not a feed choice: not saved, so a launch opens the feed.
    var onPosts = false
    /// The communities picked in Settings (lowercase), or nil to follow your favourites.
    private(set) var chosen: [String]?

    @ObservationIgnored private var job: Task<Outcome, Never>?
    @ObservationIgnored private var user = ""

    /// How a build or refresh went.
    enum Outcome: Sendable {
        /// `added`: new posts today's digest gained (all of them on a first build).
        case updated(added: Int)
        /// Refreshed moments ago: shown as it is.
        case upToDate
        case noCommunities
        case signedOut
        case failed(String)
    }

    init(_ c: AppContainer) {
        self.c = c
        let repo = c.repository
        store = DigestStore(raw: { repo.rawPost($0) })
    }

    func onUserChanged(_ username: String) {
        job?.cancel()
        job = nil
        user = username
        onPosts = false
        chosen = c.prefs.getStringList(subsKey())
        store.onUserChanged(username)
    }

    private func subsKey() -> String { userScopedKey(c.prefs, user, "digestSubs") }

    /// Sets the communities (lowercase names, at most `maxCommunities`); nil follows your favourites again.
    func setCommunities(_ names: [String]?) {
        let list = names.map { Array($0.map { $0.lowercased() }.uniqued().prefix(Self.maxCommunities)) }
        if let list { c.prefs.setStringList(subsKey(), list) } else { c.prefs.remove(subsKey()) }
        chosen = list
    }

    /// Your starred favourites, from the subscription list (cached; asked for once if it isn't).
    func favourites() async throws -> [String] {
        let subs = try await c.repository.getSubscribedSubreddits()
        return subs.filter(\.userHasFavorited).map { $0.name.lowercased() }
    }

    /// The communities a digest is built from.
    func communities() async throws -> [String] {
        let list: [String]
        if let chosen { list = chosen } else { list = try await favourites() }
        return Array(list.prefix(Self.maxCommunities))
    }

    func today() -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    /// Builds today's digest, or refreshes it: only posts not judged yet are judged
    /// (`mergeDigest`). `manual`: the user asked (pull to refresh), so one within
    /// `upToDateMs` of the last just shows what's there. `rebuild`: forget today's and
    /// start over. One at a time: a second call while one runs gets its result.
    @discardableResult
    func refresh(manual: Bool, rebuild: Bool = false) async -> Outcome {
        if let job { return await job.value }
        let t = Task { await build(manual: manual, rebuild: rebuild) }
        job = t
        let out = await t.value
        job = nil
        return out
    }

    /// Opening the Digest: builds today's when there is none, or it's more than `staleMs` old.
    func refreshIfStale() async -> Outcome? {
        await store.loaded()
        if let d = store.today(today()), nowMillis() - d.refreshedAt < Self.staleMs { return nil }
        return await refresh(manual: false)
    }

    func markSeen() { store.markSeen(today(), at: nowMillis()) }

    private func build(manual: Bool, rebuild: Bool) async -> Outcome {
        guard let session = c.session.session, !session.anonymous else { return .signedOut }
        await store.loaded()
        let day = today()
        let now = nowMillis()
        let prev = rebuild ? nil : store.today(day)
        if manual, let prev, now - prev.refreshedAt < Self.upToDateMs { return .upToDate }
        building = true
        defer {
            building = false
            progress = nil
        }
        do {
            let subs = try await communities()
            if subs.isEmpty { return .noCommunities }
            let filters = c.contentFilters.value
            let hidden = c.hiddenPosts.ids
            let candidates = try await fetchCandidates(subs).filter { !hidden.contains($0.id) && !filters.hides($0) }
            let size = DigestSize.of(c.settings.value.digestSize)
            let read = c.history.ids
            let s = c.settings.value
            // The AI step (spec section 6), when "Use AI" is on and there's a key, for the builds
            // it's chosen for (Settings: every build, or the day's first and Rebuild), and the
            // parts chosen: picking, the "why" lines, the overview (only on the day's first build).
            // Only posts not judged yet; an automatic build calls at most once in 12 hours.
            let first = prev == nil
            let overview = s.digestOverview && first
            let key = s.digestAi && (first || s.digestAiBuilds == 0) ? await c.secureStore.openaiKey() : nil
            let due = manual || first || now - (prev?.aiAt ?? 0) >= Self.staleMs
            let useAi = key?.isEmpty == false && due && (s.digestAiPick || s.digestAiWhy || overview)
            let baseUrl = s.aiUseCustomUrl ? s.aiBaseUrl : "https://api.openai.com"
            let language = s.digestLanguage ?? s.aiSummaryLanguage
            let interests = interests()
            func ask(_ posts: [Post], rate: Bool) async -> DigestAi? {
                progress = rate ? "Asking the AI about \(posts.count) posts…" : "The AI is writing about \(posts.count) posts…"
                let (system, user) = digestAiMessages(posts, interests: interests, size: size, overview: overview, language: language, now: now, rate: rate, why: s.digestAiWhy)
                // Unreachable, refused or unreadable: by the numbers, and the screen says so.
                guard let key, let reply = try? await AiService.digest(baseUrl: baseUrl, apiKey: key, model: s.aiModel, system: system, user: user) else { return nil }
                return parseDigestAi(reply, posts: posts, rated: rate)
            }
            let merged: DigestDay
            if useAi && s.digestAiPick {
                // The AI picks, from the posts not judged yet.
                let pending = digestPending(prev, day: day, candidates: candidates, readIds: read, now: now)
                let ai = pending.isEmpty ? nil : await ask(pending, rate: true)
                merged = mergeDigest(prev, day: day, candidates: candidates, readIds: read, size: size, now: now, ai: ai, aiFailed: !pending.isEmpty && ai == nil)
            } else {
                // The numbers pick; the AI, if wanted, only writes about the new picks.
                progress = "Picking the notable posts…"
                let numbers = mergeDigest(prev, day: day, candidates: candidates, readIds: read, size: size, now: now)
                let added = numbers.items.filter { $0.addedAt == now }.map(\.post)
                if useAi && !added.isEmpty && (s.digestAiWhy || overview) {
                    if let ai = await ask(added, rate: false) {
                        merged = explainDigest(numbers, ai: ai, now: now)
                    } else {
                        var failed = numbers
                        failed.aiFailed = true
                        failed.aiAt = now
                        merged = failed
                    }
                } else {
                    merged = numbers
                }
            }
            if Task.isCancelled || c.session.username != session.username { return .failed("Account changed") }
            store.put(merged)
            return .updated(added: merged.items.count - (prev?.items.count ?? 0))
        } catch {
            return .failed(friendlyError(error))
        }
    }

    /// What the AI is told about you: For You's strongest words, and your More / Less choices.
    private func interests() -> DigestInterests {
        let f = c.forYou
        let explicit = f.explicit.value
        return DigestInterests(
            keywords: Array(f.keywords.value.filter { $0.value > 0 }.sorted { $0.value > $1.value }.prefix(15).map(\.key)),
            moreTopics: explicit.topics.filter { $0.value > 0 }.map(\.key),
            lessTopics: explicit.topics.filter { $0.value < 0 }.map(\.key),
            moreCommunities: explicit.subs.filter { $0.value > 0 }.map(\.key),
            lessCommunities: explicit.subs.filter { $0.value < 0 }.map(\.key)
        )
    }

    /// The day's top posts in `subs`: up to eight communities a request (/r/a+b+c/top),
    /// then, for a community the combined listing barely reached (big ones crowd it), one
    /// request of its own while the build stays within `maxRequests`.
    private func fetchCandidates(_ subs: [String]) async throws -> [Post] {
        let repo = c.repository
        progress = "Loading posts from \(subs.count) communities…"
        loadedCount = 0
        loadingCount = subs.count
        let groups = stride(from: 0, to: subs.count, by: 8).map { Array(subs[$0..<min($0 + 8, subs.count)]) }
        var got: [Post] = []
        var firstError: Error?
        var answered = false
        await withTaskGroup(of: Result<[Post], Error>.self) { g in
            for group in groups { g.addTask { await Self.group(repo, group) { [weak self] in await self?.countLoaded() } } }
            for await r in g {
                switch r {
                case .success(let posts):
                    answered = true
                    got += posts
                case .failure(let e):
                    if firstError == nil { firstError = e }
                }
            }
        }
        if !answered { throw firstError ?? URLError(.badServerResponse) }
        var counts: [String: Int] = [:]
        for p in got { counts[p.subreddit.lowercased(), default: 0] += 1 }
        // (The website sign-in already asked each community on its own: nothing to top up.)
        let web = await repo.client.isWebMode()
        let thin = web ? [] : Array(subs.filter { counts[$0, default: 0] < 3 }.prefix(max(Self.maxRequests - groups.count, 0)))
        let more = await withTaskGroup(of: [Post].self) { g in
            for s in thin {
                g.addTask { (try? await repo.getPosts(subreddit: s, sort: .top, time: .day, limit: 10).items) ?? [] }
            }
            var all: [Post] = []
            for await l in g { all += l }
            return all
        }
        var seen = Set<String>()
        return (got + more).filter { seen.insert($0.id).inserted }
    }

    @ObservationIgnored private var loadedCount = 0
    @ObservationIgnored private var loadingCount = 0

    /// One community at a time: count them.
    private func countLoaded() {
        loadedCount += 1
        progress = "Loading posts (\(loadedCount)/\(loadingCount))…"
    }

    private static func group(_ repo: RedditRepository, _ subs: [String], loaded: @escaping @Sendable () async -> Void) async -> Result<[Post], Error> {
        do {
            // The website sign-in gets Reddit's web page for a combined listing, never the listing.
            if subs.count > 1, await repo.client.isWebMode() { throw RedditApiException(statusCode: 403) }
            return .success(try await repo.getPosts(subreddit: subs.joined(separator: "+"), sort: .top, time: .day, limit: 100).items)
        } catch let e as RedditApiException where (e.statusCode == 403 || e.statusCode == 200) && subs.count > 1 {
            // Where Reddit refuses the combined listing, one community at a time: a 403, or its
            // web page instead of the listing (a 200 that isn't JSON).
            let posts = await withTaskGroup(of: [Post].self) { g in
                for s in subs {
                    g.addTask {
                        let posts = (try? await repo.getPosts(subreddit: s, sort: .top, time: .day, limit: 10).items) ?? []
                        await loaded()
                        return posts
                    }
                }
                var all: [Post] = []
                for await l in g { all += l }
                return all
            }
            return .success(posts)
        } catch {
            return .failure(error)
        }
    }
}
