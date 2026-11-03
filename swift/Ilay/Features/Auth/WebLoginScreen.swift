import SwiftUI
import WebKit

/// The `Cookie` header for reddit.com from the jar, once it holds a session:
/// the cookies a request to www.reddit.com would send (not chat.reddit.com's),
/// or nil while `reddit_session` is missing or empty.
func webSessionHeader(_ cookies: [HTTPCookie]) -> String? {
    let host = URL(string: RedditConstants.webApiBase)!.host!
    let sent = cookies.filter { c in
        let domain = c.domain.lowercased()
        let applies = domain.hasPrefix(".") ? host == domain.dropFirst() || host.hasSuffix(domain) : host == domain
        return applies && (c.path == "/" || c.path.isEmpty)
    }
    guard sent.contains(where: { $0.name == "reddit_session" && !$0.value.isEmpty }) else { return nil }
    return sent.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
}

/// A WebView that signs the user into reddit.com, captures the resulting
/// session cookies and logs in with them. This is the no-API-key "website
/// session" login — see docs/hydra-fallback.md. The user's password is only
/// ever entered into Reddit's own page inside the WebView.
///
/// With [clearFirst] (used by "add account") existing cookies are wiped first,
/// so you can sign into a *different* account — otherwise the session check
/// finds the *current* account's reddit_session straight away and adds that
/// account again.
struct WebLoginScreen: View {
    let clearFirst: Bool

    @Environment(AppNavigator.self) private var nav
    @State private var ready: Bool
    @State private var done = false
    @State private var signingIn = false
    // Bumped when the page's renderer dies: a new WebView reloads the sign-in page.
    @State private var page = 0

    init(clearFirst: Bool = false) {
        self.clearFirst = clearFirst
        _ready = State(initialValue: !clearFirst)
    }

    var body: some View {
        ZStack {
            if ready {
                LoginWebView(clearCache: clearFirst, onPageFinished: { Task { await check() } }, onCrash: { page += 1 })
                    .id(page)
                    .ignoresSafeArea(edges: .bottom)
            }
            if !ready || signingIn { Loading() }
        }
        .navigationTitle("Sign in to Reddit")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close", systemImage: "xmark") { nav.pop() }
            }
        }
        .task {
            if clearFirst {
                let store = WKWebsiteDataStore.default()
                for cookie in await store.httpCookieStore.allCookies() {
                    await store.httpCookieStore.deleteCookie(cookie)
                }
                ready = true
            }
            // The session cookie can appear without a page load finishing (XHR login).
            while !done, !Task.isCancelled {
                await check()
                try? await Task.sleep(for: .milliseconds(700))
            }
        }
    }

    private func check() async {
        if done { return }
        guard let header = webSessionHeader(await WKWebsiteDataStore.default().httpCookieStore.allCookies()) else { return }
        if done { return }
        done = true
        signingIn = true
        // Its own task: leaving this screen mustn't abandon a login under way.
        Task {
            do {
                try await app.session.loginWithWebSession(cookie: header)
                // Signed out before: the root moves to Home by itself. Adding an
                // account: just close this screen.
                if clearFirst { nav.pop() }
            } catch {
                let message = error.localizedDescription
                nav.showSnackbar(clearFirst ? "Could not add account: \(message)" : message)
                nav.pop()
            }
        }
    }
}

private struct LoginWebView: UIViewRepresentable {
    let clearCache: Bool
    let onPageFinished: () -> Void
    let onCrash: () -> Void

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: LoginWebView

        init(_ parent: LoginWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { parent.onPageFinished() }

        // Unhandled, a dead web process leaves a blank page.
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { parent.onCrash() }

        // "Continue with…" pages opening a new window: stay in this one, as Android's WebView does.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
            return nil
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let web = WKWebView(frame: .zero, configuration: config)
        web.customUserAgent = RedditConstants.webUserAgent
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        var request = URLRequest(url: URL(string: RedditConstants.webLoginUrl)!)
        if clearCache { request.cachePolicy = .reloadIgnoringLocalCacheData }
        web.load(request)
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) { context.coordinator.parent = self }
}
