import SafariServices
import SwiftUI

/// App-wide navigation + feedback: routes, links (media in the viewer, reddit.com
/// in the app, everything else in the browser), sharing and snackbars. Available
/// as `@Environment(AppNavigator.self)` in views and as `app.navigator` elsewhere.
@MainActor @Observable final class AppNavigator {
    static let shared = AppNavigator()

    /// The selected tab: 0 Posts, 1 Explore, 2 Inbox, 3 Profile.
    var selectedTab = 0
    /// Each tab's `NavigationStack` path.
    var paths: [[Route]] = [[], [], [], []]
    /// The stack shown instead of the tabs while signed out (Login, website sign-in).
    var loginPath: [Route] = []
    /// Whether the tabs are on screen, rather than the login stack (set by `AppRoot`).
    var showingHome = true
    /// This launch restored the app after the system ended it in the background (not
    /// a fresh launch): feeds show their saved page if it's still fresh rather than
    /// loading anew. The frontpage takes it, once. (Kotlin's `app.restoredProcess`.)
    var restoredProcess = false

    /// Full-screen media viewers, drawn over the current screen (see `AppRoot`).
    let viewers = ViewerStack()
    let snackbar = ToastCenter()

    /// Bumped to ask the frontpage feed to scroll to top (or refresh if already
    /// there): the Posts tab tapped while already selected.
    var frontpageScrollSignal = 0
    /// Bumped when a tab is re-tapped while already active, so that tab's list can
    /// scroll to top. Per tab index. (The Posts tab uses `frontpageScrollSignal`,
    /// which also refreshes when already at the top.)
    var tabReselect = [0, 0, 0, 0]

    private init() {}

    /// Opens a screen on the current stack; an open media viewer would hide it, so it's closed first.
    func push(_ route: Route) {
        viewers.clear()
        // Search instead fades in over the page (#77): the stack's own push only slides.
        if case .search = route, showingHome, let window = topViewController()?.view.window {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.2
            window.layer.add(fade, forKey: "searchFade")
            var quiet = Transaction()
            quiet.disablesAnimations = true
            withTransaction(quiet) { paths[selectedTab].append(route) }
            return
        }
        if showingHome { paths[selectedTab].append(route) } else { loginPath.append(route) }
    }

    /// Pops the current stack; false when already at its root.
    @discardableResult func pop() -> Bool {
        if showingHome {
            guard !paths[selectedTab].isEmpty else { return false }
            paths[selectedTab].removeLast()
        } else {
            guard !loginPath.isEmpty else { return false }
            loginPath.removeLast()
        }
        return true
    }

    /// Clears every stack (login ↔ home). `AppRoot` shows the login stack or the
    /// tabs from the session state; `route` only matters when it's more than those.
    func resetTo(_ route: Route) {
        viewers.clear()
        paths = [[], [], [], []]
        selectedTab = 0
        loginPath = []
        switch route {
        case .home, .login: break
        default: push(route)
        }
    }

    /// Closes the top media viewer (fading out over the screen beneath).
    @discardableResult func closeViewer() -> Bool { viewers.closeTop() }

    /// Opens a post's thread; the already-loaded `post` paints instantly.
    func openPost(_ post: Post, focusCommentId: String? = nil) {
        NavCache.put(post.id, post)
        push(.post(subreddit: post.subreddit.isEmpty ? "_" : post.subreddit, postId: post.id, focusCommentId: focusCommentId))
    }

    func openSubreddit(_ name: String) { push(.subreddit(name: name)) }
    func openUser(_ username: String) { push(.user(username: username)) }

    func openImage(_ url: String, title: String? = nil) { viewers.open(.image(url: url, title: title)) }

    func openGallery(_ images: [GalleryImage], title: String? = nil, initialIndex: Int = 0) {
        if images.isEmpty { return }
        viewers.open(.gallery(
            urls: images.map(\.url),
            widths: images.map { $0.width ?? 0 },
            heights: images.map { $0.height ?? 0 },
            title: title,
            initialIndex: initialIndex
        ))
    }

    func openVideo(_ url: String, title: String? = nil, downloadUrl: String? = nil, externalUrl: String? = nil, gif: Bool = false) {
        viewers.open(.video(url: url, title: title, downloadUrl: downloadUrl, externalUrl: externalUrl, gif: gif))
    }

    /// Opens a video post full-screen (resolving RedGifs to its HD file first).
    func openPostVideo(_ post: Post) {
        Task { await Ilay.openPostVideo(self, post) }
    }

    /// A relative link (`/r/foo`, `/u/bar`, plain `r/foo`) as a reddit.com one.
    static func absoluteLink(_ href: String) -> String {
        let raw = href.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("/") { return "https://www.reddit.com\(raw)" }
        if raw.hasPrefix("r/") || raw.hasPrefix("u/") || raw.hasPrefix("user/") { return "https://www.reddit.com/\(raw)" }
        return raw
    }

    /// Opens a link from Reddit content the way a Reddit client should: media in
    /// the viewer, reddit.com links in the app, anything else in the browser.
    func openLink(_ href: String?) {
        guard let href, !href.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let raw = Self.absoluteLink(href)
        guard let uri = URL(string: raw) else { return }
        if isShareLink(uri) {
            Task {
                if let resolved = await resolveShareLink(uri) {
                    openLink(resolved.absoluteString)
                } else {
                    openInBrowser(uri)
                }
            }
            return
        }
        if isVideoUrl(uri) {
            openVideo(resolveVideoUrl(raw), externalUrl: raw)
        } else if isImageUrl(uri) {
            openImage(raw)
        } else if let route = routeForRedditUrl(uri) {
            push(route)
        } else {
            openInBrowser(uri)
        }
    }

    /// A browser: in-app Safari when enabled in Settings, else the default browser app.
    func openInBrowser(_ uri: URL) {
        // SFSafariViewController takes only http(s), and raises on anything else.
        if app.settings.value.inAppBrowser, ["http", "https"].contains(uri.scheme?.lowercased()), let top = topViewController() {
            top.present(SFSafariViewController(url: uri), animated: true)
        } else {
            UIApplication.shared.open(uri) { [self] opened in
                if !opened { showSnackbar("No app can open this link.") }
            }
        }
    }

    func openInBrowser(_ url: String) {
        if let uri = URL(string: url) { openInBrowser(uri) }
    }

    /// Opens `url` in the app that handles it (YouTube for a YouTube link), else the browser.
    func openExternal(_ url: String) {
        guard let uri = URL(string: url) else { return }
        UIApplication.shared.open(uri, options: [.universalLinksOnly: true]) { [self] opened in
            if !opened { openInBrowser(uri) }
        }
    }

    /// The system share sheet for `text` (a URL, or "Title\nURL").
    func share(_ text: String, subject: String? = nil) {
        guard let top = topViewController() else { return }
        let sheet = UIActivityViewController(activityItems: [ShareText(text: text, subject: subject)], applicationActivities: nil)
        // On an iPad-sized sheet this would need an anchor; the app is iPhone only (project.yml).
        top.present(sheet, animated: true)
    }

    /// Shares a post as `Title` followed by the link, so recipients see what it is.
    func shareWithTitle(_ url: String, _ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        share(trimmed.isEmpty ? url : "\(trimmed)\n\(url)", subject: title)
    }

    func showSnackbar(_ message: String, actionLabel: String? = nil, duration: SnackbarDuration = .short, onAction: (() -> Void)? = nil) {
        snackbar.show(message, actionLabel: actionLabel, duration: duration, onAction: onAction)
    }

    /// A quick action (vote, save, subscribe…) didn't go through; its optimistic UI was rolled back.
    func showActionError(_ action: String, _ error: Error) {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        let anonymous = app.session.session?.anonymous == true
        showSnackbar(anonymous
            ? "Sign in to \(action) — you're browsing without an account."
            : "Couldn't \(action): \(friendlyError(error))")
    }

    /// What to present from, so a share sheet or Safari also opens over a sheet.
    private func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

/// Share-sheet text with a subject (the mail app's subject line).
private final class ShareText: NSObject, UIActivityItemSource {
    let text: String
    let subject: String?

    init(text: String, subject: String?) {
        self.text = text
        self.subject = subject
    }

    func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any { text }
    func activityViewController(_ controller: UIActivityViewController, itemForActivityType type: UIActivity.ActivityType?) -> Any? { text }
    func activityViewController(_ controller: UIActivityViewController, subjectForActivityType type: UIActivity.ActivityType?) -> String { subject ?? "" }
}

extension AppContainer {
    var navigator: AppNavigator { AppNavigator.shared }
}
