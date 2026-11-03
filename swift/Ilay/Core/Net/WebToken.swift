import Foundation

// Website sign-in sends the cookies captured at login. Their `token_v2` (a
// JWT, valid for about a day) is also the bearer token for Reddit's app
// GraphQL API, which search needs (RedditClient.gql). Page loads stopped
// renewing it in October 2026, but a request to the website that carries no
// token_v2 still gets a new one.

private func headerParts(_ header: String) -> [String] { header.components(separatedBy: ";").map(\.trimmed) }

/// The value of cookie [name] in a Cookie header.
func cookieValue(_ header: String, _ name: String) -> String? {
    headerParts(header).first { $0.hasPrefix("\(name)=") }.map { String($0.dropFirst(name.count + 1)) }
}

/// [header] with cookie [name] set to [value] (in place), or removed when [value] is nil.
func withCookie(_ header: String, _ name: String, _ value: String?) -> String {
    var parts = headerParts(header).filter { !$0.isEmpty }
    let i = parts.firstIndex { $0.hasPrefix("\(name)=") }
    if let value {
        if let i { parts[i] = "\(name)=\(value)" } else { parts.append("\(name)=\(value)") }
    } else if let i {
        parts.remove(at: i)
    }
    return parts.joined(separator: "; ")
}

/// Claim [name] of a JWT (token_v2, reddit_session); nil if it can't be read.
private func claim(_ jwt: String, _ name: String) -> JsonElement? {
    let segments = jwt.components(separatedBy: ".")
    guard segments.count > 1 else { return nil }
    var b64 = segments[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/").trimmingEnd("=")
    while b64.count % 4 != 0 { b64 += "=" }
    guard let data = Data(base64Encoded: b64), let json = try? AppJson.parse(data), let v = json[name] else { return nil }
    if case .array = v { return nil }
    if case .object = v { return nil }
    return v
}

/// When a token_v2 JWT expires (epoch millis); nil if it can't be read.
func tokenExpiry(_ token: String) -> Int? {
    // A number of seconds, with a fraction in Reddit's tokens.
    claim(token, "exp").double().map { Int($0 * 1000) }
}

/// The account (t2_…) [cookieHeader]'s reddit_session belongs to, if readable.
func sessionAccount(_ cookieHeader: String) -> String? {
    cookieValue(cookieHeader, "reddit_session").flatMap { claim($0, "sub") }.str()
}

/// Whether [cookieHeader]'s token_v2 is missing or expires within 5 minutes.
func needsNewToken(_ cookieHeader: String, now: Int = nowMillis()) -> Bool {
    guard let expiry = cookieValue(cookieHeader, "token_v2").flatMap(tokenExpiry) else { return true }
    return expiry < now + 5 * 60_000
}

/// [header] with the cookies a response's Set-Cookie headers set (a deleted or emptied cookie is left out).
func mergeSetCookies(_ header: String, _ setCookies: [String]) -> String {
    var out = header
    for sc in setCookies {
        let pair = sc.substringBefore(";")
        guard let eq = pair.firstIndex(of: "="), eq > pair.startIndex else { continue }
        let value = pair[pair.index(after: eq)...].description.trimmed
        let gone = value.isEmpty || sc.lowercased().contains("max-age=0")
        out = withCookie(out, pair[..<eq].description.trimmed, gone ? nil : value)
    }
    return out
}

// URLSession joins repeated headers with ", ". A comma inside a cookie's Expires
// date isn't followed by `name=`, so that's where one cookie ends and the next starts.
private let setCookieSplit = Re(#",\s*(?=[^;,=\s]+=)"#)

/// A response's separate Set-Cookie headers.
func setCookies(_ response: HTTPURLResponse) -> [String] {
    guard let joined = response.value(forHTTPHeaderField: "Set-Cookie") else { return [] }
    return setCookieSplit.split(joined)
}

/// Gets a new token_v2 for [cookieHeader]'s session: the page (which sets it,
/// with loid, csrf_token…), then the website's GraphQL proxy, which also sets
/// it even though it rejects the empty request. Returns the updated header,
/// or nil when Reddit didn't issue a fresh token.
func renewWebToken(_ cookieHeader: String, session: URLSession = Http.session) async -> String? {
    // Reddit only issues a token to a request that doesn't carry one.
    var cookie = withCookie(cookieHeader, "token_v2", nil)
    func request(_ url: String) -> URLRequest {
        var r = URLRequest(url: URL(string: url)!)
        r.setValue(cookie, forHTTPHeaderField: "cookie")
        r.setValue(RedditConstants.webUserAgent, forHTTPHeaderField: "User-Agent")
        return r
    }
    do {
        var page = request("\(RedditConstants.webApiBase)/")
        page.httpMethod = "HEAD"
        cookie = mergeSetCookies(cookie, setCookies(try await session.send(page).response))
        var proxy = request("\(RedditConstants.webApiBase)/svc/shreddit/graphql")
        proxy.setValue("application/json", forHTTPHeaderField: "Accept")
        proxy.setValue("application/json", forHTTPHeaderField: "Content-Type")
        proxy.httpMethod = "POST"
        proxy.httpBody = Data("{}".utf8)
        cookie = mergeSetCookies(cookie, setCookies(try await session.send(proxy).response))
    } catch {
        return nil
    }
    // The page renews reddit_session too: it must still be the same account,
    // so a renewal can't hand out another account's token.
    if sessionAccount(cookie) != sessionAccount(cookieHeader) { return nil }
    return needsNewToken(cookie) ? nil : cookie
}
