import Foundation
import Observation
import UIKit
import WebKit

/// The page shows the logged-out site: the website session has expired.
struct HomeSignedOutException: LocalizedError {
    var errorDescription: String? { "Your Reddit website sign-in has expired" }
}

/// One post as reddit.com's Home page shows it — enough for a feed card
/// straight away (the full post is fetched in the background).
struct PagePost: Equatable, Sendable {
    let id: String // t3_…
    let title: String
    let subreddit: String
    let subredditIcon: String?
    let author: String
    let score: Int
    let comments: Int
    let createdUtc: Int
    let type: String // text | image | video | gallery | link | crosspost | …
    let permalink: String
    let href: String
    let domain: String
    let image: String?
    let body: String
    let flair: String?
    let nsfw: Bool
    let spoiler: Bool
    /// Reddit's "why you're seeing this", when it shows one.
    let reason: String?
    /// Reddit offers "Show fewer posts like this" for it (recommended posts).
    let canShowFewer: Bool

    /// A feed card's worth of `Post`: replaced by the full post once fetched.
    func toPost() -> Post {
        let bare = id.removePrefix("t3_")
        let sub = subreddit.removePrefix("r/")
        let vreddit = URL(string: href).flatMap { $0.host == "v.redd.it" ? $0.segments.first : nil }
        let postType: PostType = switch type {
        case "text": .selfPost
        case "image": .image
        case "gallery": .gallery
        case "video": .video
        case "link": .link
        default: image != nil ? .image : .selfPost
        }
        return Post(
            id: bare,
            fullname: id,
            title: title,
            subreddit: sub,
            subredditPrefixed: "r/\(sub)",
            subredditIcon: subredditIcon,
            author: author,
            score: score,
            numComments: comments,
            upvoteRatio: 0,
            createdUtc: createdUtc,
            permalink: permalink,
            url: href.isEmpty ? "https://www.reddit.com\(permalink)" : href,
            domain: domain,
            type: postType,
            isSelf: postType == .selfPost,
            selftext: body,
            over18: nsfw,
            spoiler: spoiler,
            linkFlairText: flair,
            // The page's flair is only words.
            linkFlair: flair.map { UserFlair(parts: [FlairPart(text: $0)]) },
            feedReason: reason,
            previewUrl: image,
            previewMedUrl: image,
            hlsUrl: vreddit.map { "https://v.redd.it/\($0)/HLSPlaylist.m3u8" }
        )
    }

    /// "2026-10-05T12:34:56.123000+0000": fractions the formatter refuses, and an offset without a colon.
    private static func millis(_ created: String) -> Int {
        let plain = fraction.replace(created, with: "").replacingOccurrences(of: "+0000", with: "+00:00")
        guard let date = ISO8601DateFormatter().date(from: plain) else { return 0 }
        return Int(date.timeIntervalSince1970 * 1000)
    }

    private static let fraction = Re(#"\.\d+"#)

    /// One post from the page's script, or nil if it isn't a post.
    static func parse(_ o: JsonElement?) -> PagePost? {
        guard let id = o["id"].str(), id.hasPrefix("t3_") else { return nil }
        return PagePost(
            id: id,
            title: (o["title"].str() ?? "").trimmed,
            subreddit: o["sub"].str() ?? "",
            subredditIcon: o["subIcon"].str()?.nilIfEmpty,
            author: o["author"].str()?.nilIfEmpty ?? "[deleted]",
            score: o["score"].str().flatMap { Int($0) } ?? 0,
            comments: o["comments"].str().flatMap { Int($0) } ?? 0,
            createdUtc: millis(o["created"].str() ?? ""),
            type: o["type"].str() ?? "",
            permalink: o["permalink"].str() ?? "",
            href: o["href"].str() ?? "",
            domain: o["domain"].str() ?? "",
            image: o["img"].str()?.nilIfEmpty,
            body: o["body"].str() ?? "",
            flair: o["flair"].str()?.nilIfEmpty,
            nsfw: o["nsfw"].isTrue(),
            spoiler: o["spoiler"].isTrue(),
            reason: o["reason"].str()?.nilIfEmpty,
            canShowFewer: o["fewer"].isTrue()
        )
    }
}

/// What the page shows now: its posts, and whether it's the logged-out site.
struct HomePageRead: Sendable {
    let posts: [PagePost]
    let signedOut: Bool

    /// The page script's JSON result, or nil while a reload is still showing the
    /// previous page. (WKWebView hands a string result back as it is.)
    static func parse(_ result: String?) -> HomePageRead? {
        guard let result, result != "null" else { return nil }
        guard let json = try? AppJson.parse(result) else { return HomePageRead(posts: [], signedOut: false) } // page between documents
        return HomePageRead(posts: (json["posts"].arr() ?? []).compactMap { PagePost.parse($0) }, signedOut: json["signedOut"].isTrue())
    }
}

/// Reads the user's real reddit.com Home feed — Reddit's own ranking and
/// recommendations — by loading the site in a hidden WKWebView with the user's
/// own website session, the way their browser would, and reading the posts the
/// page shows, in order. Promoted posts are skipped.
///
/// EXPERIMENTAL and opt-in (Settings → Reddit Home): this is not an official
/// API. It uses no Reddit app credentials and doesn't disguise itself — it is
/// a browser view of the user's own Home — but automated reading of the site
/// is against Reddit's User Agreement, and it breaks whenever Reddit changes
/// its page. Callers fall back to For You when it yields nothing.
///
/// Every page call runs on the main thread, one at a time (`busy`).
@MainActor
final class RedditHomeLoader: NSObject, WKNavigationDelegate {
    static let home = URL(string: "https://www.reddit.com/")!

    private var view: WKWebView?
    private var cookies: String? // the session the hidden browser was opened with
    private var seen = Set<String>()
    private let busy = AsyncMutex()
    private var running = false // a page call holds `busy`

    /// Opens the page in the hidden browser (tests load a saved copy instead).
    var loadHome: (WKWebView) -> Void = { $0.load(URLRequest(url: RedditHomeLoader.home)) }

    /// Ids (bare) of the posts on the hidden page now that Reddit offers "Show
    /// fewer" for. Only those can take it: a card from an earlier page (one
    /// saved before the app was closed) isn't on this one.
    private(set) var showFewerIds = Set<String>()

    private func locked<T>(_ work: () async throws -> T) async rethrows -> T {
        await busy.lock()
        running = true
        defer {
            running = false
            busy.unlock()
        }
        return try await work()
    }

    /// The next posts: on a `restart` (first page / refresh) the first ~10 as
    /// soon as they render, otherwise up to `want` more. `cookieHeader` is the
    /// active account's session. Throws `HomeSignedOutException` when the page
    /// shows the logged-out site.
    func next(
        restart: Bool,
        cookieHeader: String,
        want: Int = 25,
        onProgress: ((Int) -> Void)? = nil // running count, for the UI
    ) async throws -> [PagePost] {
        try await locked {
            try Task.checkCancellation() // superseded while it waited its turn
            if view == nil || cookieHeader != cookies {
                // First use, or the account changed: (re)open with its session.
                disposeNow()
                seen.removeAll()
                try await open(cookieHeader)
            } else if restart {
                // Refresh: reload the page in the already-open browser instead of
                // tearing it down and re-setting every cookie. Mark the old document so
                // its posts aren't read as the new page's.
                seen.removeAll()
                _ = await eval("document.documentElement.setAttribute('data-ilay-old','1')")
                if let view { loadHome(view) }
            }
            attachToWindow()

            // A refresh hands back the first posts as soon as they render; the feed
            // pages for more on its own as you scroll.
            let target = restart ? 10 : want
            var fresh: [PagePost] = []
            let deadline = nowMillis() + 15_000
            var lastGrowth = nowMillis()
            var lastScroll = 0
            while nowMillis() < deadline {
                let page = await read()
                if page?.signedOut == true { throw HomeSignedOutException() }
                if let page { showFewerIds = Set(page.posts.filter(\.canShowFewer).map { $0.id.removePrefix("t3_") }) }
                var grew = false
                for p in page?.posts ?? [] where seen.insert(p.id).inserted {
                    fresh.append(p)
                    grew = true
                }
                if grew { onProgress?(fresh.count) }
                if fresh.count >= target { break }
                let now = nowMillis()
                if grew { lastGrowth = now }
                // Nothing new for a while after posts had appeared: end of the feed.
                // (Before any appear, the page is still loading — keep waiting.) Once
                // a batch has been flowing, a shorter quiet spell is enough.
                let quiet = fresh.isEmpty ? 6_000 : 4_000
                if !seen.isEmpty && now - lastGrowth >= quiet { break }
                // Out of rendered posts: scroll so the page loads its next batch, at
                // most every second.
                if page != nil && !seen.isEmpty && !grew && now - lastScroll >= 1_000 {
                    lastScroll = now
                    _ = await eval("window.scrollTo(0, document.body.scrollHeight);")
                }
                // Check often: posts appear well before the whole page has loaded.
                try await Task.sleep(for: .milliseconds(100))
            }
            return fresh
        }
    }

    /// Scrolls the hidden page to `postId` (what the user is looking at in Ilay),
    /// so Reddit's own "seen" tracking follows what was actually on screen.
    /// Skipped while a page load is running.
    func scrollTo(_ postId: String) async {
        if running { return }
        await locked {
            _ = await eval("(function(){var e=document.getElementById('\(postId)');if(e)e.scrollIntoView({block:'center'});})()")
        }
    }

    /// The script for one try of `showFewer`.
    nonisolated static func showFewerScript(_ postId: String, attempt: Int) -> String {
        """
        (function(){
          var p = document.getElementById('\(postId)');
          var m = p && p.querySelector('shreddit-post-overflow-menu');
          if (!m) return 'gone';
          var li = m.shadowRoot && m.shadowRoot.querySelector('#post-overflow-showFewer');
          if (!li) {
            var b = (m.shadowRoot && m.shadowRoot.querySelector('button')) || m.querySelector('button');
            if (b && \(attempt) === 0) b.click();
            return 'none';
          }
          (li.querySelector('[role="menuitem"]') || li).click();
          return 'ok';
        })()
        """
    }

    /// Picks "Show fewer posts like this" in the post's own ⋯ menu on the hidden
    /// page — the same action as on reddit.com. False if it isn't offered there.
    func showFewer(_ postId: String) async -> Bool {
        await locked {
            // The menu's items may only be rendered once it has been opened:
            // open it (off screen, in the hidden page) and look again.
            for attempt in 0..<4 {
                let r = await eval(Self.showFewerScript(postId, attempt: attempt)) as? String
                if r == "ok" { return true }
                if r == "gone" { return false }
                try? await Task.sleep(for: .milliseconds(400))
            }
            return false
        }
    }

    /// The app went to the background: stop the hidden page's media. iOS suspends the
    /// page's process and its timers itself soon after. (Flutter's pauseTimers blocks the
    /// page's JavaScript thread on an `alert()` it never answers: scripts sent meanwhile
    /// would hang until their timeout, for nothing iOS doesn't already do.)
    func pause() { view?.setAllMediaPlaybackSuspended(true) }

    func resume() { view?.setAllMediaPlaybackSuspended(false) }

    // Video and fonts: Only downloads that never change what the feed shows.
    // Reddit's own events must go through — Home learns from them which posts were
    // seen, and without them a refresh kept serving the same feed. Images: Ilay loads
    // its own for the cards; the hidden page doesn't need to download any, which gets
    // its posts on screen sooner. (Patterns are WebKit's regex subset: no `|`.)
    nonisolated static let blockRules: String = {
        let urls = [
            #"^https?://v\.redd\.it/"#,
            #"^https?://packaged-media\.redd\.it/"#,
            #"^https?://fonts\.gstatic\.com/"#,
        ] + ["mp4", "m3u8", "mpd", "m4s", "ts", "woff", "woff2", "ttf", "webm"].map { #"\.\#($0)([?#].*)?$"# }
        var rules = urls.map { ["trigger": ["url-filter": $0], "action": ["type": "block"]] as [String: Any] }
        rules.append(["trigger": ["url-filter": ".*", "resource-type": ["image"]], "action": ["type": "block"]])
        let data = try! JSONSerialization.data(withJSONObject: rules)
        return String(decoding: data, as: UTF8.self)
    }()

    private static var compiledRules: WKContentRuleList?

    /// The hidden browser's setup. Same cookie jar as sign-in (the default data store).
    static func configuration() async -> WKWebViewConfiguration {
        if compiledRules == nil {
            compiledRules = try? await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "IlayRedditHome", encodedContentRuleList: blockRules)
        }
        let config = WKWebViewConfiguration()
        // A video the page starts mustn't take the audio session and pause the user's music.
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.allowsInlineMediaPlayback = true
        if let compiledRules { config.userContentController.add(compiledRules) }
        return config
    }

    private func open(_ cookieHeader: String) async throws {
        cookies = cookieHeader
        // Creating the first WKWebView starts WebKit on the main thread: let the app's
        // first frames and the loading deck draw before that.
        try await Task.sleep(for: .milliseconds(100))
        await loadWebSessionCookies(cookieHeader)

        let v = WKWebView(frame: CGRect(x: 0, y: 0, width: 402, height: 874), configuration: await Self.configuration())
        v.navigationDelegate = self
        view = v
        attachToWindow()
        // Don't wait for the whole page to load: next() reads posts as soon as
        // they're in the page.
        loadHome(v)
    }

    /// WKWebView is unreliable off screen on a device (JavaScript sometimes simply doesn't
    /// run, and nothing lazy-loads), so the page lives in the window, under everything,
    /// practically transparent: a real viewport, so "scroll to bottom" loads more.
    private func attachToWindow() {
        guard let view, view.superview == nil else { return }
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        guard let window = windows.first(where: \.isKeyWindow) ?? windows.first else { return }
        view.alpha = 0.01
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        view.frame = window.bounds
        window.insertSubview(view, at: 0)
    }

    /// The page's process died (crashed, or killed for memory): drop this page, and the
    /// next Home load opens a new one.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if view === webView {
            view = nil
            cookies = nil
        }
        webView.removeFromSuperview()
    }

    private func eval(_ js: String) async -> Any? {
        guard let v = view else { return nil }
        // While the page is reloading, the WebView can drop a script's result
        // callback entirely; without a timeout that hung a refresh forever on
        // "Opening your Home…" (the deadline check never ran again).
        return await withCheckedContinuation { (cont: CheckedContinuation<Any?, Never>) in
            var done = false
            func finish(_ result: Any?) {
                if done { return }
                done = true
                cont.resume(returning: result)
            }
            v.evaluateJavaScript(js) { result, _ in finish(result) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { finish(nil) }
        }
    }

    /// The posts on the page now, or nil while a reload is still showing the previous page.
    private func read() async -> HomePageRead? {
        let result = await eval(Self.readPosts) as? String
        // This runs ten times a second while the user scrolls: off the main thread.
        return await Task.detached { HomePageRead.parse(result) }.value
    }

    private func disposeNow() {
        let v = view
        view = nil
        cookies = nil
        showFewerIds = []
        v?.stopLoading()
        v?.navigationDelegate = nil
        v?.removeFromSuperview()
    }

    func dispose() async { await locked { disposeNow() } }

    // The feed's posts, in page order, as cards: Reddit's site renders each
    // post as a <shreddit-post id="t3_…" post-title=… score=…> with its body
    // snippet, media preview and flair in named slots, and the
    // recommendation reason / "Show fewer" option on its ⋯ menu. Ads are
    // separate elements. signedOut: the page is the logged-out site (the
    // session expired). Returns null while the previous document is still
    // showing during a reload. (Element and attribute names as of 2026-10.)
    nonisolated static let readPosts = """
    (function () {
      if (document.documentElement.getAttribute('data-ilay-old')) return null;
      var app = document.querySelector('shreddit-app');
      var signedOut = !!app && app.getAttribute('user-logged-in') !== 'true';
      var posts = Array.from(document.querySelectorAll('shreddit-post'))
        .filter(function (e) { return !e.hasAttribute('promoted') && (e.id || '').indexOf('t3_') === 0; })
        .map(function (e) {
          function slot(n) { return e.querySelector('[slot="' + n + '"]'); }
          var media = slot('post-media-container');
          var img = media && media.querySelector('img');
          var body = slot('text-body');
          var flair = slot('post-flair');
          var credit = slot('credit-bar');
          var subIcon = credit && credit.querySelector('img');
          var menu = e.querySelector('shreddit-post-overflow-menu');
          var reason = '', fewer = false;
          try {
            var rc = JSON.parse((menu && menu.getAttribute('recommendation-context-json')) || '{}');
            // Recommended (not from a subscription): Reddit offers "Show fewer" on these.
            fewer = !!(rc && rc.recommendationSource) && rc.recommendationSource.indexOf('subscribed') !== 0;
            if (rc && rc.content && !rc.isContextHidden) {
              var doc = JSON.parse(rc.content.richtext || '{}').document || [];
              reason = doc.map(function (p) { return (p.c || []).map(function (c) { return c.t || ''; }).join(''); }).join(' ').trim();
            }
          } catch (x) {}
          return {
            id: e.id, title: e.getAttribute('post-title') || '',
            sub: e.getAttribute('subreddit-prefixed-name') || '', author: e.getAttribute('author') || '',
            subIcon: subIcon ? (subIcon.getAttribute('src') || '') : '',
            score: e.getAttribute('score') || '0', comments: e.getAttribute('comment-count') || '0',
            created: e.getAttribute('created-timestamp') || '', type: e.getAttribute('post-type') || '',
            permalink: e.getAttribute('permalink') || '', href: e.getAttribute('content-href') || '',
            domain: e.getAttribute('domain') || '',
            img: img ? (img.getAttribute('src') || '') : '',
            body: body ? (body.innerText || '').trim().slice(0, 400) : '',
            flair: flair ? (flair.innerText || '').trim() : '',
            nsfw: e.hasAttribute('nsfw'), spoiler: e.hasAttribute('spoiler'),
            reason: reason, fewer: fewer
          };
        });
      return JSON.stringify({ signedOut: signedOut, posts: posts });
    })();
    """
}

/// One Blend read of your Reddit Home.
enum BlendResult: Sendable {
    /// Full posts, in Reddit's order.
    case posts([Post])
    /// Home had nothing new this time (the page may still be setting up).
    case empty
    /// A network or page error: worth trying again on the next page.
    case failed
    /// No website sign-in, or it expired: Blend is For You until you sign in.
    case signedOut
}

/// A Blend read in progress: a page may stop waiting for it (it keeps going, and the next page takes it).
@MainActor
final class BlendBatch {
    fileprivate(set) var result: BlendResult?
    fileprivate var task: Task<Void, Never>?
}

/// Experimental Reddit Home (hidden WKWebView), falling back to For You.
@MainActor @Observable
final class RedditHomeEngine {
    @ObservationIgnored private let c: AppContainer
    @ObservationIgnored private unowned let m: ForYouModule

    /// Posts found so far while the first page loads (for the loading deck).
    private(set) var progress = 0

    /// What the Home feed shows now (live, saved page, For You fallback); nil before the first load.
    var status: HomeStatus?

    /// What Blend's Home source is doing, for the Blend header.
    var blendState: BlendState?

    /// Post ids (bare) Reddit offers "Show fewer posts like this" for.
    private(set) var showFewerIds = Set<String>()

    /// Full posts for cards first shown from the page alone (the feed swaps
    /// them in by id, keeping its order).
    @ObservationIgnored var onUpgrades: (([Post]) -> Void)?

    @ObservationIgnored private var loader: RedditHomeLoader?

    // This load fell back to For You (Reddit Home couldn't be read); paging
    // continues with For You until the next refresh.
    @ObservationIgnored private var fellBack = false
    @ObservationIgnored private var loadGen = 0 // bumped by each first-page Home load
    @ObservationIgnored private var homeEmpty = 0 // consecutive empty "more" batches from Reddit Home

    // The next batch, read ahead while the user scrolls the current one.
    @ObservationIgnored private var prefetch: Task<[PagePost], Error>?
    @ObservationIgnored private var viewJob: Task<Void, Never>?

    // Blend reads run on their own (a page may stop waiting for one; it
    // keeps going and the next page takes it), so they're tracked here and
    // cancelled on refresh, when the feed closes and on account changes; a
    // result from before that (`blendGen`) is thrown away.
    @ObservationIgnored private var blendGen = 0
    @ObservationIgnored private var blendPending: BlendBatch? // being read for the next page
    @ObservationIgnored private var blendActive: BlendBatch? // handed to the page being built

    init(_ c: AppContainer, _ m: ForYouModule) {
        self.c = c
        self.m = m
    }

    func page(after: String?, loaded: [Post]) async throws -> Listing<Post> {
        if after == nil { fellBack = false }
        return fellBack ? try await m.engine.page(after: after, loaded: loaded) : try await homePage(after, loaded)
    }

    private func homePage(_ after: String?, _ loaded: [Post]) async throws -> Listing<Post> {
        let firstPage = after == nil
        let started = nowMillis()
        do {
            if await c.secureStore.authMode() != "web" { throw AppException("Reddit Home needs website sign-in") }
            // With a current token_v2: an expired one fails the first load after a while away.
            let cookie = await c.client.freshWebCookie() ?? ""
            let l = openLoader()
            if firstPage {
                loadGen += 1
                progress = 0
                prefetch?.cancel()
                prefetch = nil
            }
            let page: [PagePost]
            if firstPage {
                page = try await l.next(restart: true, cookieHeader: cookie, onProgress: { [weak self] n in self?.progress = n })
            } else if let ahead = prefetch, !ahead.isCancelled, let batch = try? await ahead.value {
                page = batch
            } else {
                page = try await l.next(restart: false, cookieHeader: cookie)
            }
            prefetch = nil
            if page.isEmpty {
                if firstPage { throw AppException("No posts found on Reddit Home") }
                // One empty batch can just be the page still setting up its "load
                // more"; only two in a row end the feed.
                homeEmpty += 1
                return Listing(items: [], after: homeEmpty >= 2 ? nil : "home")
            }
            homeEmpty = 0
            showFewerIds = l.showFewerIds
            // Cards straight from the page (no wait for the API); the full posts
            // (media, video, flair, NSFW) follow in the background.
            let cards = page.map { $0.toPost() }
            let gen = loadGen
            Task { await upgrade(page, firstPage: firstPage, gen: gen) }
            // Read the next batch ahead, so reaching the end doesn't wait.
            prefetch = Task { try await l.next(restart: false, cookieHeader: cookie) }
            if firstPage {
                trackLoad("ok", posts: cards.count, started: started)
                status = .live(at: nowMillis())
            }
            return Listing(items: cards, after: "home")
        } catch {
            if error is CancellationError || Task.isCancelled { throw error }
            if !firstPage { throw error } // a failed page keeps its cursor; retry
            // Reddit changed its page, the session expired, or the site refused:
            // show For You rather than an empty feed, and say so.
            fellBack = true
            let signedOut = error is HomeSignedOutException
            trackLoad(signedOut ? "signin_expired" : "fell_back", posts: 0, started: started)
            status = .fellBack(signedOut: signedOut)
            return try await m.engine.page(after: nil, loaded: loaded)
        }
    }

    private func openLoader() -> RedditHomeLoader {
        if let loader { return loader }
        let new = RedditHomeLoader()
        loader = new
        return new
    }

    /// Stops every Blend read (refresh, feed closed, account change).
    func cancelBlend() {
        blendGen += 1
        blendPending?.task?.cancel()
        blendActive?.task?.cancel()
        blendPending = nil
        blendActive = nil
    }

    private func startBlend(first: Bool) -> BlendBatch {
        let gen = blendGen
        let batch = BlendBatch()
        batch.task = Task { [weak batch] in
            let result = await blendCandidates(first: first, gen: gen)
            batch?.result = result
        }
        return batch
    }

    /// The Home read for this page: a fresh one on the first page (older reads
    /// are cancelled), else the one already loading in the background.
    func blendBatch(first: Bool) -> BlendBatch {
        if first { cancelBlend() }
        let pending = blendPending
        blendPending = nil
        let batch = !first ? pending ?? startBlend(first: first) : startBlend(first: first)
        blendActive = batch
        return batch
    }

    /// The page stopped waiting for `batch`: the next page takes it.
    func blendKeep(_ batch: BlendBatch) {
        blendPending = batch
    }

    /// A batch arrived: start reading the next one now, so the next page doesn't wait.
    func blendPrefetch() {
        blendPending = startBlend(first: false)
    }

    /// One read of your Reddit Home as full posts (Reddit's "why" kept as
    /// their reason), for For You to rank with everything else.
    private func blendCandidates(first: Bool, gen: Int) async -> BlendResult {
        let user = c.session.username
        do {
            if await c.secureStore.authMode() != "web" { return .signedOut }
            // With a current token_v2: an expired one fails the first load after a while away.
            let cookie = await c.client.freshWebCookie() ?? ""
            let l = openLoader()
            let page = try await l.next(restart: first, cookieHeader: cookie)
            if gen != blendGen || c.session.username != user { return .failed } // superseded
            if page.isEmpty { return .empty }
            showFewerIds = l.showFewerIds
            let full = try await c.repository.getPostsByIds(page.map(\.id))
            if gen != blendGen || c.session.username != user { return .failed }
            return .posts(withReasons(full, page))
        } catch is HomeSignedOutException {
            return .signedOut
        } catch {
            return .failed
        }
    }

    /// `full`, each keeping the reason Reddit's page gave for it.
    private func withReasons(_ full: [Post], _ page: [PagePost]) -> [Post] {
        var reasons: [String: String] = [:]
        for p in page { reasons[p.id.removePrefix("t3_")] = p.reason }
        return full.map { p in reasons[p.id].map { r in p.with { $0.feedReason = r } } ?? p }
    }

    /// Anonymous: whether a Home load worked, how many posts and how long (coarse ranges).
    private func trackLoad(_ outcome: String, posts: Int, started: Int) {
        let ms = nowMillis() - started
        let seconds = ms < 2_000 ? "<2" : ms < 5_000 ? "2-5" : ms < 10_000 ? "5-10" : "10+"
        Analytics.track("home_loaded", ["outcome": .string(outcome), "posts": .string(Analytics.bucket(posts, 0, 9)), "seconds": .string(seconds)])
    }

    /// Fetches the full posts for `page` and hands them to the feed.
    private func upgrade(_ page: [PagePost], firstPage: Bool, gen: Int) async {
        // The account these cards belong to: a switch mid-request must not give
        // its posts (or its saved Home page) to the next account. Likewise a
        // newer Home load (`gen`) makes these cards old: an upgrade finishing
        // after it must not overwrite the newer cards or saved page.
        let user = c.session.username
        func stale() -> Bool { c.session.username != user || gen != loadGen }
        // A failed fetch left cards without media (empty galleries); try again
        // a couple of times before leaving them as they are.
        var full: [Post]?
        for wait in [0, 2_000, 5_000] {
            try? await Task.sleep(for: .milliseconds(wait))
            full = try? await c.repository.getPostsByIds(page.map(\.id))
            if full != nil || stale() { break }
        }
        guard let full, !stale() else { return }
        let posts = withReasons(full, page)
        onUpgrades?(posts)
        if firstPage && !user.isEmpty {
            let repo = c.repository
            Task.detached { await saveForYouPage(user: user, posts: posts, raw: { repo.rawPost($0) }, feed: "home") }
        }
    }

    /// The user is looking at `postId` in Ilay: follow it in the hidden page so
    /// Reddit's "seen" tracking matches (debounced; skipped while loading).
    func viewing(_ postId: String) {
        guard let l = loader else { return }
        viewJob?.cancel()
        viewJob = Task {
            try? await Task.sleep(for: .milliseconds(800))
            if Task.isCancelled { return }
            await l.scrollTo("t3_\(postId)")
        }
    }

    /// "Show fewer posts like this" on reddit.com for `post`. True if Reddit took it.
    func showFewer(_ post: Post) async -> Bool {
        guard let l = loader else { return false }
        let ok = await l.showFewer(post.fullname)
        showFewerIds.remove(post.id)
        return ok
    }

    /// The app went to the background / came back: pause the hidden page meanwhile.
    func onAppBackground() { loader?.pause() }

    func onAppForeground() { loader?.resume() }

    /// The last Home page, minus posts opened since, while the fresh one loads.
    func cachedFirstPage() async -> Listing<Post>? {
        let user = c.session.username
        if user.isEmpty { return nil }
        guard let posts = await loadForYouPage(user: user, opened: c.history.ids, feed: "home") else { return nil }
        return Listing(items: posts, after: nil)
    }

    func cachedFirstPageTime() async -> Int? {
        let user = c.session.username
        return user.isEmpty ? nil : await savedPageTime(user: user, feed: "home")
    }

    /// Closes the hidden browser (the feed went away).
    func dispose() {
        cancelBlend()
        prefetch?.cancel()
        prefetch = nil
        showFewerIds = []
        guard let l = loader else { return }
        loader = nil
        Task { await l.dispose() }
    }
}
