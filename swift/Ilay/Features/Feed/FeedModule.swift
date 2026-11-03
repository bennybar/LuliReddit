import Foundation
import Observation

/// Feed/home singletons: one `FeedController` per feed key (the frontpage lives for the
/// whole session; other feeds are kept in a small LRU so going back repaints
/// instantly) and the custom-feed list shared by the Explore and You tabs. Tab
/// re-select signals live on `AppNavigator`.
@MainActor @Observable final class FeedModule: UserScoped {
    private static let maxFeeds = 12

    @ObservationIgnored private let c: AppContainer
    @ObservationIgnored private var frontpage: FeedController?
    // Dropped from the cache but not disposed: a screen deeper in the back stack may
    // still hold it, and a disposed (cancelled) one would leave that screen stuck
    // loading. It's freed once unused.
    @ObservationIgnored private var feeds: [String: FeedController] = [:]
    @ObservationIgnored private var feedOrder: [String] = [] // Least recently used first.

    /// The For You / Reddit Home engines; nil until that module plugs in.
    @ObservationIgnored var engines: FeedEngines?

    /// Bumped on account change: screens re-fetch their controller.
    private(set) var version = 0

    init(_ c: AppContainer) { self.c = c }

    /// The controller for `key` ('' = frontpage, subreddit name, or `m::user::name`).
    func controller(_ key: String) -> FeedController {
        if key.isEmpty {
            if let frontpage { return frontpage }
            let new = FeedController(key: "")
            frontpage = new
            return new
        }
        feedOrder.removeAll { $0 == key }
        feedOrder.append(key)
        if let existing = feeds[key] { return existing }
        let new = FeedController(key: key)
        feeds[key] = new
        if feedOrder.count > Self.maxFeeds { feeds[feedOrder.removeFirst()] = nil }
        return new
    }

    // MARK: Custom feeds (multireddits)

    private(set) var multireddits: Async<[Multireddit]> = .loading
    @ObservationIgnored private var multisJob: Task<Void, Never>?
    @ObservationIgnored private var multisLoading = false
    @ObservationIgnored private var multisLoaded = false

    /// Loads the user's custom feeds once (or again with `force`).
    func loadMultireddits(force: Bool = false) {
        if !force && (multisLoaded || multisLoading) { return }
        multisJob?.cancel()
        multisLoading = true
        multisJob = Task { [self] in
            if case .error = multireddits { multireddits = .loading }
            do {
                let list = try await c.repository.getMyMultireddits()
                if Task.isCancelled { return }
                multireddits = .data(list)
                multisLoaded = true
            } catch {
                if Task.isCancelled { return }
                multireddits = .error(error)
            }
            multisLoading = false
        }
    }

    /// Your own profile, for the avatars in the top bar and side bar.
    private(set) var me: RedditUser?
    @ObservationIgnored private var meJob: Task<Void, Never>?

    /// Fetches `me` the first time something shows it, once per account.
    func loadMe() {
        guard let session = c.session.session, !session.anonymous else { return }
        if me != nil || meJob != nil { return }
        meJob = Task { [self] in
            let user = try? await c.repository.getUserAbout(session.username)
            if Task.isCancelled { return }
            me = user
            meJob = nil
        }
    }

    func onUserChanged(_ username: String) {
        meJob?.cancel()
        meJob = nil
        me = nil
        frontpage?.dispose()
        frontpage = nil
        feeds.values.forEach { $0.dispose() }
        feeds.removeAll()
        feedOrder.removeAll()
        multisJob?.cancel()
        multisLoading = false
        multisLoaded = false
        multireddits = .loading
        version += 1
    }
}
