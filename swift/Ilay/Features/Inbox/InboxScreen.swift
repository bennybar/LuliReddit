import SwiftUI

/// The Inbox pager key for Reddit's own notifications (website sign-in only).
private let redditTab = "reddit"

/// A chip of Inbox's row (#246): Reddit's `place` list, only its `kinds` when set.
private struct InboxPage: Hashable {
    let label: String
    let place: String
    var kinds: Set<InboxKind>? = nil
}

/// All, Unread, Replies, Mentions, Messages, Sent: what were the tabs and, under All, a
/// filter menu ("Messages" was in both). Replies are All's comment and post replies
/// (Reddit lists those two apart); Mentions are Reddit's own list of them.
private let inboxPages = [
    InboxPage(label: "All", place: "inbox"),
    InboxPage(label: "Unread", place: "unread"),
    InboxPage(label: "Replies", place: "inbox", kinds: [.commentReply, .postReply]),
    InboxPage(label: "Mentions", place: "mentions"),
    InboxPage(label: "Messages", place: "messages"),
    InboxPage(label: "Sent", place: "sent"),
]

/// The Inbox tab. Re-tapping it scrolls the current list to top (`nav.tabReselect[2]`).
struct InboxScreen: View {
    /// A page of its own (Settings › Inbox in Profile): its title and Back, no ☰ or search bar.
    var pushed = false
    @Environment(AppNavigator.self) private var nav
    /// The chip picked, by label (All and Replies share a list).
    @State private var tab = "All"
    @State private var webSignIn = false
    @State private var fab = FabScroll()
    /// The top row of each tab, for coming back to it.
    @State private var tops: [String: String] = [:]

    private var anonymous: Bool { app.session.session?.anonymous == true }

    private var fullBar: Bool { app.settings.value.topBarMode == .full }

    var body: some View {
        // Signed in on the web: Reddit's own notifications (a chip) and Chat.
        let pages = inboxPages + (webSignIn ? [InboxPage(label: "Reddit", place: redditTab)] : [])
        let page = pages.first { $0.label == tab } ?? pages[0]
        Group {
            if anonymous {
                List { SignInPrompt(message: "Sign in to see your messages, replies and mentions.") }
            } else {
                Group {
                    if page.place == redditTab {
                        RedditNotificationsList(topId: topBinding(tab), fab: fab)
                    } else {
                        InboxList(place: page.place, kinds: page.kinds, topId: topBinding(tab), fab: fab)
                    }
                }
                .id(tab)
                .safeAreaBar(edge: .top) {
                    InboxChips(pages: pages, selected: $tab, unread: app.inbox.unreadCount)
                }
                .overlay(alignment: .bottomTrailing) {
                    CollapsingFab(systemImage: "square.and.pencil", label: "New message", expanded: fab.expanded) {
                        Overlays.launch { done in
                            NavigationStack { ComposeMessageScreen(to: nil, onCancel: done) }
                        }
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 12) // a little clear of the tab bar, as every floating button over it
                }
            }
        }
        // Opening Inbox reloads what's a minute old, and new mail (the badge going up)
        // reloads it at once (#150): it used to wait for a pull.
        .onAppear { app.inbox.refreshStale(maxAgeMillis: 60_000) }
        .onChange(of: app.inbox.unreadCount) { old, new in
            if new > old { app.inbox.refreshStale(maxAgeMillis: 0) }
        }
        // Settings › Appearance › Top bar, as Posts and Explore (#214): Full, the search
        // bar in the middle with Inbox's buttons after it; Expandable, the title.
        .navigationTitle(fullBar && !pushed ? "" : "Inbox")
        // Opened from Profile, its title big as well with Expandable (#247).
        .navigationBarTitleDisplayMode(fullBar ? .inline : pushed ? .large : .automatic)
        .toolbar {
            if !pushed { ToolbarItem(placement: .topBarLeading) { SideBarButton() } }
            if fullBar && !pushed {
                ToolbarItem(placement: .principal) {
                    Button { nav.push(.search()) } label: {
                        Text("Search Reddit").foregroundStyle(.secondary).frame(maxWidth: 220)
                    }
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !anonymous {
                    if webSignIn {
                        Button("Reddit Chat", systemImage: "bubble.left.and.bubble.right") {
                            nav.push(.redditWeb(url: RedditWeb.chat, title: "Chat"))
                        }
                    }
                    // Reddit's notifications are read-only here: nothing to mark.
                    if page.place != redditTab {
                        Button("Mark all read", systemImage: "envelope.open") {
                            Task {
                                do {
                                    try await app.inbox.markAllRead(page.place)
                                } catch {
                                    nav.showSnackbar("Couldn't mark all read: \(friendlyError(error))")
                                }
                            }
                        }
                    }
                }
                SettingsButton()
            }
        }
        .task(id: app.session.state) { webSignIn = await app.secureStore.authMode() == "web" }
        .onChange(of: webSignIn) { if !webSignIn, tab == "Reddit" { tab = "All" } }
    }

    private func topBinding(_ key: String) -> Binding<String?> {
        Binding(get: { tops[key] }, set: { tops[key] = $0 })
    }
}

/// Inbox's one row of chips (#246), the one picked kept in view.
private struct InboxChips: View {
    let pages: [InboxPage]
    @Binding var selected: String
    let unread: Int

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(pages, id: \.label) { p in
                        let on = p.label == selected
                        Button {
                            selected = p.label
                        } label: {
                            Text(p.place == "unread" && unread > 0 ? "Unread · \(unread)" : p.label)
                                .font(.subheadline.weight(on ? .semibold : .regular))
                                .padding(.horizontal, 14)
                                .frame(height: 34)
                                .foregroundStyle(on ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                                .background(on ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(.tertiarySystemFill)), in: .capsule)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                        .id(p.label)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 8)
            .onChange(of: selected) { withAnimation { proxy.scrollTo(selected, anchor: .center) } }
        }
    }
}

/// The rows on screen, updated as they come and go (no redraw needed).
private final class VisibleRows {
    var ids = Set<String>()
}

/// What a list needs to keep its place and the button folding: the screen remembers
/// each tab's top row, and re-tapping the Inbox tab scrolls to top. By row, as
/// `ScrollViewReader` is what a `List` reliably obeys.
private struct InboxScrolling: ViewModifier {
    @Binding var topId: String?
    let ids: [String]
    let visible: VisibleRows
    let proxy: ScrollViewProxy
    let fab: FabScroll
    @Environment(AppNavigator.self) private var nav
    @State private var tracking = false

    func body(content: Content) -> some View {
        content
            .onScrollPhaseChange { old, phase in
                tracking = phase == .interacting
                // Only a scroll that ended: a list settling as it appears says nothing.
                if phase == .idle, old != .idle { topId = ids.first(where: visible.ids.contains) }
            }
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { old, new in
                fab.onScroll(available: old - new, userInput: tracking)
            }
            .task {
                let target = topId
                // After the first layout: a List ignores it before that.
                try? await Task.sleep(for: .milliseconds(150))
                if let target, target != ids.first { proxy.scrollTo(target, anchor: .top) }
            }
            .onChange(of: nav.tabReselect[2]) {
                if let first = ids.first { withAnimation { proxy.scrollTo(first, anchor: .top) } }
            }
    }
}

private struct InboxList: View {
    let place: String
    let kinds: Set<InboxKind>?
    @Binding var topId: String?
    let fab: FabScroll
    @Environment(AppNavigator.self) private var nav
    @State private var visible = VisibleRows()

    private var items: [InboxItem] {
        let all = app.inbox.tab(place).items
        guard let kinds else { return all }
        return all.filter { kinds.contains($0.kind) }
    }

    var body: some View {
        let state = app.inbox.tab(place)
        let items = items
        ScrollViewReader { proxy in
        List {
            if state.loading && state.items.isEmpty {
                Loading().frame(maxWidth: .infinity).listRowSeparator(.hidden)
            } else if let error = state.error {
                // A failed (re)load shows the error even over loaded items, as in
                // Flutter (its AsyncError replaced the list); pull or Retry.
                ErrorView(message: "Could not load inbox.\n\(friendlyError(error))", onRetry: { app.inbox.refresh(place) })
                    .listRowSeparator(.hidden)
            } else if items.isEmpty {
                ContentUnavailableView("Nothing here", systemImage: "tray")
                    .listRowSeparator(.hidden)
            } else {
                ForEach(items) { item in
                    Button { open(item) } label: { InboxRow(item: item) }
                        .buttonStyle(.plain)
                        // Unread: the row tinted too, not just its dot (#120).
                        .listRowBackground(item.isNew ? Color.accentColor.opacity(0.12) : nil)
                        // Messages: swipe right = read/unread, swipe left = delete.
                        // Comment replies/mentions: read/unread only (they can't be deleted).
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button(item.isNew ? "Mark read" : "Mark unread", systemImage: item.isNew ? "envelope.open" : "envelope.badge") {
                                if item.isNew { app.inbox.markRead(item.fullname) } else { app.inbox.markUnread(item.fullname) }
                            }
                            .tint(.green)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if item.isMessage {
                                // Deleting can't be undone, so the swipe asks first. (Not
                                // role: .destructive, which slides the row away before the answer.)
                                Button("Delete", systemImage: "trash") {
                                    Task { if await confirmDelete("message") { app.inbox.deleteMessage(item.fullname) } }
                                }
                                .tint(.red)
                            }
                        }
                        // Load the next page as the end comes into view.
                        .onAppear {
                            visible.ids.insert(item.fullname)
                            if items.suffix(4).contains(where: { $0.fullname == item.fullname }) { app.inbox.loadMore(place) }
                        }
                        .onDisappear { visible.ids.remove(item.fullname) }
                }
                if state.loadingMore {
                    Loading().frame(maxWidth: .infinity).listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .contentMargins(.bottom, 80, for: .scrollContent)
        .modifier(InboxScrolling(topId: $topId, ids: items.map(\.fullname), visible: visible, proxy: proxy, fab: fab))
        }
        .refreshable { await app.inbox.refreshAndWait(place) }
        .task(id: place) { app.inbox.ensureLoaded(place) }
        // A kind filter can leave too few rows to scroll (or none, and no list): keep
        // fetching, within a bound, until there's a screenful.
        .task(id: [items.count, state.items.count, state.after?.hashValue ?? 0, state.loadingMore ? 1 : 0, state.loading ? 1 : 0]) {
            if items.count < 10, state.hasMore, !state.loading, !state.loadingMore, state.items.count < 500 {
                app.inbox.loadMore(place)
            }
        }
    }

    private func open(_ item: InboxItem) {
        if item.isNew { app.inbox.markRead(item.fullname) }
        if item.isMessage {
            NavCache.put(item.fullname, item)
            nav.push(.messageThread(fullname: item.fullname))
        } else if let ref = item.postRef {
            // Comment replies/mentions are t1_<id> → jump straight to that comment.
            let commentId = item.fullname.hasPrefix("t1_") ? item.fullname.removePrefix("t1_") : item.contextCommentId
            nav.push(.post(subreddit: ref.subreddit, postId: ref.postId, focusCommentId: commentId))
        }
    }
}

private struct InboxRow: View {
    let item: InboxItem

    var body: some View {
        let (icon, label) = switch item.kind {
        case .message: ("envelope", "Message")
        case .commentReply: ("arrowshape.turn.up.left", "Comment reply")
        case .postReply: ("bubble.left.and.bubble.right", "Post reply")
        case .mention: ("at", "Mention")
        }
        let heading = item.isMessage ? item.subject.nilIfEmpty ?? "(no subject)" : item.linkTitle ?? label
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.caption.weight(.semibold)).foregroundStyle(.tint)
                Text(label).font(.caption.weight(.semibold)).foregroundStyle(.tint)
                Text("\(userName(item.author)) · \(timeAgo(item.createdUtc))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if item.isNew {
                    Circle().fill(.tint).frame(width: 9, height: 9).accessibilityLabel("Unread")
                }
            }
            Text(heading).font(.body.weight(.semibold)).lineLimit(1)
            Text(item.body.replacingOccurrences(of: "\n", with: " "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }
}

/// Reddit's own notifications (replies, mentions, upvote milestones…), read from
/// reddit.com when this tab is shown and kept a few minutes. A tap opens the post or
/// comment in Ilay; older ones are on reddit.com.
private struct RedditNotificationsList: View {
    @Binding var topId: String?
    let fab: FabScroll
    @Environment(AppNavigator.self) private var nav
    @State private var visible = VisibleRows()

    var body: some View {
        let state = app.redditNotifications.state
        var ids: [String] = []
        if case let .data(items, _, _, _) = state { ids = items.map(\.id) }
        return ScrollViewReader { proxy in
        List {
            switch state {
            case nil, .loading:
                Loading().frame(maxWidth: .infinity).listRowSeparator(.hidden)
            case let .failed(signedOut):
                ContentUnavailableView {
                    Image(systemName: "bell.slash")
                } description: {
                    Text(signedOut
                        ? "Your Reddit website sign-in has expired. Sign in again to see Reddit's notifications."
                        : "Couldn't load Reddit's notifications. Pull to try again.")
                } actions: {
                    Button("Open on reddit.com", action: openWeb).buttonStyle(.glass)
                }
                .listRowSeparator(.hidden)
            case let .data(items, _, hasMore, loadingMore):
                if items.isEmpty {
                    ContentUnavailableView("No notifications", systemImage: "bell")
                        .listRowSeparator(.hidden)
                }
                ForEach(items) { n in
                    Button {
                        app.redditNotifications.opened(n)
                        if let link = n.link { nav.openLink(link) } else { openWeb() }
                    } label: {
                        RedditNotificationRow(n: n)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(n.unread ? Color.accentColor.opacity(0.12) : nil) // as unread inbox rows (#120)
                    .onAppear {
                        visible.ids.insert(n.id)
                        if items.suffix(4).contains(where: { $0.id == n.id }) { app.redditNotifications.loadMore() }
                    }
                    .onDisappear { visible.ids.remove(n.id) }
                }
                if loadingMore {
                    Loading().frame(maxWidth: .infinity).listRowSeparator(.hidden)
                } else if !hasMore, !items.isEmpty {
                    Button("Older notifications on reddit.com", action: openWeb)
                        .foregroundStyle(.tint)
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .contentMargins(.bottom, 80, for: .scrollContent)
        .modifier(InboxScrolling(topId: $topId, ids: ids, visible: visible, proxy: proxy, fab: fab))
        }
        .refreshable {
            app.redditNotifications.refresh(force: true)
            // Done once the page has answered (it can take a while; the spinner says so).
            try? await Task.sleep(for: .milliseconds(100))
            while app.redditNotifications.isBusy { try? await Task.sleep(for: .milliseconds(200)) }
        }
        // Only while you're on this tab; leaving it lets the hidden page close.
        .onAppear { app.redditNotifications.refresh() }
        .onDisappear { app.redditNotifications.release() }
    }

    private func openWeb() {
        nav.push(.redditWeb(url: RedditNotifications.url, title: "Reddit notifications"))
    }
}

private struct RedditNotificationRow: View {
    let n: RedditNotification

    var body: some View {
        let (icon, label) =
            n.type == "POST_REPLY" ? ("bubble.left.and.bubble.right", "Post reply")
            : n.type == "COMMENT_REPLY" ? ("arrowshape.turn.up.left", "Comment reply")
            : n.type.contains("MENTION") ? ("at", "Mention")
            : n.type.hasPrefix("UPVOTE") ? ("arrow.up", "Upvotes")
            : ("bell", "Reddit")
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.caption.weight(.semibold)).foregroundStyle(.tint)
                Text(label).font(.caption.weight(.semibold)).foregroundStyle(.tint)
                if n.at > 0 {
                    Text(timeAgo(n.at)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if n.unread {
                    Circle().fill(.tint).frame(width: 9, height: 9).accessibilityLabel("Unread")
                }
            }
            Text(n.title).font(.body.weight(.semibold)).lineLimit(2)
            if !n.body.isEmpty {
                Text(n.body).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }
}
