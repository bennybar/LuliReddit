import SwiftUI
import UserNotifications

/// Prefs flag: have we shown the one-time notifications suggestion?
private let notifPromptedPref = "notifyInboxPrompted"

private struct NavItem {
    let systemImage: String
    let label: String
}

private let navItems = [
    NavItem(systemImage: "house", label: "Posts"),
    NavItem(systemImage: "safari", label: "Explore"),
    NavItem(systemImage: "envelope", label: "Inbox"),
    NavItem(systemImage: "person.crop.circle", label: "Profile"),
]

/// Each tab's root, one line per tab: a feature swaps its screen in here.
private struct TabRoot: View {
    let index: Int

    var body: some View {
        switch index {
        case 0: FrontpageTab()
        case 1: ExploreTab()
        case 2: InboxScreen()
        default: ProfileTab()
        }
    }
}

/// The home shell: Posts / Explore / Inbox / Profile tabs, each with its own
/// `NavigationStack`, and the side bar. SwiftUI keeps every opened tab alive (state,
/// scroll position, running tasks) like Flutter's IndexedStack.
struct HomeScreen: View {
    /// How far the side bar is out, 0...1. Above 0 it's in the view tree.
    @State private var drawer: CGFloat = 0
    @State private var lastExploreTap = Date.distantPast
    @State private var startupChecksDone = false

    private let drawerWidth: CGFloat = 300

    var body: some View {
        @Bindable var nav = app.navigator
        // Settings › Navigation: the bottom bar, the side bar, or both.
        let bottomBar = app.settings.value.navStyle != 1
        let sideBar = app.settings.value.navStyle != 0
        // No drawer over a pushed screen: the edge swipe is that stack's Back there.
        let atRoot = nav.paths[nav.selectedTab].isEmpty

        ZStack(alignment: .leading) {
            TabView(selection: Binding(get: { nav.selectedTab }, set: selectTab)) {
                ForEach(navItems.indices, id: \.self) { i in
                    Tab(navItems[i].label, systemImage: navItems[i].systemImage, value: i) {
                        NavigationStack(path: $nav.paths[i]) {
                            TabRoot(index: i)
                                .navigationDestination(for: Route.self) { RouteView(route: $0) }
                        }
                        .modifier(HidesTabBar(hidden: !bottomBar))
                    }
                    .badge(i == 2 ? unread : 0)
                }
            }
            .tabBarMinimizeBehavior(.onScrollDown)
            .environment(\.sideBar, sideBar ? { openDrawer() } : nil)
            .gesture(EdgePan(enabled: sideBar && atRoot && drawer == 0, width: drawerWidth) { progress in
                drawer = progress
            } onEnd: { progress, velocity in
                settleDrawer(open: velocity > 300 || (velocity > -300 && progress > 0.5))
            })

            if drawer > 0 {
                Color.black.opacity(0.4 * drawer)
                    .ignoresSafeArea()
                    .onTapGesture { settleDrawer(open: false) }
                    .accessibilityLabel("Close menu")
                    .accessibilityAddTraits(.isButton)
                SideBar(selected: nav.selectedTab, unread: unread, onTab: selectTab) { pick in
                    settleDrawer(open: false)
                    pick()
                }
                .frame(width: drawerWidth)
                .offset(x: -drawerWidth * (1 - drawer))
                .simultaneousGesture(
                    DragGesture(minimumDistance: 20)
                        .onChanged { value in
                            // Sideways only: up and down belongs to its list.
                            guard abs(value.translation.width) > abs(value.translation.height), value.translation.width < 0 else { return }
                            drawer = 1 + value.translation.width / drawerWidth
                        }
                        .onEnded { value in
                            settleDrawer(open: drawer > 0.5 && value.predictedEndTranslation.width > -drawerWidth / 2)
                        }
                )
                .transition(.identity)
            }
        }
        // Snackbars float above the tab bar while the shell is showing.
        .onChange(of: bottomBar, initial: true) { nav.snackbar.bottomPadding = bottomBar ? 56 : 0 }
        .onDisappear { nav.snackbar.bottomPadding = 0 }
        // Each time the home shell is created (app start, after signing in again):
        // What's new, then the one-time notifications suggestion. @State, so
        // coming back to it doesn't re-run it. (The GitHub update check is
        // Android-only: its releases are APKs. Settings → Check for updates remains.)
        .task {
            if startupChecksDone { return }
            startupChecksDone = true
            await maybeShowWhatsNew()
            await maybeSuggestNotifications()
        }
    }

    /// The Inbox tab's badge.
    private var unread: Int { app.inbox.unreadCount }

    private func selectTab(_ i: Int) {
        let nav = app.navigator
        // Double-tapping Explore opens search, keyboard up.
        let now = Date()
        if i == 1 && now.timeIntervalSince(lastExploreTap) < 0.4 {
            lastExploreTap = .distantPast
            nav.selectedTab = 1
            nav.push(.search())
            return
        }
        if i == 1 { lastExploreTap = now }
        // Re-tapping the active tab: back to its root, the system's way; already
        // there, scrolls it to top (Posts also refreshes).
        if i == nav.selectedTab {
            if !nav.paths[i].isEmpty {
                nav.paths[i].removeAll()
            } else if i == 0 {
                nav.frontpageScrollSignal += 1
            } else {
                nav.tabReselect[i] += 1
            }
        } else {
            nav.selectedTab = i
        }
    }

    private func openDrawer() {
        settleDrawer(open: true)
    }

    private func settleDrawer(open: Bool) {
        withAnimation(.spring(duration: 0.3, bounce: 0)) { drawer = open ? 1 : 0 }
    }
}

/// Nothing at all when not hiding: an explicit `.automatic` out here would override the
/// `.hidden` of a pushed screen (a thread, a composer).
private struct HidesTabBar: ViewModifier {
    let hidden: Bool

    func body(content: Content) -> some View {
        if hidden { content.toolbar(.hidden, for: .tabBar) } else { content }
    }
}

/// The screen-edge swipe that brings out the side bar. A real edge recognizer, so
/// nothing sits over the content: taps and scrolling there are untouched.
private struct EdgePan: UIGestureRecognizerRepresentable {
    let enabled: Bool
    let width: CGFloat
    let onChange: (CGFloat) -> Void
    let onEnd: (_ progress: CGFloat, _ velocity: CGFloat) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIScreenEdgePanGestureRecognizer {
        let recognizer = UIScreenEdgePanGestureRecognizer()
        recognizer.edges = .left
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UIScreenEdgePanGestureRecognizer, context: Context) {
        // Not while it's tracking: this very gesture is what moves the drawer off 0.
        if recognizer.state == .possible { recognizer.isEnabled = enabled }
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIScreenEdgePanGestureRecognizer, context: Context) {
        let x = recognizer.translation(in: recognizer.view).x
        let progress = min(max(x / width, 0), 1)
        switch recognizer.state {
        case .began, .changed: onChange(progress)
        case .ended, .cancelled: onEnd(progress, recognizer.velocity(in: recognizer.view).x)
        default: break
        }
    }
}

/// The side bar (Settings › Navigation): the four tabs, then your stuff and
/// Settings. `onPick` closes it, then runs the choice.
private struct SideBar: View {
    let selected: Int
    let unread: Int
    let onTab: (Int) -> Void
    let onPick: (@escaping () -> Void) -> Void

    var body: some View {
        let session = app.session.session
        let me = app.feed.me
        let anonymous = session?.anonymous != false
        let username = anonymous ? nil : session?.username
        // The Explore tab's list, so these cost no requests of their own.
        let subs = SubscriptionsViewModel.shared.subs.value ?? []
        let favorites = subs.filter(\.userHasFavorited)
        let recent = app.recentSubreddits.state.map { $0.asSubreddit() }

        List {
            Section {
                if let username {
                    // Stands in for the Profile row (#64).
                    Button { onPick { onTab(3) } } label: {
                        // Your name and karma beside your picture, a size up (#167).
                        HStack(spacing: 14) {
                            LetterAvatar(name: username, size: 64, imageUrl: me?.iconUrl)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.settings.value.sideBarUserPrefix ? "u/\(username)" : username)
                                    .font(.title3.bold()).foregroundStyle(.primary).lineLimit(1)
                                if let me {
                                    Text("\(compactNumber(me.linkKarma + me.commentKarma)) karma")
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .listRowBackground(selected == 3 ? Color.accentColor.opacity(0.15) : nil)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ilay").font(.title2.bold())
                        Text("Browsing without an account").foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
                ForEach(navItems.indices, id: \.self) { i in
                    if i != 3 || username == nil {
                        Button { onPick { onTab(i) } } label: {
                            Label(navItems[i].label, systemImage: navItems[i].systemImage)
                                .foregroundStyle(.primary)
                        }
                        .badge(i == 2 ? unread : 0)
                        .listRowBackground(i == selected ? Color.accentColor.opacity(0.15) : nil)
                    }
                }
            }
            Section {
                if !anonymous {
                    moreRow("bookmark", "Saved", .saved)
                    moreRow("rectangle.stack", "Custom feeds", .customFeeds)
                }
                moreRow("clock.arrow.circlepath", "History", .history)
                moreRow("arrow.down.circle", "Read later", .offline)
                moreRow("square.and.pencil", "Drafts", .drafts)
                moreRow("gearshape", "Settings", .settings)
            }
            if app.settings.value.showRecentlyVisited {
                SideBarSubs(
                    title: "Recently visited", subs: recent, onPick: onPick,
                    empty: app.settings.value.trackHistory ? "Subreddits you open will show here" : nil,
                    visits: app.recentSubreddits.state.map(\.visits),
                    onRemove: { app.recentSubreddits.remove($0.name) }
                )
            }
            SideBarSubs(title: "Favorites", subs: favorites, onPick: onPick)
        }
        .listStyle(.insetGrouped)
        .background(Color(.systemGroupedBackground))
        .scrollContentBackground(.hidden)
        .task {
            SubscriptionsViewModel.shared.loadIfNeeded()
            // Your avatar and karma: one request, the first time something shows them.
            app.feed.loadMe()
        }
    }

    private func moreRow(_ systemImage: String, _ label: String, _ route: Route) -> some View {
        Button { onPick { app.navigator.push(route) } } label: {
            Label(label, systemImage: systemImage).foregroundStyle(.primary)
        }
    }
}

/// A titled list of subreddits in the side bar (#63); when it has none, `empty`, or nothing.
private struct SideBarSubs: View {
    let title: String
    let subs: [Subreddit]
    let onPick: (@escaping () -> Void) -> Void
    var empty: String? = nil
    var visits: [Int]? = nil
    /// Long-press: remove it from the list (Recently visited, #123).
    var onRemove: ((Subreddit) -> Void)? = nil

    var body: some View {
        if !subs.isEmpty || empty != nil {
            Section(title) {
                if subs.isEmpty {
                    Text(empty ?? "").foregroundStyle(.secondary)
                }
                ForEach(Array(subs.enumerated()), id: \.element.name) { i, sub in
                    Button {
                        // A followed user is a subscription to their profile, u_<name>.
                        onPick {
                            if sub.name.hasPrefix("u_") {
                                app.navigator.openUser(String(sub.name.dropFirst(2)))
                            } else {
                                app.navigator.openSubreddit(sub.name)
                            }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            LetterAvatar(name: sub.name, size: 28, imageUrl: sub.iconUrl)
                            Text(sub.namePrefixed).lineLimit(1).foregroundStyle(.primary)
                        }
                    }
                    // Recently visited: how often you opened it (#92).
                    .badge(visits.map { i < $0.count ? $0[i] : 0 } ?? 0)
                    .contextMenu {
                        if let onRemove {
                            Button("Remove from \(title)", systemImage: "minus.circle", role: .destructive) { onRemove(sub) }
                        }
                    }
                }
            }
        }
    }
}

/// One-time, opt-in suggestion to enable inbox notifications (shown on an early app
/// open). Declining or enabling both mark it as handled so we never nag again: it
/// stays fully controllable in Settings either way.
@MainActor private func maybeSuggestNotifications() async {
    let prefs = app.prefs
    if prefs.getBool(notifPromptedPref) == true { return }
    if app.settings.value.notifyInbox { return }
    prefs.setBool(notifPromptedPref, true)
    let enable = await Overlays.alert(
        "Get notified of replies?",
        message: "Ilay can check your Reddit inbox in the background (about every 15 minutes) and notify you of replies, mentions and messages.\n\n"
            + "It uses simple polling — no Firebase or tracking. You can change this anytime in Settings.",
        buttons: [(title: "Not now", role: .cancel, value: false), (title: "Enable", role: nil, value: true)]
    )
    if enable != true { return }
    if !(await app.inbox.requestPermission()) { return }
    app.settings.setNotifyInbox(true)
    // Prime: no notification for what's already unread.
    _ = await app.inbox.pollInbox(notify: false)
    app.inbox.registerPolling()
}
