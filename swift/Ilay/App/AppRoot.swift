import SwiftUI

/// Once per process (`AppRoot` can be created again).
private var appStartTracked = false
private var frontpagePrestarted = false

/// Login or the tabs, by the session, with the media viewers and sheets above them.
struct AppRoot: View {
    @Environment(\.scenePhase) private var scenePhase
    /// The latest incoming deep link, consumed once the tabs show.
    @State private var pendingLink: (url: URL, summarize: Bool)?
    @State private var lastLink: String?
    @State private var lastLinkAt = Date.distantPast
    @State private var lastInboxSync = Date()
    /// A fresh install shows the setup before sign-in (#114).
    @State private var setup = needsSetup()

    var body: some View {
        @Bindable var nav = app.navigator
        let state = app.session.state
        // A transient keychain read failure can momentarily read as logged out;
        // don't bounce a known account to the login screen.
        let showHome = { if case .loggedIn = state { true } else { app.session.hasAccount } }()
        ZStack {
            if state == .loading {
                Color(.systemBackground).ignoresSafeArea()
            } else if showHome {
                HomeScreen()
            } else if setup {
                SetupScreen { setup = false }
            } else {
                NavigationStack(path: $nav.loginPath) {
                    RouteView(route: .login)
                        .navigationDestination(for: Route.self) { RouteView(route: $0) }
                }
            }
            // Media viewers present themselves above everything; this only keeps them in step.
            MediaViewerHost(stack: nav.viewers)
        }
        .modifier(OverlayHost())
        .modifier(ShellRestoration())
        .environment(nav)
        .ilayTheme()
        .onChange(of: showHome, initial: true) { old, new in
            nav.showingHome = new
            // Someone who already has an account never sees the setup, even after signing out.
            if new, setup {
                app.prefs.setBool(setupDoneKey, true)
                setup = false
            }
            if old != new { nav.resetTo(new ? .home : .login) }
        }
        .onChange(of: showHome && pendingLink != nil) { if showHome { openPendingLink() } }
        .onOpenURL { handleLink($0) }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active: onResume()
            case .background:
                Analytics.flushPostsOpened()
                app.forYou.redditHome.onAppBackground()
                if app.settings.value.notifyInbox { app.inbox.registerPolling() }
            default: break
            }
        }
        .onChange(of: app.loadedIdentity) { importSharedSummaries() }
        .task {
            trackAppStarted()
            await prestartFrontpage()
        }
    }

    /// Anonymous: which login method this install uses.
    private func trackAppStarted() {
        if appStartTracked { return }
        appStartTracked = true
        Task {
            let username = await app.secureStore.username()
            let method = (username ?? "").isEmpty ? "logged_out" : await app.secureStore.authMode() == "web" ? "website" : "api"
            // Which frontpage feed this install uses (and whether Reddit Home is
            // allowed at all), to see how many actually use Home.
            let s = app.settings.value
            let feed = s.postsTabAll ? "all"
                : s.redditHomeAllowed && s.redditHomeFeed ? "home"
                : s.forYouFeed && s.blendHome && s.redditHomeAllowed ? "blend"
                : s.forYouFeed ? "for_you" : "frontpage"
            Analytics.track("app_started", ["login_method": .string(method), "feed": .string(feed), "home_allowed": .bool(s.redditHomeAllowed)])
        }
    }

    /// Starts loading the frontpage (For You's sources, or Reddit Home's hidden browser)
    /// as soon as the stored session is read, instead of when Home first appears.
    private func prestartFrontpage() async {
        if frontpagePrestarted { return }
        frontpagePrestarted = true
        // After the account's stores are loaded: that also resets the feeds.
        for await _ in Observations({ app.loadedIdentity }) {
            guard case let .loggedIn(session) = app.session.state, app.loadedIdentity == session.identity else {
                if app.session.state == .loggedOut { return }
                continue
            }
            app.feed.controller(app.settings.value.postsTabKey).start()
            return
        }
    }

    private func onResume() {
        // Re-read the keychain to restore auth after background/resume.
        app.session.reload()
        app.forYou.redditHome.onAppForeground()
        // Re-sync the inbox (items read elsewhere show as read), at most every 2 minutes.
        if Date().timeIntervalSince(lastInboxSync) > 120 {
            lastInboxSync = Date()
            app.inbox.onAppResumed()
        }
        importSharedSummaries()
    }

    /// Not before the account's store is loaded: it would drop them when that happens.
    private func importSharedSummaries() {
        if let session = app.session.session, app.loadedIdentity == session.identity { SharedHandover.importSummaries() }
    }

    private func handleLink(_ uri: URL) {
        // "Ilay" in another app's share sheet (open, or summarize), or a reddit link.
        let incoming: (url: URL, summarize: Bool)
        if let shared = sharedLink(uri) {
            incoming = shared
        } else if isRedditHost(uri.host) {
            incoming = (uri, false)
        } else {
            return // luli://oauth belongs to sign-in.
        }
        // Dedupe: the same link can arrive twice in a row (cold start + resume),
        // but tapping it again later must still open it.
        let now = Date()
        if uri.absoluteString == lastLink && now.timeIntervalSince(lastLinkAt) < 2 { return }
        lastLink = uri.absoluteString
        lastLinkAt = now
        pendingLink = incoming
        if app.navigator.showingHome { openPendingLink() }
    }

    private func openPendingLink() {
        guard let link = pendingLink else { return }
        pendingLink = nil
        let nav = app.navigator
        Task {
            // Share links (/r/<sub>/s/<code>) redirect to the real post first.
            let target = isShareLink(link.url) ? await resolveShareLink(link.url) ?? link.url : link.url
            if isRedditMediaHost(target.host) {
                // i.redd.it / v.redd.it / preview.redd.it: straight into the viewer.
                nav.openLink(target.absoluteString)
            } else if let route = routeForRedditUrl(target) {
                if link.summarize, case let .post(_, postId, _) = route { summarizeOnOpen = postId }
                nav.push(route)
            } else {
                // A reddit page Ilay can't show (wiki, settings…): the browser,
                // keeping whatever was open here.
                nav.openInBrowser(target)
            }
        }
    }
}

/// The open tab, its stacks and viewers survive the system ending the app in the
/// background: `@SceneStorage` keeps them then, and drops them when you swipe the app
/// away, which starts fresh. The same two cases as Android's saved state.
private struct ShellRestoration: ViewModifier {
    private struct Saved: Codable {
        var tab: Int
        var paths: [[Route]]
        var viewers: [MediaViewer]
    }

    @SceneStorage("shell") private var saved = ""
    @State private var restored = false

    private var current: String {
        let nav = app.navigator
        let state = Saved(tab: nav.selectedTab, paths: nav.paths, viewers: nav.viewers.entries.map(\.viewer))
        return (try? JSONEncoder().encode(state)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    func body(content: Content) -> some View {
        content
            .onAppear {
                if restored { return }
                restored = true
                guard let state = try? JSONDecoder().decode(Saved.self, from: Data(saved.utf8)), state.paths.count == 4 else { return }
                let nav = app.navigator
                // Feeds show their saved page if it's still fresh rather than loading anew.
                nav.restoredProcess = true
                nav.selectedTab = state.tab
                nav.paths = state.paths
                nav.viewers.restore(state.viewers)
            }
            .onChange(of: current) { if restored { saved = current } }
    }
}
