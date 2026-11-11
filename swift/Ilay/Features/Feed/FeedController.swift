import Foundation
import Observation

struct FeedState: Equatable {
    var posts: [Post]
    var sort: PostSort
    var time: TopTime
    var after: String? = nil
    var loadingMore = false
    var hasPending = false // a fresh page is staged behind a "New posts" pill

    var hasMore: Bool { after?.isEmpty == false }
}

/// The feed's async state (Riverpod's AsyncValue<FeedState>).
enum FeedUi {
    case loading
    case error(Error)
    case data(FeedState)

    var state: FeedState? {
        if case let .data(s) = self { s } else { nil }
    }

    var isLoading: Bool {
        if case .loading = self { true } else { false }
    }

    var isError: Bool {
        if case .error = self { true } else { false }
    }
}

/// Where a plain (not For You / Home) feed gets its pages; tests replace it.
struct FeedSource {
    let posts: (_ sort: PostSort, _ time: TopTime, _ after: String?) async throws -> Listing<Post>
    let cached: (_ sort: PostSort, _ time: TopTime) async -> Listing<Post>?

    /// The Reddit listing for a feed key.
    @MainActor static func reddit(_ key: String) -> FeedSource {
        let repo = app.repository
        if let (user, name) = FeedController.multi(key) {
            return FeedSource(
                posts: { sort, time, after in try await repo.getMultiPosts(username: user, multiname: name, sort: sort, time: time, after: after) },
                cached: { _, _ in nil }
            )
        }
        let subreddit = key.isEmpty ? nil : key
        return FeedSource(
            posts: { sort, time, after in try await repo.getPosts(subreddit: subreddit, sort: sort, time: time, after: after) },
            cached: { sort, time in await repo.cachedPosts(subreddit: subreddit, sort: sort, time: time) }
        )
    }
}

/// Paging cursor of a page restored from disk (it has no real cursor).
private let restoredPage = "restored"

/// Feed for the frontpage (key == ""), a subreddit (key == name) or a multireddit
/// (key == "m::username::multiname"). Owned by `FeedModule`, so it outlives the screen
/// (back navigation repaints instantly).
@MainActor @Observable final class FeedController {
    let key: String
    private(set) var ui: FeedUi = .loading
    private(set) var sort: PostSort
    private(set) var time: TopTime

    @ObservationIgnored private let source: FeedSource
    @ObservationIgnored private var started = false
    @ObservationIgnored private var cacheConsulted = false
    @ObservationIgnored private var showingCache = false // a cached page is on screen, fresh one in flight
    // Bumped whenever the list is replaced (load, refresh, sort, "New posts"),
    // so a page that was in flight for the old list is dropped, not appended.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var lastLoaded = 0
    @ObservationIgnored private var buildJob: Task<Void, Never>?
    @ObservationIgnored private var buildToken = 0
    @ObservationIgnored private var moreJob: Task<Void, Never>?
    @ObservationIgnored private var staleJob: Task<Void, Never>?
    @ObservationIgnored private(set) var isBuilding = false
    // A freshly-fetched first page staged behind the "New posts" pill.
    @ObservationIgnored private var pending: [Post]?
    @ObservationIgnored private var pendingAfter: String?
    /// Opens the full-screen media browser (#103) from the post at the top of this feed's
    /// list on screen. Set by that list, which knows what's on screen and what's filtered out.
    @ObservationIgnored var browseMedia: (() -> Void)?

    private var engines: FeedEngines? { app.feed.engines }
    private var isFrontpage: Bool { key.isEmpty }
    private var current: FeedState? { ui.state }

    /// A multireddit feed key looks like `m::username::multiname`.
    nonisolated static func multi(_ key: String) -> (user: String, name: String)? {
        guard key.hasPrefix("m::") else { return nil }
        let parts = key.components(separatedBy: "::")
        return parts.count == 3 ? (parts[1], parts[2]) : nil
    }

    /// How long a loaded frontpage is kept before returning to it loads a new one (Settings → Keep feed for).
    private var keepMillis: Int { app.settings.value.feedKeepMinutes * 60_000 }
    // With the Posts tab on r/all (Settings) the frontpage is a plain pushed page.
    private var forYou: Bool { isFrontpage && !app.settings.value.postsTabAll && app.settings.value.forYouFeed && engines != nil }

    /// Experimental Reddit Home (opt-in after a risk warning in Settings).
    private var redditHome: Bool {
        let s = app.settings.value
        return isFrontpage && !s.postsTabAll && s.redditHomeAllowed && s.redditHomeFeed && engines != nil
    }

    /// Home and For You open with the shuffling deck and deal their cards in,
    /// rather than painting the last saved page and then swapping it out.
    var deckMode: Bool { redditHome || forYou }

    init(key: String, source: FeedSource? = nil) {
        self.key = key
        self.source = source ?? .reddit(key)
        // A subreddit can have its own default (#60), set in its About sheet.
        let own = app.settings.value.subredditSorts[key.lowercased()]
        sort = own?.sort ?? app.settings.value.defaultSort
        time = own?.time ?? .day
    }

    /// First use: builds the feed (Riverpod builds a provider on first watch).
    func start() {
        if started { return }
        started = true
        // Reddit Home deals its cards straight from the page; the full posts (media,
        // video, NSFW…) arrive moments later and replace them in place.
        if isFrontpage {
            engines?.onHomeUpgrades = { [weak self] full in
                guard let self, var cur = self.current else { return }
                let byId = Dictionary(full.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                if !cur.posts.contains(where: { byId[$0.id] != nil }) { return }
                cur.posts = cur.posts.map { byId[$0.id] ?? $0 }
                self.ui = .data(cur)
            }
        }
        if app.navigator.restoredProcess && deckMode {
            app.navigator.restoredProcess = false // once; a later frontpage (account switch) loads normally
            restoreOrBuild()
        } else {
            rebuild(showLoading: deckMode)
        }
    }

    /// Back after iOS ended the app in the background: Home / For You show the page
    /// saved with the last load if it's younger than the "Keep feed for" time, exactly
    /// as if the app had stayed open; otherwise they load as usual.
    private func restoreOrBuild() {
        ui = .loading
        isBuilding = true
        buildToken += 1
        let token = buildToken
        buildJob = Task { [self] in
            let savedAt = try? await (redditHome ? engines?.homeCachedFirstPageTime() : engines?.forYouCachedFirstPageTime())
            let fresh = (savedAt ?? nil).map { nowMillis() - $0 < keepMillis } == true
            let page = fresh ? await cachedFirstPage() : nil
            guard token == buildToken else { return }
            isBuilding = false
            if let page, let savedAt = savedAt ?? nil {
                lastLoaded = savedAt
                if redditHome { engines?.homeStatus = .saved(at: savedAt) }
                // The saved page has no paging cursor: mark it so reaching its
                // end fetches more (see loadMore) instead of stopping there.
                ui = .data(FeedState(posts: page.items, sort: sort, time: time, after: page.after ?? restoredPage))
            } else {
                rebuild(showLoading: true)
            }
        }
    }

    /// Returning to the frontpage (from a post, or the app from the background): it
    /// keeps its posts for the "Keep feed for" time; after that it loads anew, as on a
    /// fresh launch. Pull-to-refresh is the way to replace it sooner.
    func refreshIfExpired() {
        if isBuilding || current == nil { return }
        if nowMillis() - lastLoaded < keepMillis { return }
        rebuild(showLoading: deckMode)
    }

    func dispose() {
        if isFrontpage {
            engines?.onHomeUpgrades = nil
            engines?.disposeHome()
        }
        buildJob?.cancel()
        moreJob?.cancel()
        staleJob?.cancel()
        generation += 1
    }

    /// "Hide read posts": drops posts already in history as each page arrives.
    /// Filtering when fetched rather than live keeps a post you've just read (or
    /// scrolled past) from vanishing under you; the next load skips it. It covers For You
    /// too (#148); For You's own option also hides them live, as you read. Reddit Home
    /// is left as Reddit sends it. Feeds only (front page, custom feeds) unless "Also in
    /// subreddits" is on: browsing one subreddit you often want to see what you've read.
    private func dropRead(_ listing: Listing<Post>) -> Listing<Post> {
        let s = app.settings.value
        if redditHome || !s.hideReadPosts { return listing }
        // The feed the Posts tab shows (r/all with that setting) counts as the front page here.
        let subreddit = !key.isEmpty && !key.hasPrefix("m::") && key != s.postsTabKey
        if subreddit && !s.hideReadInSubreddits { return listing }
        let read = app.history.ids
        if read.isEmpty { return listing }
        return Listing(items: listing.items.filter { !read.contains($0.id) }, after: listing.after, fromCache: listing.fromCache)
    }

    private func fetch(after: String? = nil) async throws -> Listing<Post> {
        // A page that was all read comes back empty, and an empty page never asks
        // for the next one: try a few more before giving up.
        var page = dropRead(try await fetchRaw(after))
        var tries = 0
        while page.items.isEmpty, let next = page.after, tries < 3 {
            tries += 1
            page = dropRead(try await fetchRaw(next))
        }
        return page
    }

    private func fetchRaw(_ after: String?) async throws -> Listing<Post> {
        let loaded = current?.posts ?? []
        // Reddit Home (falls back to For You itself, with a notice) and For
        // You are ranked/loaded by the For You module.
        if redditHome, let engines { return try await engines.homePage(after: after, loaded: loaded) }
        if forYou, let engines { return try await engines.forYouPage(after: after, loaded: loaded) }
        return try await source.posts(sort, time, after)
    }

    private func cachedFirstPage() async -> Listing<Post>? {
        // The last Home / For You page, minus posts opened since, while the
        // fresh one loads.
        if redditHome { return (try? await engines?.homeCachedFirstPage()) ?? nil }
        if forYou { return ((try? await engines?.forYouCachedFirstPage()) ?? nil).map(dropRead) }
        return await source.cached(sort, time).map(dropRead)
    }

    private func build() async throws -> FeedState {
        generation += 1
        // Paint the last cached page straight away on a cold open, before the
        // network answers: parsing a page costs milliseconds, the request costs
        // hundreds. Only once per feed — a refresh or sort change already has
        // intent behind it and shouldn't flash an older page.
        var cached: Listing<Post>?
        // In deck mode the saved page is only a fallback for a failed load, so
        // it's read only then (it used to delay every load by a disk read).
        if !cacheConsulted && !deckMode {
            cacheConsulted = true
            cached = await cachedFirstPage()
            try Task.checkCancellation()
            if let cached {
                showingCache = true
                ui = .data(FeedState(posts: cached.items, sort: sort, time: time, after: cached.after))
            }
        }
        // Retry once: a cold-start request can fail while the token is being
        // refreshed for the first time.
        let listing: Listing<Post>
        do {
            do {
                listing = try await fetch()
            } catch {
                try Task.checkCancellation()
                listing = try await fetch()
            }
        } catch {
            try Task.checkCancellation()
            // Keep the cached page rather than replacing it with an error: it's
            // still the most useful thing to show, and pull-to-refresh retries.
            if cached == nil && deckMode { cached = await cachedFirstPage() }
            guard let cached else { throw error }
            if redditHome, let at = (try? await engines?.homeCachedFirstPageTime()) ?? nil { engines?.homeStatus = .saved(at: at) }
            showingCache = false
            // Count the attempt as a load: otherwise every return to the feed
            // (refreshIfExpired) retried at once, swapping in the loading deck
            // and losing the scroll position each time while offline.
            lastLoaded = nowMillis()
            return FeedState(posts: cached.items, sort: sort, time: time, after: cached.after)
        }
        try Task.checkCancellation()
        showingCache = false
        lastLoaded = nowMillis()
        return FeedState(posts: listing.items, sort: sort, time: time, after: listing.after)
    }

    /// (Re)builds the feed. A newer build cancels an older one still in flight (e.g. a
    /// quick second sort change), so a slow stale page can't land on top of the newer list.
    @discardableResult private func rebuild(showLoading: Bool) -> Task<Void, Never> {
        buildJob?.cancel()
        let hadData = current != nil
        if showLoading, !ui.isLoading { ui = .loading }
        isBuilding = true
        buildToken += 1
        let token = buildToken
        let job = Task { [self] in
            defer { if token == buildToken { isBuilding = false } }
            do {
                ui = .data(try await build())
            } catch {
                if Task.isCancelled { return }
                // A failed pull-to-refresh keeps the posts on screen and says why.
                if !showLoading && hadData && current != nil {
                    app.navigator.showSnackbar(friendlyError(error))
                } else {
                    ui = .error(error)
                }
            }
        }
        buildJob = job
        return job
    }

    func changeSort(_ sort: PostSort, time: TopTime? = nil) {
        self.sort = sort
        if let time { self.time = time }
        // Persist the frontpage sort + turn off the For You / Home feeds.
        if isFrontpage {
            let s = app.settings
            s.setDefaultSort(sort)
            s.setForYouFeed(false)
            s.setBlendHome(false)
            s.setRedditHomeFeed(false)
        }
        rebuild(showLoading: true)
    }

    /// Switches the frontpage to the "For You" feed (persisted).
    func selectForYou() {
        app.settings.setForYouFeed(true)
        app.settings.setBlendHome(false)
        rebuild(showLoading: true)
    }

    /// Switches the frontpage to Blend (Beta): For You ranking over your Reddit Home too (persisted).
    func selectBlend() {
        app.settings.setForYouFeed(true)
        app.settings.setBlendHome(true)
        rebuild(showLoading: true)
    }

    /// Switches the frontpage to the experimental Reddit Home (persisted).
    func selectRedditHome() {
        app.settings.setBlendHome(false)
        app.settings.setRedditHomeFeed(true)
        rebuild(showLoading: true)
    }

    /// Pull-to-refresh: reloads with the current list kept on screen. Returns when done.
    func refresh() async {
        started = true
        await rebuild(showLoading: deckMode || (current == nil && !ui.isError)).value
    }

    /// Retry from the error view.
    func retry() {
        rebuild(showLoading: true)
    }

    /// A subreddit or custom feed opened again (#150): its posts are kept in memory
    /// (FeedModule), so it showed the list from last time until a pull. Older than
    /// `maxAgeMillis`, it loads anew; the old list stays up meanwhile.
    func reloadIfOld(maxAgeMillis: Int = 5 * 60_000) {
        if isBuilding { return }
        guard let cur = current, !cur.hasPending else { return }
        if nowMillis() - lastLoaded < maxAgeMillis { return }
        rebuild(showLoading: false)
    }

    /// When returning to a stale feed, quietly fetch the first page. If it has posts
    /// we're not already showing, stage them behind a "New posts" pill instead of
    /// yanking the list out from under the user.
    func refreshIfStale(maxAgeMillis: Int = 5 * 60_000) {
        if isBuilding { return }
        guard let cur = current else { return }
        if cur.hasPending { return } // already staged
        if nowMillis() - lastLoaded < maxAgeMillis { return }
        let gen = generation
        staleJob = Task { [self] in
            // A failure leaves the current feed in place.
            guard let listing = try? await fetch() else { return }
            lastLoaded = nowMillis()
            guard gen == generation, var latest = current else { return }
            let currentIds = Set(latest.posts.map(\.id))
            // For You re-ranks rising posts every time, so "anything new" was
            // almost always true; it needs 3 new posts in the new top 10.
            let hasNew = forYou
                ? listing.items.prefix(10).filter { !currentIds.contains($0.id) }.count >= 3
                : listing.items.contains { !currentIds.contains($0.id) }
            if hasNew {
                pending = listing.items
                pendingAfter = listing.after
                latest.hasPending = true
                ui = .data(latest)
            }
        }
    }

    /// Swaps the staged "New posts" page in (called when the pill is tapped).
    func applyPending() {
        guard var cur = current, let p = pending else { return }
        generation += 1
        // (A page that was loading for the old list is dropped, so clear its spinner.)
        cur.posts = p
        cur.after = pendingAfter
        cur.hasPending = false
        cur.loadingMore = false
        ui = .data(cur)
        pending = nil
        pendingAfter = nil
    }

    func loadMore() {
        guard var cur = current, cur.hasMore, !cur.loadingMore else { return }
        // Paging off a cached page would be overwritten by the fresh one.
        if showingCache { return }
        let gen = generation
        let after = cur.after
        cur.loadingMore = true
        ui = .data(cur)
        moreJob = Task { [self] in
            // A restored page (no cursor): fetch a first page and continue
            // from it, skipping posts already shown.
            let restored = after == restoredPage
            do {
                let listing = try await fetch(after: restored ? nil : after)
                guard gen == generation else { return } // the list was replaced meanwhile
                // Append to the latest state, which may carry a staged "New posts" page.
                var latest = current ?? cur
                let shown = restored ? Set(latest.posts.map(\.id)) : []
                latest.posts += restored ? listing.items.filter { !shown.contains($0.id) } : listing.items
                latest.after = listing.after
                latest.loadingMore = false
                ui = .data(latest)
            } catch {
                guard gen == generation else { return }
                var latest = current ?? cur
                latest.loadingMore = false
                ui = .data(latest)
            }
        }
    }
}
