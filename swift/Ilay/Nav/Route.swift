import Foundation

/// Every screen. Codable: the tab stacks are saved as JSON. Objects that can't
/// travel in a route (a Post, an InboxItem) go through [NavCache] and the route
/// carries their id.
enum Route: Hashable, Codable, Sendable {
    case login
    /// Website-session sign-in. [clearFirst] wipes existing cookies so you can sign into a *different* account (add account).
    case webLogin(clearFirst: Bool = false)
    case home
    case settings
    case settingsSection(title: String)
    case manageForYou
    case exploreSections
    case contentFilters
    case policy
    case history
    case summaries
    case saved
    case offline
    case notificationActivity
    case drafts
    case whatsNew
    case customFeeds
    /// A reddit.com page signed in as you (website sign-in): notifications, chat, a poll, Reddit's settings.
    case redditWeb(url: String, title: String)
    case search(subreddit: String? = nil, query: String? = nil, sort: String? = nil, time: String? = nil)
    case submit(subreddit: String? = nil)
    /// A private-message thread; the root InboxItem is in [NavCache] under [fullname].
    case messageThread(fullname: String)
    case composeMessage(to: String? = nil)
    case subreddit(name: String)
    /// The frontpage as a pushed page (Explore's All button, with the Posts tab on r/all).
    case frontpage
    case user(username: String)
    case multireddit(username: String, name: String)
    case manageMultireddit(username: String, name: String)
    /// A post + comments. The already-loaded Post (if any) is in [NavCache] under [postId].
    case post(subreddit: String, postId: String, focusCommentId: String? = nil)
}

/// Hands objects (posts, inbox items) to the next screen. Least recently used goes past 200.
enum NavCache {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var map = OrderedMap<Any>()

    static func put(_ key: String, _ value: Any) {
        lock.withLock {
            map.removeValue(forKey: key)
            map[key] = value
            if map.count > 200 { map.removeFirst() }
        }
    }

    static func get<T>(_ key: String) -> T? {
        lock.withLock {
            guard let v = map.removeValue(forKey: key) else { return nil }
            map[key] = v
            return v as? T
        }
    }
}

/// A link shared to Ilay from another app by the share extension,
/// `luli://share?url=<reddit link>[&summarize=1]`: the link, and whether
/// "Summarize with Ilay" (rather than "Open in Ilay") was picked.
func sharedLink(_ uri: URL) -> (url: URL, summarize: Bool)? {
    // The Debug build's own scheme is ilayswift (project.yml).
    guard uri.scheme == "luli" || uri.scheme == "ilayswift", uri.host == "share" else { return nil }
    let query = URLComponents(url: uri, resolvingAgainstBaseURL: false)?.queryItems ?? []
    guard let url = query.first(where: { $0.name == "url" })?.value.flatMap(URL.init(string:)), isRedditHost(url.host) else { return nil }
    return (url, query.first { $0.name == "summarize" }?.value == "1")
}

/// A post shared to "Summarize with Ilay": its summary opens once the thread
/// loads. The post screen takes it (and clears it) when its id matches.
@MainActor var summarizeOnOpen: String?
