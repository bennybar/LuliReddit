import SwiftUI

@main
struct IlayApp: App {
    @UIApplicationDelegateAdaptor(IlayAppDelegate.self) private var appDelegate

    init() {
        // Hosted unit tests start the app too: they must not read the real login.
        guard !isRunningTests else { return }
        app.start()
        app.session.reload()
        app.inbox.onAppStart()
        SharedHandover.start()
    }

    var body: some Scene {
        WindowGroup {
            if !isRunningTests {
                AppRoot()
            }
        }
    }
}

/// The Home Screen's long-press menu (#317): Home, then the subreddits you open most.
/// AppRoot opens the chosen one.
@MainActor @Observable
final class QuickActions {
    static let shared = QuickActions()
    static let homeURL = URL(string: "ilay-shortcut://home")!
    private static let subreddits = 3 // with Home, the 4 the menu shows

    /// The chosen action's link (Home's, or the subreddit's), until AppRoot opens it.
    var pending: URL?
    @ObservationIgnored private var published: [String]?

    /// Rebuilds the menu when the most visited subreddits change.
    func update(_ mostVisited: [RecentSubreddit]) {
        guard !isRunningTests else { return }
        let names = mostVisited.prefix(Self.subreddits).map(\.name)
        if names == published { return }
        published = names
        let home = UIApplicationShortcutItem(
            type: "home", localizedTitle: "Home", localizedSubtitle: nil,
            icon: UIApplicationShortcutIcon(systemImageName: "house"), userInfo: nil
        )
        UIApplication.shared.shortcutItems = [home] + names.map { name in
            UIApplicationShortcutItem(
                type: "subreddit", localizedTitle: "r/\(name)", localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "bubble.left.and.bubble.right"),
                userInfo: ["name": name as NSString]
            )
        }
    }

    func perform(_ item: UIApplicationShortcutItem) {
        if item.type == "subreddit", let name = item.userInfo?["name"] as? String {
            pending = URL(string: "https://www.reddit.com/r/\(name)")
        } else {
            pending = Self.homeURL
        }
    }
}

/// Hands the Home Screen's quick actions to [QuickActions]: at launch, and while running.
final class IlayAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let item = options.shortcutItem { QuickActions.shared.perform(item) }
        let config = UISceneConfiguration(name: nil, sessionRole: session.role)
        config.delegateClass = QuickActionSceneDelegate.self
        return config
    }
}

final class QuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        QuickActions.shared.perform(shortcutItem)
        completionHandler(true)
    }
}
