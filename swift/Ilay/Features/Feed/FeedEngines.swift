import SwiftUI

/// What the Home status strip says about the Reddit Home page on show.
enum HomeStatus: Equatable, Sendable {
    /// Your live Reddit Home, loaded at `at`.
    case live(at: Int)
    /// The Home page saved at `at`: back after iOS closed Ilay, or Home couldn't load.
    case saved(at: Int)
    /// For You instead, because Home couldn't load; `signedOut`: the website sign-in expired.
    case fellBack(signedOut: Bool)
}

/// What Blend's Reddit Home source is contributing right now.
enum BlendState: Equatable, Sendable {
    case loading
    case included(count: Int)
    case unavailable(signedOut: Bool)
}

/// The For You learner, as the feed uses it: every signal a card or a swipe sends.
/// (Kotlin's `app.forYou.learner`.)
@MainActor protocol FeedLearner: AnyObject {
    func vote(_ post: Post, from: Int, to: Int)
    func save(_ post: Post, saved: Bool)
    func open(_ post: Post)
    func viewMedia(_ post: Post)
    func share(_ post: Post)
    func impression(_ post: Post)
    func dismiss(_ post: Post, undo: Bool)
    func hideSubreddit(_ post: Post, undo: Bool)
    func filterOutSubreddit(_ post: Post, undo: Bool)
}

/// The narrow interface between the feed and the For You / Reddit Home engines.
/// `ForYouModule` implements it and plugs in with one line: `app.feed.engines = app.forYou`.
/// Until then (nil) the frontpage is the plain Reddit listing, without the For You,
/// Blend and Home chips. The implementation should be `@Observable`: `homeStatus` and
/// `blendState` are read from SwiftUI.
@MainActor protocol FeedEngines: AnyObject {
    var learner: FeedLearner { get }

    func forYouPage(after: String?, loaded: [Post]) async throws -> Listing<Post>
    func forYouCachedFirstPage() async throws -> Listing<Post>?
    func forYouCachedFirstPageTime() async throws -> Int?

    func homePage(after: String?, loaded: [Post]) async throws -> Listing<Post>
    func homeCachedFirstPage() async throws -> Listing<Post>?
    func homeCachedFirstPageTime() async throws -> Int?

    var homeStatus: HomeStatus? { get set }
    var blendState: BlendState? { get }
    /// Reddit Home deals its cards straight from the page; the full posts (media,
    /// video, NSFW…) arrive moments later: call this and they replace them in place.
    var onHomeUpgrades: (([Post]) -> Void)? { get set }
    /// The card on screen, for the hidden reddit.com page to follow (Reddit's own "seen").
    func homeViewing(_ postId: String)
    func disposeHome()

    /// The shuffling deck with its live count of posts found, shown while Home / For You load.
    func loadingDeck(forYou: Bool) -> AnyView
    /// "Why you're seeing this" and explicit More / Less.
    func showTuneSheet(_ post: Post)
}
