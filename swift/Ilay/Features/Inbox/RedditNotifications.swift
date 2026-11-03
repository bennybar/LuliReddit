import Foundation
import Observation
import UIKit
import WebKit

/// One entry of Reddit's own notification list (reddit.com/notifications).
struct RedditNotification: Identifiable, Equatable, Sendable {
    let id: String
    /// Reddit's message type, e.g. POST_REPLY, COMMENT_REPLY, UPVOTE_POST, USERNAME_MENTION.
    let type: String
    let title: String
    let body: String
    /// Where it goes (a post or comment link), opened in Ilay.
    let link: String?
    let at: Int
    let avatar: String?
    /// Reddit's "clicked" flag when the page shows it (nil: not known).
    var clicked: Bool? = nil
    /// Not opened yet: new since you last looked or unread on Reddit, and not opened in Ilay.
    var unread = false
}

private let commentLinkRe = Re(#"/comments/[a-z0-9]+/[^/]+/([a-z0-9]+)/?(?:[?#].*)?$"#)
private let commentPathRe = Re(#"/comment/([a-z0-9]+)/?(?:[?#].*)?$"#)

/// Reddit's own notifications (website sign-in), shown natively in the Inbox. Like
/// Home, read from reddit.com in a hidden page. The page opens when you go to the tab
/// and closes soon after you leave it (or when the app goes to the background); while
/// open it also reads older notifications (one small request a batch) and tells Reddit
/// which one you opened. Kept a few minutes, so coming back costs nothing; no
/// background checks.
@MainActor @Observable
final class RedditNotifications: UserScoped {
    enum State {
        case loading
        case data(items: [RedditNotification], at: Int, hasMore: Bool = false, loadingMore: Bool = false)
        case failed(signedOut: Bool)
    }

    static let url = "https://www.reddit.com/notifications"
    private static let freshFor = 3 * 60_000
    private static let timeout: TimeInterval = 25
    private static let maxIds = 400
    private static let seenKey = "redditNotifSeen"
    private static let openedKey = "redditNotifOpened"

    private(set) var state: State?

    @ObservationIgnored private unowned let c: AppContainer
    @ObservationIgnored private var user = ""

    // The hidden page and the link to the next batch.
    @ObservationIgnored private var view: WKWebView?
    @ObservationIgnored private var pageDelegate: HiddenPageDelegate?
    @ObservationIgnored private var nextUrl: String?
    @ObservationIgnored private var closeJob: Task<Void, Never>?

    // One page job at a time.
    @ObservationIgnored private var tail: Task<Void, Never>?
    @ObservationIgnored private var locks = 0

    // In the background the page is closed and nothing new opens.
    @ObservationIgnored private var paused = false
    // The tab is showing (it refreshes on coming back to the app).
    @ObservationIgnored private var active = false

    // Inbox items marked read in Ilay, waiting to be marked on Reddit too.
    @ObservationIgnored private var toMark: [String] = []
    @ObservationIgnored private var markAll = false
    @ObservationIgnored private var markJob: Task<Void, Never>?

    init(_ c: AppContainer) {
        self.c = c
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.paused = true
                self.closeJob?.cancel()
                self.closeView(update: true)
            }
        }
        center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.paused = false
                if !self.toMark.isEmpty || self.markAll { self.queueMark() }
                if self.active { self.refresh() }
            }
        }
    }

    /// A page job is running (pull to refresh waits for it).
    var isBusy: Bool { locks > 0 }

    private func withLock(_ work: @escaping () async -> Void) async {
        let previous = tail
        locks += 1
        let job = Task {
            await previous?.value
            await work()
            locks -= 1
        }
        tail = job
        await job.value
    }

    /// Loads the list unless a recent copy is showing (`force`: pull to refresh).
    func refresh(force: Bool = false) {
        active = true
        closeJob?.cancel()
        if locks > 0 || paused { return }
        if !force, case let .data(_, at, _, _) = state, nowMillis() - at < Self.freshFor { return }
        Task {
            await withLock { [self] in
                let forUser = c.session.username
                if case .data = state {} else { state = .loading }
                var result: PageResult?
                if await c.secureStore.authMode() == "web", let cookie = await c.secureStore.webCookie()?.nilIfEmpty {
                    result = await open(cookie)
                }
                if forUser != c.session.username { return } // account changed meanwhile
                guard let result else {
                    state = .failed(signedOut: true)
                    return
                }
                if result.ok {
                    nextUrl = result.next
                    state = .data(items: mark(result.items), at: nowMillis(), hasMore: result.next != nil)
                } else if case .data = state {
                    // A failed refresh keeps the list you had.
                } else {
                    state = .failed(signedOut: result.signedOut)
                }
            }
        }
    }

    /// The next batch of older notifications, read through the open page.
    func loadMore() {
        guard case let .data(items, at, hasMore, loadingMore) = state, hasMore, !loadingMore, locks == 0 else { return }
        state = .data(items: items, at: at, hasMore: true, loadingMore: true)
        Task {
            await withLock { [self] in
                let more = await nextUrl.asyncMap { await fetchMore($0) } ?? nil
                nextUrl = more?.next
                guard case let .data(current, at, _, _) = state else { return }
                let known = Set(current.map(\.id))
                let added = mark((more?.items ?? []).filter { !known.contains($0.id) })
                state = .data(items: current + added, at: at, hasMore: more?.next != nil && !added.isEmpty)
            }
        }
    }

    /// You opened `n`: it stops showing as unread here, and the open page clicks it
    /// too, which is how Reddit learns it was opened (Reddit's page then moves to the
    /// post, so it steps back to the list).
    func opened(_ n: RedditNotification) {
        remember(Self.openedKey, [n.id])
        setRead { $0.id == n.id }
        if let view { Task { await clickItem(view, n.id) } }
    }

    private func setRead(where matches: (RedditNotification) -> Bool) {
        guard case let .data(items, at, hasMore, loadingMore) = state else { return }
        let updated = items.map { n -> RedditNotification in
            var n = n
            if matches(n) { n.unread = false }
            return n
        }
        state = .data(items: updated, at: at, hasMore: hasMore, loadingMore: loadingMore)
    }

    /// A reply or mention (comment `commentId`) was read in Ilay's Inbox: Reddit's
    /// notification for it is a separate list, so mark it there too (website sign-in
    /// only). Batched: reads close together share one page load.
    func markReadOnReddit(_ commentId: String) {
        if !toMark.contains(commentId) { toMark.append(commentId) }
        queueMark()
    }

    /// Inbox → Mark all read: Reddit's "Mark all as read" on its notification list too.
    func markAllReadOnReddit() {
        markAll = true
        queueMark()
    }

    private func queueMark() {
        markJob?.cancel()
        // In the background: sent on coming back.
        if paused { return }
        markJob = Task {
            try? await Task.sleep(for: .seconds(2))
            if Task.isCancelled { return }
            await withLock { [self] in
                if paused { return } // kept for coming back
                let ids = toMark
                let all = markAll
                toMark = []
                markAll = false
                if ids.isEmpty && !all { return }
                guard await c.secureStore.authMode() == "web", let cookie = await c.secureStore.webCookie()?.nilIfEmpty else { return }
                closeJob?.cancel()
                if view == nil {
                    let r = await open(cookie)
                    if r.ok {
                        nextUrl = r.next
                        state = .data(items: mark(r.items), at: nowMillis(), hasMore: r.next != nil)
                    }
                }
                guard let page = view else { return }
                if all {
                    _ = await eval(page, "(function(){var b=document.querySelector('mark-all-messages-read button');if(b)b.click();return !!b})()")
                    try? await Task.sleep(for: .milliseconds(1500))
                    setRead { _ in true }
                } else {
                    var opened: [String] = []
                    for id in ids {
                        guard case let .data(items, _, _, _) = state else { break }
                        guard let n = items.first(where: { $0.link?.contains("/\(id)/") == true }) else { continue }
                        opened.append(n.id)
                        await clickItem(page, n.id)
                    }
                    if !opened.isEmpty {
                        remember(Self.openedKey, opened)
                        setRead { opened.contains($0.id) }
                    }
                }
            }
            // Reading replies one after another: the next one reuses the page
            // (while the tab is showing, it stays).
            if !active { release(after: 60) }
        }
    }

    // Clicks one notification in the page (how Reddit records it as opened), then
    // steps back to the list, which Reddit's page moved away from.
    private func clickItem(_ page: WKWebView, _ notificationId: String) async {
        let id = notificationId.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let clicked = await eval(page, "(function(){var e=document.querySelector('notification-item[notification-id=\"\(id)\"]');var a=e&&e.querySelector('a[href]');if(a)a.click();return !!a})()")
        guard clicked as? Bool == true else { return }
        try? await Task.sleep(for: .seconds(2))
        if view === page, page.canGoBack { page.goBack() }
        // Wait for the list to be back before the next click.
        for _ in 0..<10 {
            try? await Task.sleep(for: .milliseconds(500))
            if view !== page { return }
            if let count = await eval(page, "document.querySelectorAll('notification-item').length") as? Int, count > 0 { return }
        }
    }

    /// Leaving the tab: the page closes shortly after (coming straight back keeps it).
    func release(after seconds: Double = 10) {
        active = false
        closeJob?.cancel()
        closeJob = Task {
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled { closeView(update: true) }
        }
    }

    private func closeView(update: Bool) {
        view?.stopLoading()
        view?.removeFromSuperview()
        view = nil
        pageDelegate = nil
        nextUrl = nil
        guard update, case let .data(items, at, _, _) = state else { return }
        // No page, no next batch: "Older notifications on reddit.com" stands in.
        state = .data(items: items, at: at)
    }

    // Unread: new since last time (not among the stored "seen" ids), or Reddit says it
    // wasn't clicked; either way, not once opened in Ilay.
    private func mark(_ items: [RedditNotification]) -> [RedditNotification] {
        let seen = recall(Self.seenKey)
        let opened = recall(Self.openedKey)
        let firstLook = seen.isEmpty
        let out = items.map { n -> RedditNotification in
            var n = n
            n.unread = !opened.contains(n.id) && ((!firstLook && !seen.contains(n.id)) || n.clicked == false)
            return n
        }
        remember(Self.seenKey, items.map(\.id))
        // Opened on Reddit (its app, the site): the matching reply or mention reads as
        // read in Ilay's Inbox too. Free: the list is already read.
        let openedThere = items.filter { $0.clicked == true }.compactMap { $0.link.flatMap(Self.commentIdOf) }
        if !openedThere.isEmpty { c.inbox.markReadFromReddit(openedThere) }
        return out
    }

    private func recall(_ base: String) -> Set<String> {
        let raw = c.prefs.getString(userScopedKey(c.prefs, c.session.username, base)) ?? ""
        return Set(raw.components(separatedBy: ",").filter { !$0.isEmpty })
    }

    private func remember(_ base: String, _ ids: [String]) {
        let key = userScopedKey(c.prefs, c.session.username, base)
        var seen = Set<String>()
        let all = (ids + (c.prefs.getString(key) ?? "").components(separatedBy: ","))
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .prefix(Self.maxIds)
        c.prefs.setString(key, all.joined(separator: ","))
    }

    private struct PageResult {
        let items: [RedditNotification]
        let next: String?
        let signedOut: Bool
        let ok: Bool
    }

    private func eval(_ page: WKWebView, _ js: String) async -> Any? {
        await withTimeout(2) { done in
            page.evaluateJavaScript(js) { value, _ in done(value) }
        }
    }

    /// A completion-handler call, given up on after `seconds`. (The async forms of
    /// WebKit's calls crash on a nil result.)
    private func withTimeout(_ seconds: Double, _ call: (@escaping (Any?) -> Void) -> Void) async -> Any? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Any?, Never>) in
            var finished = false
            let done: (Any?) -> Void = { value in
                if finished { return }
                finished = true
                continuation.resume(returning: value)
            }
            call(done)
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                done(nil)
            }
        }
    }

    private func open(_ cookie: String) async -> PageResult {
        closeView(update: false)
        await loadWebSessionCookies(cookie)
        let config = WKWebViewConfiguration()
        // Only the list's text and links are read: no images, video or fonts.
        if let rules = try? await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "ilay-notifications", encodedContentRuleList: redditNotificationBlockRules) {
            config.userContentController.add(rules)
        }
        let page = WKWebView(frame: .zero, configuration: config)
        page.customUserAgent = RedditConstants.webUserAgent
        let delegate = HiddenPageDelegate { [weak self, weak page] in
            if let self, self.view === page { self.closeView(update: true) }
        }
        page.navigationDelegate = delegate
        pageDelegate = delegate
        view = page
        // In the window, as a page that isn't has its timers stopped; never seen or touched.
        let window = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.keyWindow
        page.frame = window?.bounds ?? CGRect(x: 0, y: 0, width: 390, height: 844)
        page.alpha = 0.01
        page.isUserInteractionEnabled = false
        page.accessibilityElementsHidden = true
        window?.insertSubview(page, at: 0)
        page.load(URLRequest(url: URL(string: Self.url)!))
        let deadline = Date().addingTimeInterval(Self.timeout)
        var emptySince: Date?
        while Date() < deadline, view === page {
            try? await Task.sleep(for: .milliseconds(500))
            guard let raw = await eval(page, Self.read) as? String, let json = parseJsonOrNull(raw) else { continue }
            if json["login"].isTrue() {
                closeView(update: false)
                return PageResult(items: [], next: nil, signedOut: true, ok: false)
            }
            let items = Self.parse(json)
            if !items.isEmpty {
                // Reddit's read flags appear once the page has drawn its menus.
                try? await Task.sleep(for: .milliseconds(1200))
                let again = (await eval(page, Self.read) as? String).flatMap(parseJsonOrNull).map(Self.parse) ?? []
                return PageResult(items: again.count >= items.count ? again : items, next: json["next"].str(), signedOut: false, ok: true)
            }
            // The page is up but lists nothing: give it a moment, then it's really empty.
            if json["ready"].isTrue() {
                let now = Date()
                let since = emptySince ?? now
                emptySince = since
                if now.timeIntervalSince(since) > 3 { return PageResult(items: [], next: nil, signedOut: false, ok: true) }
            }
        }
        if view === page { closeView(update: false) }
        return PageResult(items: [], next: nil, signedOut: false, ok: false)
    }

    // Reddit's page loads older notifications from this link as you scroll; fetched
    // from inside the page (its sign-in) and read the same way.
    private func fetchMore(_ url: String) async -> (items: [RedditNotification], next: String?)? {
        guard let page = view else { return nil }
        let body = """
        var r = await fetch(url, {credentials: 'include'});
        var d = new DOMParser().parseFromString(await r.text(), 'text/html');
        return JSON.stringify({items: ilayRead(d), next: ilayNext(d)});
        """
        let value = await withTimeout(12) { done in
            page.callAsyncJavaScript(body, arguments: ["url": url], in: nil, in: .page) { result in
                done(try? result.get())
            }
        }
        guard view === page, let raw = value as? String, let json = parseJsonOrNull(raw) else { return nil }
        return (Self.parse(json), json["next"].str())
    }

    // A new account (or sign-out): its own list, and a fresh page.
    func onUserChanged(_ username: String) {
        if username == user { return }
        user = username
        state = nil
        toMark = []
        markAll = false
        markJob?.cancel()
        closeJob?.cancel()
        closeView(update: false)
    }

    /// The comment a notification link points at (`.../comments/<post>/<slug>/<comment>/`), or nil.
    nonisolated static func commentIdOf(_ link: String) -> String? {
        (commentLinkRe.firstMatch(link) ?? commentPathRe.firstMatch(link))?.groups[1]
    }

    /// The notifications in what the page script read: drops entries without an id or title, and repeats.
    nonisolated static func parse(_ json: JsonElement) -> [RedditNotification] {
        var seen = Set<String>()
        return (json["items"].arr() ?? []).compactMap { e in
            guard let id = e["id"].str(), let title = e["title"].str()?.nilIfEmpty, seen.insert(id).inserted else { return nil }
            return RedditNotification(
                id: id,
                type: e["type"].str() ?? "",
                title: title,
                body: e["body"].str() ?? "",
                link: e["link"].str().flatMap { $0.hasPrefix("http") ? $0 : nil },
                at: e["ts"].str().flatMap { try? Date($0, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true)) }
                    .map { Int(($0.timeIntervalSince1970 * 1000).rounded()) } ?? 0,
                avatar: e["avatar"].str().flatMap { $0.hasPrefix("http") ? $0 : nil },
                clicked: e["clicked"].bool()
            )
        }
    }

    // Each <notification-item>: its link, title, body, time, avatar, and Reddit's
    // clicked flag (in the tracking data of its ⋯ menu, once the page has drawn it);
    // plus the link to the next, older batch. Defines ilayRead / ilayNext on the page
    // for fetchMore to reuse.
    private static let read = #"""
    (function(){
    window.ilayRead=function(root){var out=[];
    root.querySelectorAll('notification-item').forEach(function(e){
      var a=e.querySelector('a[href]');
      var t=e.querySelector('[data-testid=title]');
      var b=e.querySelector('[data-testid=body] > .line-clamp-2');
      var ts=e.querySelector('faceplate-timeago');
      var img=e.querySelector('img');
      var clicked=null;
      try{var m=e.querySelector('notification-context-menu');var tr=m&&m.shadowRoot&&m.shadowRoot.querySelector('faceplate-tracker');
        var ctx=tr&&JSON.parse(tr.getAttribute('data-faceplate-tracking-context'));if(ctx&&ctx.inbox&&typeof ctx.inbox.is_clicked==='boolean')clicked=ctx.inbox.is_clicked;}catch(x){}
      out.push({id:e.getAttribute('notification-id'),type:e.getAttribute('message-type'),
        link:a?a.href:null,title:t?t.textContent.trim():'',body:b?b.textContent.trim():'',
        ts:ts?ts.getAttribute('ts'):null,avatar:img?img.getAttribute('src'):null,clicked:clicked});
    });return out;};
    window.ilayNext=function(root){var p=root.querySelector('faceplate-partial[src*="notifications-inbox-content"]');return p?p.getAttribute('src'):null;};
    return JSON.stringify({login:location.pathname.indexOf('/login')===0||location.hostname.indexOf('accounts.')===0,
      ready:!!document.querySelector('mark-all-messages-read,mark-all-notifications-seen'),items:ilayRead(document),next:ilayNext(document)});
    })()
    """#
}

/// WebKit's rules for the hidden page: Home's skippable media hosts and files, and every
/// image, media file and font.
let redditNotificationBlockRules: String = {
    let skippable = [#"^https?://v\.redd\.it/"#, #"^https?://packaged-media\.redd\.it/"#, #"^https?://fonts\.gstatic\.com/"#]
        + ["mp4", "m3u8", "mpd", "m4s", "ts", "woff", "woff2", "ttf", "webm"].map { #"\.\#($0)([?#].*)?$"# }
    let block: JsonElement = ["type": "block"]
    let rules: [JsonElement] = [["trigger": ["url-filter": ".*", "resource-type": ["image", "media", "font"]], "action": block]]
        + skippable.map { ["trigger": ["url-filter": .string($0)], "action": block] }
    return JsonElement.array(rules).encoded()
}()

private final class HiddenPageDelegate: NSObject, WKNavigationDelegate {
    let onTerminated: () -> Void

    init(onTerminated: @escaping () -> Void) { self.onTerminated = onTerminated }

    // Stay on the list: a clicked item doesn't load its post here.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        action.targetFrame?.isMainFrame == true && action.navigationType == .linkActivated ? .cancel : .allow
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { onTerminated() }
}

private extension Optional {
    func asyncMap<T>(_ transform: (Wrapped) async -> T) async -> T? {
        guard let self else { return nil }
        return await transform(self)
    }
}
