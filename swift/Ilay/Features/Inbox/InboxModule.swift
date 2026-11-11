import Foundation
import Observation
import UserNotifications

/// One inbox tab's list (`where` = inbox | unread | messages | sent).
struct InboxTabState {
    var items: [InboxItem] = []
    var after: String? = nil
    /// True until the first page arrives (or fails).
    var loading = true
    var loadingMore = false
    var error: Error? = nil

    var hasMore: Bool { after?.isEmpty == false }
}

/// One unread inbox item, ready for a notification.
struct UnreadItem: Equatable, Sendable {
    struct PostTarget: Equatable, Sendable {
        let subreddit: String
        let postId: String
        let commentId: String
    }

    let fullname: String
    let title: String
    let body: String
    /// For comment replies / mentions.
    let post: PostTarget?
    /// Thread to open for private messages.
    let messageFullname: String?
}

/// Inbox state (the four tabs), the unread badge, and background polling +
/// notifications (the counterpart of inbox_controller.dart, inbox_poller.dart and
/// notification_service.dart).
@MainActor @Observable
final class InboxModule: UserScoped {
    static let tabs = [(label: "All", key: "inbox"), (label: "Unread", key: "unread"), (label: "Messages", key: "messages"), (label: "Sent", key: "sent")]

    /// Mirrors the Settings flag (same prefs key as the Flutter build).
    static let notifyInboxPref = "notifyInbox"
    private static let seenIdsPref = "notif_seen_ids"

    @ObservationIgnored private unowned let c: AppContainer

    private var states: [String: InboxTabState]
    /// Unread inbox count for the nav badge.
    private(set) var unreadCount = 0

    @ObservationIgnored private var loadJobs: [String: Task<Void, Never>] = [:]
    /// Tabs with a load running (a finished job stays in `loadJobs`: it says the tab was loaded once).
    @ObservationIgnored private var activeLoads: Set<String> = []
    @ObservationIgnored private var unreadJob: Task<Void, Never>?
    /// Bumped on account change, so a stale in-flight load can't land in the new account's tabs.
    @ObservationIgnored private var generation = 0
    /// One poll at a time (the background task and "Check now" can both start one).
    @ObservationIgnored private var pollTail: Task<[UnreadItem], Never>?

    init(_ c: AppContainer) {
        self.c = c
        states = Dictionary(uniqueKeysWithValues: Self.tabs.map { ($0.key, InboxTabState()) })
    }

    func tab(_ place: String) -> InboxTabState { states[place] ?? InboxTabState() }

    private var anonymous: Bool { c.session.session?.anonymous == true }

    /// Re-reads the unread count (no inbox while browsing without an account).
    func refreshUnread() {
        guard !anonymous, case .loggedIn = c.session.state else {
            unreadCount = 0
            return
        }
        unreadJob?.cancel()
        unreadJob = Task {
            // Coalesce bursts (marking several items quickly) into one request.
            try? await Task.sleep(for: .milliseconds(700))
            if Task.isCancelled { return }
            // A failure keeps the last count.
            if let count = try? await c.repository.getUnreadCount(), !Task.isCancelled { unreadCount = count }
        }
    }

    // MARK: Tabs

    /// Loads `place` the first time a tab is shown.
    func ensureLoaded(_ place: String) {
        let s = tab(place)
        if s.items.isEmpty, s.error == nil, !activeLoads.contains(place) { refresh(place) }
    }

    // When each tab last loaded, for `refreshStale`.
    @ObservationIgnored private var loadedAt: [String: Int] = [:]

    /// Inbox opened, or new mail counted (#150): reloads the tabs already shown once
    /// whose list is older than `maxAgeMillis`. Before, only a pull (or the app coming
    /// back from the background) did.
    func refreshStale(maxAgeMillis: Int) {
        if anonymous { return }
        let now = nowMillis()
        for (place, s) in states where !s.items.isEmpty || s.error != nil {
            if activeLoads.contains(place) { continue }
            if now - (loadedAt[place] ?? 0) >= maxAgeMillis { refresh(place) }
        }
    }

    /// Reloads one tab from the first page (and the badge).
    @discardableResult func refresh(_ place: String) -> Task<Void, Never> {
        loadJobs[place]?.cancel()
        let gen = generation
        activeLoads.insert(place)
        let job = Task {
            do {
                let listing = try await c.repository.getInbox(where: place)
                if Task.isCancelled || gen != generation { return }
                states[place] = InboxTabState(items: listing.items, after: listing.after, loading: false)
                loadedAt[place] = nowMillis()
            } catch {
                if Task.isCancelled || gen != generation { return }
                states[place]?.loading = false
                states[place]?.loadingMore = false
                states[place]?.error = error
            }
            activeLoads.remove(place)
        }
        loadJobs[place] = job
        refreshUnread()
        return job
    }

    /// Pull-to-refresh: waits until the reload finishes. The current list (or error)
    /// stays up meanwhile — clearing the error here flashed "Nothing here" — and is
    /// replaced by the result, as in Flutter.
    func refreshAndWait(_ place: String) async {
        await refresh(place).value
    }

    func loadMore(_ place: String) {
        let current = tab(place)
        if !current.hasMore || current.loadingMore || current.loading { return }
        states[place]?.loadingMore = true
        let gen = generation
        Task {
            do {
                let listing = try await c.repository.getInbox(where: place, after: current.after)
                if gen != generation { return }
                let seen = Set(tab(place).items.map(\.fullname))
                states[place]?.items += listing.items.filter { !seen.contains($0.fullname) }
                states[place]?.after = listing.after
                states[place]?.loadingMore = false
            } catch {
                if gen == generation { states[place]?.loadingMore = false }
            }
        }
    }

    /// Applies `change` to `fullname` in every tab (an item can show in several).
    private func mapItem(_ fullname: String, _ change: (InboxItem) -> InboxItem?) {
        for key in Array(states.keys) {
            guard let items = states[key]?.items, items.contains(where: { $0.fullname == fullname }) else { continue }
            // Built first: `states[key]?.items = states[key]?…` starts the write on
            // `states` before reading it again on the right, an exclusivity crash.
            let changed = items.compactMap { $0.fullname == fullname ? change($0) : $0 }
            states[key]?.items = changed
        }
    }

    /// Whether the loaded item is unread (nil if it isn't loaded).
    private func isNew(_ fullname: String) -> Bool? {
        for s in states.values {
            if let item = s.items.first(where: { $0.fullname == fullname }) { return item.isNew }
        }
        return nil
    }

    /// Replies / mentions (comment ids) Reddit's notification list says you opened
    /// elsewhere: mark the loaded unread ones read here and in Reddit's inbox (not
    /// back on the notification list, where they already are).
    func markReadFromReddit(_ commentIds: [String]) {
        for id in commentIds where isNew("t1_\(id)") == true {
            markRead("t1_\(id)", notifications: false)
        }
    }

    /// Optimistically marks one item read locally and on the server (`notifications`: Reddit's notification list too).
    func markRead(_ fullname: String, notifications: Bool = true) {
        // Already read: nothing to send (a repeated swipe used to fire again and
        // again, hitting Reddit's rate limit).
        if isNew(fullname) == false { return }
        mapItem(fullname) { var item = $0; item.isNew = false; return item }
        Task {
            // A failure keeps the optimistic state.
            if (try? await c.repository.markRead(fullname)) != nil { refreshUnread() }
        }
        // Replies and mentions also sit in Reddit's notification list (website sign-in).
        if notifications, fullname.hasPrefix("t1_") { c.redditNotifications.markReadOnReddit(fullname.removePrefix("t1_")) }
    }

    /// Optimistically marks one item unread locally and on the server.
    func markUnread(_ fullname: String) {
        if isNew(fullname) == true { return }
        mapItem(fullname) { var item = $0; item.isNew = true; return item }
        Task {
            if (try? await c.repository.markUnread(fullname)) != nil { refreshUnread() }
        }
    }

    /// Deletes a private message (t4_). Optimistically removes it from the list.
    func deleteMessage(_ fullname: String) {
        mapItem(fullname) { _ in nil }
        Task {
            if (try? await c.repository.deleteMessage(fullname)) != nil { refreshUnread() }
        }
    }

    /// Marks *everything* read — Reddit's read_all_messages has no per-tab variant —
    /// so every tab is refreshed afterwards, not just this one. Throws on failure
    /// (after restoring this tab) so the caller can say so.
    func markAllRead(_ place: String) async throws {
        let before = tab(place)
        states[place]?.items = before.items.map { var item = $0; item.isNew = false; return item }
        do {
            try await c.repository.markAllRead()
        } catch {
            states[place] = before
            throw error
        }
        c.redditNotifications.markAllReadOnReddit()
        refreshLoadedTabs()
    }

    private func refreshLoadedTabs() {
        for (place, s) in states where !s.items.isEmpty || s.error != nil || loadJobs[place] != nil {
            refresh(place)
        }
        refreshUnread()
    }

    // MARK: App lifecycle

    /// App start: takes notification taps and background checks (both must be set up
    /// before launch finishes), and keeps polling scheduled if notifications are on.
    func onAppStart() {
        InboxNotifications.start()
        if c.prefs.getBool(Self.notifyInboxPref) == true { registerPolling() }
        PostReminders.shared.fired()
    }

    /// App resumed (>= 2 min since last): re-sync every inbox tab so items read on
    /// the official app show as read here, and the badge.
    func onAppResumed() {
        if anonymous { return }
        refreshLoadedTabs()
    }

    // MARK: Notifications

    /// A notification was tapped (it navigates once the session is ready: on a cold
    /// start the tap arrives before the UI exists).
    func handleNotificationTap(_ info: [AnyHashable: Any]) {
        // Tapped after updating from the Flutter build, which scheduled it.
        if info[InboxNotifications.extraTarget] == nil, let payload = info["payload"] as? String {
            let target = flutterPayloadRoute(payload)
            openFromNotification(target.route, inbox: target.inbox)
            return
        }
        let target = info[InboxNotifications.extraTarget] as? String
        let sub = info[InboxNotifications.extraSubreddit] as? String
        let post = info[InboxNotifications.extraPostId] as? String
        switch target {
        case InboxNotifications.targetPost:
            let route = sub.flatMap { s in post.map { Route.post(subreddit: s, postId: $0, focusCommentId: info[InboxNotifications.extraCommentId] as? String) } }
            openFromNotification(route, inbox: true)
        // A post reminder: open the post where you are (not the Inbox).
        case PostReminders.target:
            let route = sub.flatMap { s in post.map { Route.post(subreddit: s, postId: $0) } }
            openFromNotification(route, inbox: false)
        case InboxNotifications.targetMessage:
            openFromNotification((info[InboxNotifications.extraMessage] as? String).map { .messageThread(fullname: $0) }, inbox: true)
        default:
            openFromNotification(nil, inbox: true)
        }
    }

    /// Back to the tab's root (screens opened by earlier notifications are closed, so
    /// Back doesn't walk through them), on the Inbox tab for inbox items, then `route` on top.
    private func openFromNotification(_ route: Route?, inbox: Bool) {
        Task {
            for _ in 0..<200 { // up to ~10 s for a cold start
                let nav = c.navigator
                switch c.session.state {
                case .loading: break
                case .loggedOut: return
                case .loggedIn:
                    if nav.showingHome {
                        // The app may be anywhere: close a full-screen viewer or open
                        // sheet first, or the screen opens hidden underneath it.
                        nav.viewers.clear()
                        Overlays.dismissAll()
                        nav.paths[nav.selectedTab] = []
                        if inbox {
                            nav.selectedTab = 2
                            nav.paths[2] = []
                        }
                        if let route { nav.push(route) }
                        return
                    }
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    /// The notification permission (call from UI). True if granted.
    func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
    }

    /// Checks the inbox and, when `notify` is true, fires a notification for each
    /// item not already seen; returns the items it showed one for. When `notify` is
    /// false it only "primes" the seen set (used when the user first turns the
    /// feature on, so we don't dump a notification for every pre-existing unread item).
    func pollInbox(notify: Bool) async -> [UnreadItem] {
        let previous = pollTail
        let job = Task { () -> [UnreadItem] in
            _ = await previous?.value
            return await runPoll(notify: notify)
        }
        pollTail = job
        return await withTaskCancellationHandler { await job.value } onCancel: { job.cancel() }
    }

    private func runPoll(notify: Bool) async -> [UnreadItem] {
        // For one account: the account is read before the request, and a switch while
        // it runs drops the result rather than notifying or recording one account's
        // items as the other's.
        let gen = generation
        let user = await c.secureStore.username() ?? ""
        // Per account: the polled inbox is the active account's, so one shared list
        // made every switch notify for all of the other account's unread. An account's
        // first poll only primes its list (no burst of old items).
        let key = userScopedKey(c.prefs, user, Self.seenIdsPref)
        let primed = c.prefs.contains(key)
        let seen = c.prefs.getStringList(key) ?? []
        let items = await fetchUnread(seen: Set(seen))
        // Out of background time: nothing was learned, so nothing is recorded.
        if Task.isCancelled { return [] }
        guard let items else { // not logged in / network error
            c.notificationLog.checked("Couldn't check: offline, or not signed in")
            return []
        }
        let userNow = await c.secureStore.username() ?? ""
        if gen != generation || userNow != user { return [] }
        let fresh = items.filter { !seen.contains($0.fullname) }
        var shown: [UnreadItem] = []
        if notify, primed {
            for item in fresh {
                let ok = await InboxNotifications.show(item)
                if ok { shown.append(item) }
                c.notificationLog.add(NotificationEvent(
                    at: nowMillis(), account: user, source: NotificationEvent.sourceInbox,
                    title: item.title, text: item.body,
                    outcome: ok ? .shown : .notShown,
                    subreddit: item.post?.subreddit, postId: item.post?.postId, commentId: item.post?.commentId,
                    messageFullname: item.messageFullname
                ))
            }
        }
        c.notificationLog.checked(
            !primed ? "First check for u/\(user): \(items.count) unread (not notified)"
                : fresh.isEmpty ? "\(items.count) unread, nothing new"
                : !notify ? "\(fresh.count) new (not notified: checked from the app)"
                : "\(fresh.count) new, \(shown.count) notified"
        )
        // Remember everything currently unread so we never re-notify, capped so the
        // list can't grow without bound.
        let current = Set(items.map(\.fullname))
        let updated = items.map(\.fullname) + seen.filter { !current.contains($0) }
        c.prefs.setStringList(key, Array(updated.prefix(200)))
        if !fresh.isEmpty { refreshUnread() }
        return shown
    }

    /// The current unread items, or nil if we can't authenticate / reach Reddit.
    /// Reads past the first 25 while every item on a page is new (a burst between
    /// checks), up to 100: older new ones would otherwise never notify.
    private func fetchUnread(seen: Set<String>) async -> [UnreadItem]? {
        do {
            if await c.secureStore.authMode() == "anon" { return nil }
            if (await c.secureStore.username() ?? "").isEmpty { return nil }
            var out: [UnreadItem] = []
            var after: String?
            for page in 0..<4 {
                let res = try await c.client.getResult("/message/unread", [("limit", "25"), ("after", after)])
                if res.fromCache { return page == 0 ? nil : out } // offline: never notify from a stale copy
                let items = (res.json["data"]["children"].arr() ?? []).compactMap { Self.parseUnread($0["data"]) }
                out += items
                after = res.json["data"]["after"].str()
                if after?.isEmpty != false || items.count < 25 || items.contains(where: { seen.contains($0.fullname) }) { return out }
            }
            return out
        } catch {
            return nil
        }
    }

    func registerPolling() { InboxNotifications.registerPolling() }
    func cancelPolling() { InboxNotifications.cancelPolling() }

    func onUserChanged(_ username: String) {
        generation += 1
        loadJobs.values.forEach { $0.cancel() }
        loadJobs = [:]
        activeLoads = []
        states = Dictionary(uniqueKeysWithValues: Self.tabs.map { ($0.key, InboxTabState()) })
        unreadCount = 0
        refreshUnread()
    }

    /// One unread item parsed from Reddit's raw inbox listing.
    nonisolated static func parseUnread(_ d: JsonElement?) -> UnreadItem? {
        guard let fullname = d["name"].str() else { return nil }
        let author = d["author"].str() ?? "Reddit"
        let wasComment = d["was_comment"].isTrue()
        let subject = d["subject"].str() ?? ""
        let linkTitle = d["link_title"].str()
        let rawBody = (d["body"].str() ?? "").replacingOccurrences(of: "\n", with: " ").trimmed

        let linkSuffix = linkTitle.map { " · \($0)" } ?? ""
        let title = wasComment ? "u/\(author) replied\(linkSuffix)" : subject.isEmpty ? "Message from u/\(author)" : subject
        let snippet = rawBody.count > 140 ? "\(rawBody.prefix(140))…" : rawBody.isEmpty ? "Open Ilay to read" : rawBody
        // Deep-link target for comment replies/mentions (t1_): jump to the comment.
        var post: UnreadItem.PostTarget?
        if wasComment, fullname.hasPrefix("t1_"), let sub = d["subreddit"].str(), !sub.isEmpty,
           let linkId = d["link_id"].str(), linkId.hasPrefix("t3_") { // t3_<postId>
            post = UnreadItem.PostTarget(subreddit: sub, postId: linkId.removePrefix("t3_"), commentId: fullname.removePrefix("t1_"))
        }
        // Messages open their conversation (by its first message when known).
        let message = !wasComment && fullname.hasPrefix("t4_") ? (d["first_message_name"].str() ?? fullname) : nil
        return UnreadItem(fullname: fullname, title: title, body: snippet, post: post, messageFullname: message)
    }
}

/// Where a notification scheduled by the Flutter build goes (its payload is a go_router
/// path: `/comments/<sub>/<id>?comment=<c>`, `/message?id=<m>`, `reminder:` plus a path).
/// One already waiting when the update installs must still open.
func flutterPayloadRoute(_ payload: String) -> (route: Route?, inbox: Bool) {
    let reminder = payload.hasPrefix("reminder:")
    let path = reminder ? payload.removePrefix("reminder:") : payload
    let parts = URLComponents(string: path)
    let query = parts?.queryItems ?? []
    let segments = (parts?.path ?? "").components(separatedBy: "/").filter { !$0.isEmpty }
    if segments.count == 3, segments[0] == "comments" {
        let comment = query.first { $0.name == "comment" }?.value
        return (.post(subreddit: segments[1], postId: segments[2], focusCommentId: comment), !reminder)
    }
    if segments == ["message"], let id = query.first(where: { $0.name == "id" })?.value {
        return (.messageThread(fullname: id), true)
    }
    return (nil, !reminder)
}
