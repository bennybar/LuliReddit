import SwiftUI

/// The screen for each route, in one place: a feature adds its screen by replacing
/// its placeholder line here.
struct RouteView: View {
    let route: Route

    var body: some View {
        switch route {
        case .login: LoginScreen()
        case let .webLogin(clearFirst): WebLoginScreen(clearFirst: clearFirst)
        case .home: EmptyView() // The tabs themselves, never pushed.
        case .settings: SettingsScreen()
        case let .settingsSection(title): SettingsScreen(section: title)
        case .manageForYou: ManageForYouScreen()
        case .exploreSections: ExploreSectionsScreen()
        case .contentFilters: ContentFiltersScreen()
        case .policy: PolicyScreen()
        case .whatsNew: WhatsNewScreen()
        case .customFeeds: CustomFeedsScreen()
        case .history: HistoryScreen()
        case .summaries: SummariesScreen()
        case .digest: DigestScreen()
        case .inbox: InboxScreen(pushed: true)
        case .saved: SavedScreen()
        case .offline: OfflineScreen()
        case .notificationActivity: NotificationActivityScreen()
        case .drafts: DraftsScreen()
        case let .redditWeb(url, title): RedditWebScreen(url: url, title: title)
        case let .search(subreddit, query, sort, time):
            SearchScreen(subreddit: subreddit, query: query, sort: sort, time: time).modifier(SearchZoom())
        case let .submit(subreddit): SubmitScreen(subreddit: subreddit)
        case let .messageThread(fullname): MessageThreadScreen(fullname: fullname)
        case let .composeMessage(to): ComposeMessageScreen(to: to)
        case let .subreddit(name): SubredditScreen(name: name)
        case .frontpage: FrontpageScreen()
        case let .user(username): UserScreen(username: username)
        case let .multireddit(username, name): MultiredditScreen(username: username, name: name)
        case let .manageMultireddit(username, name): ManageMultiredditScreen(username: username, name: name)
        case let .post(subreddit, postId, focusCommentId): PostDetailScreen(subreddit: subreddit, postId: postId, focusCommentId: focusCommentId)
        }
    }
}

extension EnvironmentValues {
    /// The namespace the Posts tab's search button and the Search screen share (#271).
    @Entry var searchZoom: Namespace.ID? = nil
}

/// The id a search button gives `matchedTransitionSource` for the Search screen to grow out of.
let searchZoomSource = "search"

/// Search opened from the Posts tab's search button (or a community's, #285) grows out of
/// it and shrinks back into it, as Gmail's does (#271). From anywhere else, it keeps its fade (#77).
private struct SearchZoom: ViewModifier {
    @Environment(\.searchZoom) private var namespace
    /// Decided once, as this screen is pushed (`AppNavigator.push(_:zoom:zoomSource:)`).
    @State private var zoom = app.navigator.zoomsNextSearch
    @State private var source = app.navigator.nextSearchSource

    func body(content: Content) -> some View {
        if zoom, let namespace {
            content.navigationTransition(.zoom(sourceID: source, in: namespace))
        } else {
            content
        }
    }
}

extension View {
    /// The bar's search button labelled `label` as what the Search screen grows out of (#271,
    /// #285). A toolbar item's own `matchedTransitionSource` starts the zoom well off it (below
    /// the button, mid-banner on a community), so a clear stand-in over this page, where the
    /// button is on screen, is the source instead.
    func barZoomSource(_ id: String, in namespace: Namespace.ID, label: String) -> some View {
        modifier(BarZoomSource(id: id, namespace: namespace, label: label))
    }
}

private struct BarZoomSource: ViewModifier {
    let id: String
    let namespace: Namespace.ID
    let label: String

    /// The button, in the window's space.
    @State private var button: CGRect?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topLeading) {
                GeometryReader { g in
                    if let button {
                        let origin = g.frame(in: .global).origin
                        Color.black.opacity(0.001)
                            .frame(width: button.width, height: button.height)
                            .matchedTransitionSource(id: id, in: namespace) { $0.clipShape(.rect(cornerRadius: button.height / 2)) }
                            // Laid out there (an offset would leave its frame at the corner).
                            .padding(.leading, max(0, button.minX - origin.x))
                            .padding(.top, max(0, button.minY - origin.y))
                    }
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            // Once the bar has laid out, and again whenever its buttons may have moved.
            .task(id: label) { await measure() }
            .onGeometryChange(for: CGSize.self, of: { $0.size }) { _ in
                Task { await measure() }
            }
    }

    private func measure() async {
        try? await Task.sleep(for: .milliseconds(300))
        // Never a search page's own field over this page (its words can be the same).
        guard let found = barButtonFrame(label), found.width < 260 else { return }
        button = found
        app.navigator.searchButtonFrames[id] = found
    }
}

/// Where the shown navigation bar's element labelled `label` is, in the window's space (an
/// accessibility frame: SwiftUI's bar items aren't plain views).
@MainActor func barButtonFrame(_ label: String) -> CGRect? {
    guard let window = topViewController()?.view.window else { return nil }
    func visible(_ v: UIView) -> Bool {
        var cur: UIView? = v
        while let c = cur {
            if c.isHidden || c.alpha < 0.01 { return false }
            cur = c.superview
        }
        return true
    }
    func bars(_ v: UIView) -> [UINavigationBar] {
        if let bar = v as? UINavigationBar { return visible(bar) ? [bar] : [] }
        return v.subviews.flatMap(bars)
    }
    func find(_ obj: NSObject, depth: Int) -> CGRect? {
        if depth > 40 { return nil }
        if let v = obj as? UIView, v.isHidden || v.alpha < 0.01 { return nil }
        if obj.accessibilityLabel == label, !obj.accessibilityFrame.isEmpty { return obj.accessibilityFrame }
        var kids = (obj.accessibilityElements as? [NSObject]) ?? []
        if let v = obj as? UIView { kids += v.subviews }
        for k in kids { if let r = find(k, depth: depth + 1) { return r } }
        return nil
    }
    for bar in bars(window) {
        if let r = find(bar, depth: 0) { return window.convert(r, from: nil) }
    }
    return nil
}
