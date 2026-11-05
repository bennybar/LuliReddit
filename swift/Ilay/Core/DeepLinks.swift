import Foundation

/// True for reddit.com / *.reddit.com / redd.it / *.redd.it (media) hosts.
func isRedditHost(_ host: String?) -> Bool {
    guard let h = host?.lowercased() else { return false }
    return h == "redd.it" || h.hasSuffix(".redd.it") || h == "reddit.com" || h.hasSuffix(".reddit.com")
}

private let sharedUrlRe = Re(#"https?://[^\s<>"]+"#)

/// The first reddit.com / redd.it link in shared text. Apps share a post as
/// the bare URL or as "title https://…", sometimes with trailing punctuation.
func redditUrlInText(_ text: String?) -> String? {
    guard let text else { return nil }
    return sharedUrlRe.allMatches(text)
        .map { $0.value.trimmingEnd(".,)!?") }
        .first { isRedditHost(URL(string: $0)?.host) }
}

/// Reddit's media hosts (i.redd.it, v.redd.it, preview.redd.it…): open in the image / video viewer.
func isRedditMediaHost(_ host: String?) -> Bool { host?.lowercased().hasSuffix(".redd.it") == true }

/// A share link (`reddit.com/r/<sub>/s/<code>`, or `/u/<name>/s/<code>` for a custom feed): it only redirects to the real post / comment / feed URL.
func isShareLink(_ uri: URL) -> Bool {
    if !isRedditHost(uri.host) { return false }
    let s = uri.segments
    return s.count >= 4 && (s[0] == "r" || s[0] == "u" || s[0] == "user") && s[2] == "s"
}

/// Follows a [isShareLink] URL's redirects (up to 3) to the link it stands for; nil if it can't.
func resolveShareLink(_ uri: URL) async -> URL? {
    var url = uri
    func location(head: Bool) async -> String? {
        var req = URLRequest(url: url)
        req.setValue(RedditConstants.webUserAgent, forHTTPHeaderField: "User-Agent")
        if head { req.httpMethod = "HEAD" }
        guard let (_, res) = try? await Http.noRedirects.data(for: req), let http = res as? HTTPURLResponse else { return nil }
        return http.value(forHTTPHeaderField: "location")
    }
    for _ in 0..<3 {
        // HEAD first (no body); some servers only redirect a GET.
        var next = await location(head: true)
        if next == nil { next = await location(head: false) }
        guard let next else { return nil }
        let target = next.hasPrefix("/") ? "https://www.reddit.com\(next)" : next
        guard let u = URL(string: target) else { return nil }
        if !isShareLink(u) { return u }
        url = u
    }
    return nil
}

/// The in-app post a link to a Reddit post opens — a permalink, relative
/// (`/r/…/comments/…`, `/user/…/comments/…`, a crosspost's own url) or on reddit.com,
/// or a redd.it short link — or nil for any other link.
func redditPostRoute(_ url: String) -> Route? {
    guard let uri = URL(string: url.hasPrefix("/") ? "https://www.reddit.com\(url)" : url),
          let route = routeForRedditUrl(uri), case .post = route else { return nil }
    return route
}

/// What a link card says for a link to a Reddit post (opened in Ilay, not the
/// browser): where it was crossposted from, when the link says.
func redditLinkLabel(_ p: Post, _ route: Route) -> String {
    if p.crosspostParent != nil, case let .post(sub, _, _) = route, sub != "_" { return "Crossposted from \(crosspostSource(sub))" }
    return "Reddit post"
}

/// Maps a reddit.com / redd.it URL to an in-app route, or nil if unsupported.
func routeForRedditUrl(_ uri: URL) -> Route? {
    guard let host = uri.host?.lowercased() else { return nil }
    let segs = uri.segments

    // Short links: redd.it/<postId>
    if host == "redd.it" { return segs.first.map { .post(subreddit: "_", postId: $0) } }
    if !(host == "reddit.com" || host.hasSuffix(".reddit.com")) { return nil }

    // Comment / post permalinks: /r/<sub>/comments/<id>/<slug>/<commentId> or
    // /comments/<id>. A segment after the title slug is a focused comment.
    if let ci = segs.firstIndex(of: "comments"), ci + 1 < segs.count {
        let id = segs[ci + 1]
        let sub = ci >= 2 && segs[ci - 2] == "r" ? segs[ci - 1] : "_"
        let commentId = segs.count > ci + 3 ? segs[ci + 3] : nil
        return .post(subreddit: sub, postId: id, focusCommentId: commentId)
    }

    // Gallery: /gallery/<id> is the post itself.
    if segs.count >= 2, segs[0] == "gallery" { return .post(subreddit: "_", postId: segs[1]) }
    // A share link must be resolved first (resolveShareLink): /r/<sub>/s/<code>
    // is a post, not the subreddit; /u/<name>/s/<code> a custom feed, not the user.
    if segs.count >= 4, segs[0] == "r" || segs[0] == "u" || segs[0] == "user", segs[2] == "s" { return nil }

    // Multireddit: /user/<name>/m/<multi>
    if segs.count >= 4, segs[0] == "user" || segs[0] == "u", segs[2] == "m" {
        return .multireddit(username: segs[1], name: segs[3])
    }
    // User: /u/<name> or /user/<name>
    if segs.count >= 2, segs[0] == "u" || segs[0] == "user" { return .user(username: segs[1]) }
    // Subreddit: /r/<sub>
    if segs.count >= 2, segs[0] == "r" { return .subreddit(name: segs[1]) }
    return nil
}
