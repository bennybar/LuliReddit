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
