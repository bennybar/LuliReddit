import SwiftUI

/// A user's about info and, by sort, the lists already opened (they survive switching tabs).
@MainActor @Observable final class UserProfileModel {
    private(set) var about: Async<RedditUser> = .loading
    /// How far the header has slid away. Read only by the header, so scrolling doesn't re-run the screen.
    var collapse: CGFloat = 0

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

    var body: some View {
        let nav = app.navigator
        let me = app.session.username
        let isSelf = !me.isEmpty && me.lowercased() == username.lowercased()

        UserProfileBody(username: username)
            .navigationTitle("u/\(username)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    let share = { nav.share("https://reddit.com/user/\(username)") }
                    if isSelf {
                        Button("Share", systemImage: "square.and.arrow.up", action: share)
                    } else {
                        Menu("More", systemImage: "ellipsis") {
                            Button("Send message", systemImage: "envelope") { nav.push(.composeMessage(to: username)) }
                            Button("Share", systemImage: "square.and.arrow.up", action: share)
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
/// lists: the user screen, and the Profile tab (`belowHeader`: its "Your stuff" row).
/// Each new `scrollTop` value takes the list and header back to the top.
struct UserProfileBody<Below: View>: View {
    let username: String
    var scrollTop = 0
    @ViewBuilder let belowHeader: () -> Below

    @State private var model: UserProfileModel
    @State private var tab = "Posts"
    // Posts and comments, newest first like reddit.com; Hot and Top too.
    @State private var sort = PostSort.newest
    @State private var time = TopTime.all
    @State private var headerHeight: CGFloat = 0
    @State private var tabsHeight: CGFloat = 0

    init(username: String, scrollTop: Int = 0, @ViewBuilder belowHeader: @escaping () -> Below) {
        self.username = username
        self.scrollTop = scrollTop
        self.belowHeader = belowHeader
        _model = State(initialValue: UserProfileModel(username: username))
    }

    private var isSelf: Bool {
        let me = app.session.username
        return !me.isEmpty && me.lowercased() == username.lowercased()
    }

    private var tabs: [String] {
        isSelf ? ["Posts", "Comments", "Saved", "Upvoted", "Downvoted"] : ["Posts", "Comments"]
    }

    var body: some View {
        let me = app.session.username
        let current = tabs.contains(tab) ? tab : "Posts"
        // A deleted (Reddit's 404) or suspended account has no lists either: just say so.
        let gone: Error? = if case let .error(e) = model.about, e is AppException || (e as? RedditApiException)?.statusCode == 404 { e } else { nil }
        // The header (and the Profile tab's row under it) slides away as a list scrolls down
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
                            ProfileHeader(user: user, canFollow: !isSelf && !me.isEmpty)
                        }
                        belowHeader()
                    } tabs: {
                        // Posts / Comments / Saved as segments, your Upvoted and Downvoted (used less) in a menu
                        // beside them, and the sort for Posts and Comments: on the same row when it fits, else under it.
                        let more = isSelf ? ["Upvoted", "Downvoted"] : []
                        let segments = ConnectedChoice(options: tabs.filter { !more.contains($0) }.map { (key: $0, label: $0) }, selected: current, onSelect: { tab = $0 })
                        let moreMenu = PickOneMenu(
                            options: more.map { (key: $0, label: $0) },
                            selected: more.contains(current) ? current : nil,
                            onPick: { tab = $0 },
                            icon: { $0 == "Upvoted" ? "arrow.up" : "arrow.down" }
                        ) {
                            // On one of its lists, the button names it (no segment is selected then).
                            if more.contains(current) {
                                Label(current, systemImage: current == "Upvoted" ? "arrow.up" : "arrow.down").font(.subheadline)
                            } else {
                                Label("More", systemImage: "ellipsis").labelStyle(.iconOnly).frame(minHeight: 20)
                            }
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        let sortBar = SortBar(sort: sort, time: time, sorts: [.newest, .hot, .top]) { s, t in
                            sort = s
                            if let t { time = t }
                        }
                        let sorted = current == "Posts" || current == "Comments"
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) {
                                segments
                                if sorted { sortBar }
                                if !more.isEmpty { moreMenu }
                            }
                            VStack(alignment: .trailing, spacing: 6) {
                                HStack(spacing: 8) {
                                    segments
                                    if !more.isEmpty { moreMenu }
                                }
                                if sorted { sortBar }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                    }
                }
            }
        }
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
        }
    }
}

extension UserProfileBody where Below == EmptyView {
    init(username: String, scrollTop: Int = 0) {
        self.init(username: username, scrollTop: scrollTop) { EmptyView() }
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
    }
}

private struct ProfileHeader: View {
    let user: RedditUser
    let canFollow: Bool

    // Following a user is subscribing to their profile (u_<name>): their posts
    // then show in your Best / Hot / New and For You, like a subreddit's.
    @State private var following: Bool
    @State private var busy = false

    init(user: RedditUser, canFollow: Bool) {
        self.user = user
        self.canFollow = canFollow
        _following = State(initialValue: user.following)
    }

    var body: some View {
        HStack(spacing: 16) {
            LetterAvatar(name: user.name, size: 60, imageUrl: user.iconUrl)
            VStack(alignment: .leading, spacing: 2) {
                Text("u/\(user.name)").font(.title3.bold()).lineLimit(1)
                Text("\(compactNumber(user.linkKarma)) post · \(compactNumber(user.commentKarma)) comment karma")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Joined \(Date(timeIntervalSince1970: Double(user.createdUtc) / 1000).formatted(.dateTime.month(.abbreviated).year()))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            Text("r/\(comment.subreddit) · \(compactNumber(vote.score)) pts · \(timeAgo(comment.createdUtc))")
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
