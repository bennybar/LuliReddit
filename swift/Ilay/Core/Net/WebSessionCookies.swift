import Foundation
import WebKit

/// Puts the active website session ([cookieHeader]) in the WebView cookie jar,
/// which every WebView shares (hidden Home, signed-in pages). The jar may hold
/// a different account's session (the last one that signed in through it).
@MainActor
func loadWebSessionCookies(_ cookieHeader: String) async {
    let jar = WKWebsiteDataStore.default().httpCookieStore
    let inJar = await jar.allCookies().filter { isRedditHost($0.domain.trimming(".")) }
    let session = inJar.first { $0.name == "reddit_session" }?.value
    // Same account already in the jar: keep it as is. Wiping it also threw
    // away the cookies Reddit set when the page passed its browser check,
    // so every launch had to pass that check again (an extra page load).
    if session == cookieValue(cookieHeader, "reddit_session") { return }
    for c in inJar { await jar.deleteCookie(c) }
    for part in cookieHeader.components(separatedBy: ";") {
        guard let i = part.firstIndex(of: "="), i > part.startIndex else { continue }
        let name = String(part[..<i]).trimmed
        let value = String(part[part.index(after: i)...]).trimmed
        guard let cookie = HTTPCookie(properties: [
            .domain: ".reddit.com", .path: "/", .name: name, .value: value, .secure: "TRUE",
        ]) else { continue }
        await jar.setCookie(cookie)
    }
}
