import SwiftUI
import WebKit

/// Reddit pages Ilay opens signed in (website sign-in only).
enum RedditWeb {
    static let chat = "https://chat.reddit.com/"
    static let settings = "https://www.reddit.com/settings"

    /// Pages that stay in the WebView; any other site goes to the browser.
    /// No host (about:blank) counts as Reddit.
    static func isReddit(_ uri: URL) -> Bool {
        guard let host = uri.host?.lowercased() else { return true }
        return host == "reddit.com" || host.hasSuffix(".reddit.com") || host.hasSuffix(".redditmedia.com")
            || host.hasSuffix(".redditstatic.com") || host == "redd.it"
    }
}

/// Reddit sizes Chat to 100dvh, which a WebView can report as 0 (a blank page);
/// and its "Skip to …" links show up as a stuck pill.
private let fixCss = #"""
(function(){if(document.getElementById('ilay-fix'))return;var s=document.createElement('style');s.id='ilay-fix';s.textContent='reddit-chat-fullscreen{height:auto!important}a[href="#main-content"],a[href="#main-right-content"]{display:none!important}';document.head.appendChild(s)})()
"""#

/// A reddit.com page signed in as you (website sign-in): notifications, chat,
/// a poll, Reddit's settings. Links to posts, profiles and communities open
/// in Ilay instead; other sites open in the browser. Its own WebView, so
/// Home's hidden page (and its place) is left alone.
struct RedditWebScreen: View {
    let url: String
    let title: String

    @Environment(AppNavigator.self) private var nav
    // nil while loading the session into the cookie jar; false = not signed in on the web.
    @State private var ready: Bool?
    @State private var page = RedditWebPage()

    var body: some View {
        ZStack(alignment: .top) {
            if ready == nil {
                Loading().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if ready == false || page.crashed {
                ContentUnavailableView {
                    Image(systemName: "safari")
                } description: {
                    Text(page.crashed ? "The page stopped working." : "This page needs the website sign-in (Settings → Login method).")
                } actions: {
                    Button("Open in browser") { nav.openInBrowser(url) }.buttonStyle(.glass)
                }
            } else {
                WebPageView(page: page, url: url)
                    .ignoresSafeArea(edges: .bottom)
                if page.progress > 0, page.progress < 1 {
                    ProgressView(value: page.progress).progressViewStyle(.linear)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if page.canGoBack {
                    Button("Previous page", systemImage: "chevron.backward") { page.web?.goBack() }
                }
                Button("Reload", systemImage: "arrow.clockwise") { page.web?.reload() }
                Button("Open in browser", systemImage: "arrow.up.right.square") {
                    nav.openInBrowser(page.web?.url?.absoluteString ?? url)
                }
            }
        }
        .task {
            let cookie = await app.secureStore.authMode() == "web" ? await app.secureStore.webCookie() : nil
            guard let cookie, !cookie.isEmpty else {
                ready = false
                return
            }
            await loadWebSessionCookies(cookie)
            ready = true
        }
    }
}

@MainActor @Observable
private final class RedditWebPage: NSObject, WKNavigationDelegate, WKUIDelegate {
    @ObservationIgnored var web: WKWebView?
    @ObservationIgnored private var observers: [NSKeyValueObservation] = []
    @ObservationIgnored private var startRoute: Route?
    var progress = 0.0
    var canGoBack = false
    var crashed = false

    func makeWebView(url: String) -> WKWebView {
        if let web { return web }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default() // The jar loadWebSessionCookies fills.
        let web = WKWebView(frame: .zero, configuration: config)
        web.customUserAgent = RedditConstants.webUserAgent
        web.allowsBackForwardNavigationGestures = true
        web.navigationDelegate = self
        web.uiDelegate = self
        observers = [
            web.observe(\.estimatedProgress) { [weak self] web, _ in
                MainActor.assumeIsolated { self?.progress = web.estimatedProgress }
            },
            web.observe(\.canGoBack) { [weak self] web, _ in
                MainActor.assumeIsolated { self?.canGoBack = web.canGoBack }
            },
            // Reddit's pages switch "pages" in-place (no load to intercept):
            // catch a move to a post the same way, and step back.
            web.observe(\.url) { [weak self] web, _ in
                MainActor.assumeIsolated {
                    guard let self, let now = web.url else { return }
                    if self.openNatively(now), web.canGoBack { web.goBack() }
                }
            },
        ]
        self.web = web
        let start = URL(string: url)
        startRoute = start.flatMap(routeForRedditUrl)
        if let start { web.load(URLRequest(url: start)) }
        return web
    }

    /// A post / profile / community link opens natively (not the page you came for).
    private func openNatively(_ uri: URL) -> Bool {
        guard let route = routeForRedditUrl(uri), route != startRoute else { return false }
        app.navigator.push(route)
        return true
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        // A nil target frame is a new window, which `createWebViewWith` keeps in this one.
        guard action.targetFrame?.isMainFrame != false, let u = action.request.url else { return .allow }
        if openNatively(u) { return .cancel }
        if u.scheme == "http" || u.scheme == "https" {
            if RedditWeb.isReddit(u) { return .allow }
            app.navigator.openInBrowser(u)
        }
        return .cancel // mailto: and other app links
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript(fixCss)
    }

    // The web process died: drop the page.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        crashed = true
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }
}

private struct WebPageView: UIViewRepresentable {
    let page: RedditWebPage
    let url: String

    func makeUIView(context: Context) -> WKWebView { page.makeWebView(url: url) }
    func updateUIView(_ web: WKWebView, context: Context) {}
}
