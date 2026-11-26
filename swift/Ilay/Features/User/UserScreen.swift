import SwiftUI

/// A user's about info and, by sort, the lists already opened (they survive switching tabs).
@MainActor @Observable final class UserProfileModel {
    private(set) var about: Async<RedditUser> = .loading
    /// How far the header has slid away. Read only by the header, so scrolling doesn't re-run the screen.
    var collapse: CGFloat = 0
    /// How far the list is pulled down past its top (pull to refresh): the header moves down
    /// with it, or the large title, which follows the pull, slides in behind the header.
    var pull: CGFloat = 0

    @ObservationIgnored private let username: String
    @ObservationIgnored private var started = false
    @ObservationIgnored private var sources: [String: AnyObject] = [:]

    init(username: String) { self.username = username }

    func load() {
        if started { return }
        started = true
        Task {
            do { about = .data(try await app.repository.getUserAbout(username)) } catch { about = .error(error) }
        }
    }

    func retry() {
        about = .loading
        started = false
        load()
    }

    func source<T>(_ key: String, fetch: @escaping (String?) async throws -> Listing<T>) -> PagedSource<T> {
        if let existing = sources[key] as? PagedSource<T> { return existing }
        let new = PagedSource(fetch: fetch)
        sources[key] = new
        return new
    }
}

/// A user's profile: header + Posts / Comments (and your own Saved / Upvoted / Downvoted) tabs.
struct UserScreen: View {
    let username: String
    @State private var tab = "Posts"
    /// Home's namespace: the Search screen grows out of this page's search button (#293, as #285).
    @Environment(\.searchZoom) private var homeZoom
    /// Outside Home (previews): one of its own, matching nothing.
    @Namespace private var ownZoom

    /// Its own id: this page sits over a tab, whose button has the plain one.
    private var zoomSource: String { "\(searchZoomSource):u/\(username)" }

    var body: some View {
        let nav = app.navigator
        let me = app.session.username
        let isSelf = !me.isEmpty && me.lowercased() == username.lowercased()
        // Expandable: the community page's header, the banner behind the bar (#293).
        let banner = app.settings.value.topBarMode == .expandable

        UserProfileBody(username: username, tab: $tab)
            .navigationTitle(banner ? "" : "u/\(username)")
            .navigationBarTitleDisplayMode(.inline)
            .barZoomSource(zoomSource, in: homeZoom ?? ownZoom, label: "Search")
            .toolbar {
                if banner {
                    // Their posts, as your Profile's search finds yours.
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Search", systemImage: "magnifyingglass") {
                            nav.push(.search(query: "author:\(username)"), zoom: true, zoomSource: zoomSource)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    let share = { nav.share("https://reddit.com/user/\(username)") }
                    if isSelf {
                        Button("Share", systemImage: "square.and.arrow.up", action: share)
                    } else {
                        Menu("More", systemImage: "ellipsis") {
                            Button("Send message", systemImage: "envelope") { nav.push(.composeMessage(to: username)) }
                            Button("Share", systemImage: "square.and.arrow.up", action: share)
                            Button("Report user", systemImage: "flag") { // #221
                                Task { await showReportDialog("u/\(username)") { try await app.repository.reportUser(username, reason: $0) } }
                            }
                            Button("Block user", systemImage: "hand.raised", role: .destructive) {
                                Task { await confirmBlockUser(username) }
                            }
                        }
                    }
                }
            }
    }
}

/// A profile's header and its Posts / Comments (and your own Saved / Upvoted / Downvoted)
/// lists: the user screen, and the Profile tab (whose Library menu picks Upvoted and
/// Downvoted, and whose name opens the account switcher: `onSwitchAccount`).
/// Each new `scrollTop` value takes the list and header back to the top.
struct UserProfileBody: View {
    let username: String
    var scrollTop = 0
    @Binding var tab: String
    var onSwitchAccount: (() -> Void)?

    @State private var model: UserProfileModel
    // Posts and comments, newest first like reddit.com; Hot and Top too.
    @State private var sort = PostSort.newest
    @State private var time = TopTime.all
    @State private var headerHeight: CGFloat = 0
    @State private var tabsHeight: CGFloat = 0

    init(username: String, scrollTop: Int = 0, tab: Binding<String>, onSwitchAccount: (() -> Void)? = nil) {
        self.username = username
        self.scrollTop = scrollTop
        _tab = tab
        self.onSwitchAccount = onSwitchAccount
        _model = State(initialValue: UserProfileModel(username: username))
    }

    private var isSelf: Bool {
        let me = app.session.username
        return !me.isEmpty && me.lowercased() == username.lowercased()
    }

    private var tabs: [String] {
        isSelf ? ["Posts", "Comments", "Saved", "Upvoted", "Downvoted"] : ["Posts", "Comments"]
    }

    /// Expandable: the community page's header (#293), the banner behind the bar.
    private var banner: Bool { app.settings.value.topBarMode == .expandable }

    /// "Followed u/x" / "Unfollowed u/x" after the round Follow, as Join's (#277).
    @State private var followPill: String?

    var body: some View {
        let me = app.session.username
        let current = tabs.contains(tab) ? tab : "Posts"
        // A deleted (Reddit's 404) or suspended account has no lists either: just say so.
        let gone: Error? = if case let .error(e) = model.about, e is AppException || (e as? RedditApiException)?.statusCode == 404 { e } else { nil }
        // The header slides away as a list scrolls down
        // and comes back once it's back at the top; the tabs stay. It sits over the list, which
        // leaves it room: moving with the rows, not resizing them, keeps the scrolling smooth.
        Group {
            if let gone {
                ErrorView(
                    message: gone is AppException ? gone : "u/\(username) doesn't exist or has been deleted.",
                    systemImage: "person.slash"
                )
            } else {
                ZStack(alignment: .top) {
                    list(current)
                    ProfileTop(model: model, headerHeight: $headerHeight, tabsHeight: $tabsHeight) {
                        switch model.about {
                        case .loading:
                            Loading().frame(maxWidth: .infinity, minHeight: 96)
                        case let .error(error):
                            ErrorView(message: error, onRetry: model.retry)
                        case let .data(user):
                            if banner {
                                UserBannerHeader(user: user, canFollow: !isSelf && !me.isEmpty, onSwitchAccount: onSwitchAccount) { on in
                                    followPill = "\(on ? "Followed" : "Unfollowed") \(userName(user.name))"
                                }
                            } else {
                                ProfileHeader(user: user, canFollow: !isSelf && !me.isEmpty, onSwitchAccount: onSwitchAccount)
                            }
                        }
                    } tabs: {
                        // Posts / Comments / Saved as segments; Upvoted and Downvoted (picked from the
                        // Library menu) join them as a fourth while open. The sort is beside them.
                        let shown = ["Posts", "Comments", "Saved"].filter(tabs.contains) + (["Upvoted", "Downvoted"].contains(current) ? [current] : [])
                        HStack(spacing: 8) {
                            Picker("List", selection: $tab) {
                                ForEach(shown, id: \.self) { Text($0).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            if current == "Posts" || current == "Comments" {
                                SortBar(sort: sort, time: time, sorts: [.newest, .hot, .top]) { s, t in
                                    sort = s
                                    if let t { time = t }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                    }
                    if banner, case let .data(user) = model.about, user.bannerUrl != nil {
                        // The banner from the screen's top, behind the bar, and the picture over
                        // its foot; it moves with the header.
                        UserBannerBackdrop(model: model, user: user)
                    }
                }
            }
        }
        .toolbar {
            if banner, case let .data(user) = model.about {
                // The picture and name, in the bar once the header has gone under it.
                ToolbarItem(placement: .principal) { FoldedName(model: model, user: user) }
            }
        }
        // Above the bottom bar, in the inverse of the page's colours, as Join's.
        .overlay(alignment: .bottom) {
            if let followPill {
                Text(followPill)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(.systemBackground))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color(.label), in: .capsule)
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
                    .padding(.bottom, 84)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(followPill)
                    .task {
                        try? await Task.sleep(for: .seconds(3))
                        withAnimation(.easeOut(duration: 0.25)) { self.followPill = nil }
                    }
            }
        }
        .animation(.spring(duration: 0.3), value: followPill)
        .task { model.load() }
    }

    @ViewBuilder private func list(_ current: String) -> some View {
        let repo = app.repository
        let username = username
        // Your own lists reload on every return from a post (scores and votes
        // you just changed); others' after the usual five minutes.
        let staleAfter = isSelf ? 30_000 : 5 * 60_000
        let sortKey = sort.needsTime ? "\(sort.path)_\(time.param)" : sort.path
        let sortTime = sort.needsTime ? time : nil
        let sort = sort
        let top = headerHeight + tabsHeight
        // "Hide NSFW posts" (Content filters) applies to profiles too (#94), and to
        // the Saved / Upvoted / Downvoted tabs.
        let hideNsfw = app.contentFilters.value.hideNsfw
        let sfw = hideNsfw ? "_sfw" : ""
        switch current {
        case "Posts":
            let key = "posts_\(sortKey)\(sfw)"
            let source: PagedSource<Post> = model.source(key) {
                var page = try await repo.getUserPosts(username, after: $0, sort: sort, time: sortTime)
                if hideNsfw { page.items = page.items.filter { !$0.over18 } }
                return page
            }
            postList(source, top: top, emptyLabel: "No posts yet", staleAfter: staleAfter).id(key)
        case "Comments":
            let source: PagedSource<Comment> = model.source("comments_\(sortKey)") { try await repo.getUserComments(username, after: $0, sort: sort, time: sortTime) }
            PagedList(source: source, itemKey: { AnyHashable($0.fullname) }, emptyLabel: "No comments yet", staleAfterMillis: staleAfter, scrollTop: scrollTop) {
                ProfileCommentCard(comment: $0)
            }
            .background(hook(source.state.items.count, top: top))
            .id("comments_\(sortKey)")
        case "Saved":
            let source: PagedSource<SavedItem> = model.source("saved\(sfw)") {
                var page = try await repo.getUserSaved(username, after: $0)
                if hideNsfw { page.items = page.items.filter { !$0.over18 } }
                return page
            }
            PagedList(
                source: source,
                itemKey: { AnyHashable($0.fullname) },
                emptyLabel: "Nothing saved",
                contentType: { $0.post.map(pagedPostKind) ?? 6 },
                staleAfterMillis: staleAfter,
                scrollTop: scrollTop,
                posts: PagedPostRows(post: \.post)
            ) { item in
                switch item {
                case let .post(post): PagedPostRow(post: post)
                case let .comment(comment): ProfileCommentCard(comment: comment)
                }
            }
            .background(hook(source.state.items.count, top: top))
            .id("saved\(sfw)")
        case "Upvoted":
            let source: PagedSource<Post> = model.source("upvoted\(sfw)") {
                var page = try await repo.getUserPosts(username, where: "upvoted", after: $0)
                if hideNsfw { page.items = page.items.filter { !$0.over18 } }
                return page
            }
            postList(source, top: top, emptyLabel: "Nothing upvoted", staleAfter: staleAfter).id("upvoted\(sfw)")
        default:
            let source: PagedSource<Post> = model.source("downvoted\(sfw)") {
                var page = try await repo.getUserPosts(username, where: "downvoted", after: $0)
                if hideNsfw { page.items = page.items.filter { !$0.over18 } }
                return page
            }
            postList(source, top: top, emptyLabel: "Nothing downvoted", staleAfter: staleAfter).id("downvoted\(sfw)")
        }
    }

    private func postList(_ source: PagedSource<Post>, top: CGFloat, emptyLabel: String, staleAfter: Int) -> some View {
        PagedList(
            source: source,
            itemKey: { AnyHashable($0.id) },
            emptyLabel: emptyLabel,
            contentType: pagedPostKind,
            staleAfterMillis: staleAfter,
            scrollTop: scrollTop,
            posts: PagedPostRows(post: { $0 })
        ) { PagedPostRow(post: $0) }
        .background(hook(source.state.items.count, top: top))
    }

    private func hook(_ count: Int, top: CGFloat) -> PagedListHook {
        let (model, headerHeight) = (model, headerHeight)
        return PagedListHook(generation: count, topInset: top) { scrolled in
            let collapse = min(max(scrolled, 0), headerHeight)
            if collapse != model.collapse { model.collapse = collapse }
            let pull = max(-scrolled, 0)
            if pull != model.pull { model.pull = pull }
        }
    }
}

extension SavedItem {
    var fullname: String {
        switch self {
        case let .post(post): post.fullname
        case let .comment(comment): comment.fullname
        }
    }

    var post: Post? {
        if case let .post(post) = self { post } else { nil }
    }

    /// An NSFW post, or a comment on one.
    var over18: Bool {
        switch self {
        case let .post(post): post.over18
        case let .comment(comment): comment.over18
        }
    }
}

/// The header and tabs, over the list. Bottom-aligned in a shrinking frame: the header
/// slides up behind the bars, and the tabs stay right under them.
private struct ProfileTop<Header: View, Tabs: View>: View {
    let model: UserProfileModel
    @Binding var headerHeight: CGFloat
    @Binding var tabsHeight: CGFloat
    @ViewBuilder let header: () -> Header
    @ViewBuilder let tabs: () -> Tabs

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0, content: header)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { headerHeight = $0 }
            tabs()
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { tabsHeight = $0 }
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(.systemBackground))
        .frame(height: max(headerHeight + tabsHeight - model.collapse, 0), alignment: .bottom)
        .clipped()
        .offset(y: model.pull)
    }
}

private struct ProfileHeader: View {
    let user: RedditUser
    let canFollow: Bool
    let onSwitchAccount: (() -> Void)?

    // Following a user is subscribing to their profile (u_<name>): their posts
    // then show in your Best / Hot / New and For You, like a subreddit's.
    @State private var following: Bool
    @State private var busy = false

    init(user: RedditUser, canFollow: Bool, onSwitchAccount: (() -> Void)?) {
        self.user = user
        self.canFollow = canFollow
        self.onSwitchAccount = onSwitchAccount
        _following = State(initialValue: user.following)
    }

    var body: some View {
        HStack(spacing: 16) {
            LetterAvatar(name: user.name, size: 56, imageUrl: user.iconUrl)
                .pictureOpens(user.iconUrl, name: "u/\(user.name)")
            VStack(alignment: .leading, spacing: 2) {
                // Your own name opens the account switcher, as in Mail or the App Store.
                if let onSwitchAccount {
                    Button(action: onSwitchAccount) {
                        HStack(spacing: 4) {
                            Text(userName(user.name)).font(.title3.bold()).lineLimit(1)
                            Image(systemName: "chevron.down").font(.caption.bold()).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Switch or add account")
                } else {
                    Text(userName(user.name)).font(.title3.bold()).lineLimit(1)
                }
                Text("\(compactNumber(user.linkKarma + user.commentKarma)) karma · joined \(Date(timeIntervalSince1970: Double(user.createdUtc) / 1000).formatted(.dateTime.month(.abbreviated).year()))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if canFollow {
                // One toggle: its fill changes with the state, and it reads as on/off.
                Button(following ? "Following" : "Follow") {
                    let next = !following
                    following = next
                    busy = true
                    Task {
                        do {
                            try await app.repository.setSubscribed("u_\(user.name)", subscribe: next)
                        } catch {
                            following = !next
                            app.navigator.showActionError(next ? "follow" : "unfollow", error)
                        }
                        busy = false
                    }
                }
                .buttonStyle(JoinStyle(on: following))
                .disabled(busy)
                .accessibilityAddTraits(following ? .isSelected : [])
            }
        }
        .padding(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
    }
}

private let profileBanner: CGFloat = 64 // under the bar, as a community's
private let profileIcon: CGFloat = 76
private let profileIconOver: CGFloat = 26 // a third of it over the banner's foot (#277's)

/// The banner from the screen's top to its foot, behind the bar, and the picture over its
/// foot (#293, as a community's BannerBackdrop); it slides away with the header.
private struct UserBannerBackdrop: View {
    let model: UserProfileModel
    let user: RedditUser

    var body: some View {
        let page = Color(.systemBackground)
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: profileBanner)
            .background {
                Rectangle()
                    .fill(IlayTheme.accent.opacity(0.35).gradient)
                    .overlay {
                        if let url = user.bannerUrl.flatMap(URL.init(string:)) { BannerImage(url: url) }
                    }
                    .clipped()
                    .ignoresSafeArea(edges: .top)
            }
            .overlay(alignment: .topLeading) {
                LetterAvatar(name: user.name, size: profileIcon, imageUrl: user.iconUrl)
                    .padding(3)
                    .background(page, in: Circle())
                    .offset(x: 13, y: profileBanner - profileIconOver - 3)
            }
            .offset(y: model.pull - model.collapse)
            // Gone once folded: the header stops at the bar, which would leave the picture
            // peeking out behind the status bar.
            .opacity(max(0, 1 - max(0, model.collapse - profileBanner) / 50))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The picture and name in the bar once the header has slid under it.
private struct FoldedName: View {
    let model: UserProfileModel
    let user: RedditUser

    var body: some View {
        let folded = model.collapse > profileBanner + 40
        HStack(spacing: 8) {
            LetterAvatar(name: user.name, size: 24, imageUrl: user.iconUrl)
            Text(userName(user.name)).font(.headline).lineLimit(1)
        }
        .opacity(folded ? 1 : 0)
        .animation(.easeOut(duration: 0.2), value: folded)
    }
}

/// A profile's header as a community's (#293): with a banner, room for it (drawn behind, by
/// UserBannerBackdrop), the picture over its foot and the name beside it; without one, no
/// band of colour standing in but the picture big and centred. Karma and the account's age,
/// Follow as a round + / ✓, and the description in a card when there is one.
private struct UserBannerHeader: View {
    let user: RedditUser
    let canFollow: Bool
    let onSwitchAccount: (() -> Void)?
    /// Followed (true) or stopped (false) by the + / ✓.
    let onFollowed: (Bool) -> Void

    @State private var following: Bool
    @State private var busy = false
    @State private var open = false

    init(user: RedditUser, canFollow: Bool, onSwitchAccount: (() -> Void)?, onFollowed: @escaping (Bool) -> Void) {
        self.user = user
        self.canFollow = canFollow
        self.onSwitchAccount = onSwitchAccount
        self.onFollowed = onFollowed
        _following = State(initialValue: user.following)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if user.bannerUrl != nil {
                Color.clear.frame(height: profileBanner)
                HStack(alignment: .top, spacing: 12) {
                    // The picture's place: drawn with the banner, the rest of it below its foot.
                    Color.clear.frame(width: profileIcon, height: profileIcon - profileIconOver - 10)
                    VStack(alignment: .leading, spacing: 2) {
                        name(.title.bold())
                        karma
                    }
                    .layoutPriority(1)
                    Spacer(minLength: 0)
                    if canFollow { follow }
                }
                .padding(.horizontal, 16)
            } else {
                VStack(spacing: 8) {
                    LetterAvatar(name: user.name, size: 112, imageUrl: user.iconUrl)
                        .pictureOpens(user.iconUrl, name: "u/\(user.name)")
                    name(.largeTitle.bold())
                    HStack(spacing: 12) {
                        karma
                        if canFollow { follow }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            }
            if !user.description.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(user.description)
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .lineLimit(open ? nil : 3)
                    if user.description.count > 120 {
                        Button(open ? "Show less" : "Show all") {
                            withAnimation(.easeInOut(duration: 0.26)) { open.toggle() }
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 22))
                .padding(.horizontal, 12)
            }
        }
        .padding(.bottom, 8)
        .overlay(alignment: .topLeading) {
            // The picture is drawn behind (UserBannerBackdrop), which takes no touches: a clear
            // circle at its place opens it full screen and is where it zooms from (#279).
            if user.bannerUrl != nil, let icon = user.iconUrl {
                Color.clear
                    .frame(width: profileIcon + 6, height: profileIcon + 6)
                    .contentShape(Circle())
                    .zoomSource(circle: true)
                    .onTapGesture { app.navigator.openPicture(icon, name: "u/\(user.name)") }
                    .accessibilityLabel("Open picture")
                    .accessibilityAddTraits(.isButton)
                    .offset(x: 13, y: profileBanner - profileIconOver - 3)
            }
        }
    }

    /// u/name (the "r/ and u/ before names" setting's, #289); your own opens the accounts (#144).
    @ViewBuilder private func name(_ font: Font) -> some View {
        if let onSwitchAccount {
            Button(action: onSwitchAccount) {
                HStack(spacing: 4) {
                    Text(userName(user.name)).font(font).lineLimit(1)
                    Image(systemName: "chevron.down").font(.caption.bold()).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Switch or add account")
        } else {
            Text(userName(user.name)).font(font).lineLimit(1)
        }
    }

    /// "6.2M karma · 20y": karma and how long the account has been around.
    private var karma: some View {
        Text("\(compactNumber(user.linkKarma + user.commentKarma)) karma · \(timeAgo(user.createdUtc))")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    /// Follow as Join is on a community (#277): + to follow, ✓ to stop. Following a user is
    /// subscribing to their profile (u_<name>): their posts then show in your feeds.
    private var follow: some View {
        Button {
            let next = !following
            following = next
            busy = true
            Task {
                do {
                    try await app.repository.setSubscribed("u_\(user.name)", subscribe: next)
                    onFollowed(next)
                } catch {
                    following = !next
                    app.navigator.showActionError(next ? "follow" : "unfollow", error)
                }
                busy = false
            }
        } label: {
            Image(systemName: following ? "checkmark" : "plus")
                .font(.body.weight(.semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 40, height: 40)
                .foregroundStyle(following ? Color.secondary : Color.white)
                .background(following ? AnyShapeStyle(Color(.tertiarySystemFill)) : AnyShapeStyle(IlayTheme.accent), in: .circle)
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityLabel(following ? "Unfollow \(userName(user.name))" : "Follow \(userName(user.name))")
        .accessibilityAddTraits(following ? .isSelected : [])
    }
}

struct ProfileCommentCard: View {
    let comment: Comment

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // Your votes from threads (this list is Reddit's copy from when it loaded).
        let vote = app.commentVotes.effective(comment)
        let colors = IlayTheme.voteColors(dark: colorScheme == .dark)
        let tint: Color = switch vote.likes {
        case true?: colors.up
        case false?: colors.down
        case nil: .secondary
        }
        VStack(alignment: .leading, spacing: 4) {
            if !comment.linkTitle.isEmpty {
                Text(comment.linkTitle).font(.subheadline.bold()).lineLimit(2)
            }
            Text("\(subredditName(comment.subreddit)) · \(compactNumber(vote.score)) pts · \(timeAgo(comment.createdUtc))")
                .font(.caption)
                .foregroundStyle(tint)
            Text(comment.body.replacingOccurrences(of: "\n", with: " "))
                .font(.subheadline)
                .lineLimit(4)
                .padding(.top, 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.pagedCard, in: .rect(cornerRadius: 20))
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .contentShape(.rect)
        .onTapGesture { openPermalink(comment.permalink) }
    }
}
