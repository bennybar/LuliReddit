import Foundation
import os

/// A non-2xx answer from Reddit. [reason] is Reddit's machine-readable cause
/// when it sends one, e.g. "private", "banned" or "quarantined".
struct RedditApiException: LocalizedError {
    let statusCode: Int
    var reason: String? = nil
    var message: String? = nil

    var errorDescription: String? { "HTTP \(statusCode)\(reason.map { " (\($0))" } ?? "")" }
}

/// A GET result: the JSON body and whether it was served from the offline cache.
struct ApiResult: Sendable {
    let json: JsonElement
    var fromCache = false
}

/// Query or form fields, in order. Nil values are left out.
typealias Fields = [(String, String?)]

/// Authenticated client for oauth.reddit.com. Attaches the bearer token, a
/// compliant User-Agent and `raw_json=1`, transparently refreshes the access
/// token once on a 401, surfaces rate-limit headers, serves a disk-cache copy
/// when offline, and in website-session mode talks to www.reddit.com like a
/// logged-in browser instead.
actor RedditClient {
    private let store: SecureStore
    private let auth: AuthRepository
    private let cache: ResponseCache
    private let session: URLSession
    private let onRateLimit: @Sendable (RateLimit) -> Void

    // Settable without waiting for the actor: an account switch must apply to
    // the very next request. A new generation forces a re-read of the auth mode.
    private struct Shared {
        var generation = 1
        var cacheOn = true
    }
    private let shared = OSAllocatedUnfairLock(initialState: Shared())

    // Auth-mode config, lazily loaded and refreshed on login / switch / resume.
    private let configLock = AsyncMutex()
    private var loadedGeneration = 0
    private var webMode = false
    private var webCookie: String?
    private var webModhash: String?
    // Prefix for response-cache keys, so one account's cached pages are never
    // served to another.
    private var cacheUser = ""
    // Held in memory rather than read from secure storage on every request.
    private var username = ""
    private var token: String?
    private var tokenExpiry: Int?

    init(
        store: SecureStore,
        auth: AuthRepository,
        cache: ResponseCache,
        session: URLSession = Http.session,
        onRateLimit: @escaping @Sendable (RateLimit) -> Void
    ) {
        self.store = store
        self.auth = auth
        self.cache = cache
        self.session = session
        self.onRateLimit = onRateLimit
    }

    /// Force a re-read of the auth mode on the next request (login / account switch).
    nonisolated func invalidateAuthConfig() { shared.withLock { $0.generation += 1 } }

    /// Settings → offline cache, pushed in from settings.
    nonisolated func setCacheEnabled(_ on: Bool) { shared.withLock { $0.cacheOn = on } }

    private nonisolated var generation: Int { shared.withLock { $0.generation } }
    private nonisolated var cacheOn: Bool { shared.withLock { $0.cacheOn } }

    private func ensureConfig() async {
        if loadedGeneration == generation { return }
        await configLock.lock()
        defer { configLock.unlock() }
        let gen = generation
        if loadedGeneration == gen { return }
        token = nil
        tokenExpiry = nil
        webMode = await store.authMode() == "web"
        webCookie = webMode ? await store.webCookie() : nil
        webModhash = webMode ? await store.webModhash() : nil
        username = await store.username() ?? ""
        cacheUser = username.lowercased()
        loadedGeneration = gen
    }

    /// The request URL for the current mode. Web mode appends `.json` to listing GETs.
    private func reqUrl(_ path: String, isGet: Bool) -> String {
        if !webMode { return RedditConstants.oauthApiBase + path }
        let base = RedditConstants.webApiBase
        return isGet && !path.contains("/api/") ? "\(base)\(path).json" : "\(base)\(path)"
    }

    private func validToken() async -> String {
        if token == nil {
            token = await store.accessToken()
            tokenExpiry = await store.tokenExpiry()
        }
        let expired = tokenExpiry.map { nowMillis() > $0 } ?? true
        if token?.isEmpty != false || expired {
            if let fresh = await auth.refresh() {
                token = fresh
                tokenExpiry = await store.tokenExpiry()
                return fresh
            }
        }
        return token ?? ""
    }

    private func authorize(_ r: URLRequest, method: String) async -> URLRequest {
        var r = r
        if webMode {
            // With a current token_v2 (see WebToken.swift).
            if let c = webCookie, needsNewToken(c) { _ = await refreshWebToken() }
            r.setValue(RedditConstants.webUserAgent, forHTTPHeaderField: "User-Agent")
            if let c = webCookie { r.setValue(c, forHTTPHeaderField: "cookie") }
            if method != "GET", let m = webModhash { r.setValue(m, forHTTPHeaderField: "X-Modhash") }
        } else {
            let t = await validToken()
            r.setValue("bearer \(t)", forHTTPHeaderField: "Authorization")
            r.setValue(RedditConstants.userAgent(username.nilIfEmpty), forHTTPHeaderField: "User-Agent")
        }
        return r
    }

    private let renewLock = AsyncMutex()
    private var renewedAt = 0

    /// A new token_v2 for the website session, saved with it. One renewal at a
    /// time; after a failed one, waits 5 minutes before trying again; after a
    /// token Reddit [rejected], a minute (one it just issued being refused
    /// means something else is wrong).
    private func refreshWebToken(rejected: Bool = false) async -> Bool {
        guard let cookie = webCookie else { return false }
        let user = username
        await renewLock.lock()
        defer { renewLock.unlock() }
        if webCookie != cookie { return true } // renewed meanwhile
        let wait = rejected ? 60_000 : 5 * 60_000
        if nowMillis() - renewedAt < wait { return false }
        let fresh = await renewWebToken(cookie, session: session)
        renewedAt = nowMillis()
        guard let fresh else { return false }
        // An account switch while renewing: the fresh cookie is the old account's.
        if loadedGeneration != generation || username != user { return false }
        webCookie = fresh
        await store.updateWebCookie(fresh, user: user)
        return true
    }

    /// The website session's cookies with a current token_v2, for loading
    /// reddit.com pages (Reddit Home): the saved one has usually expired after
    /// the app was closed a day.
    func freshWebCookie() async -> String? {
        await ensureConfig()
        if let c = webCookie, needsNewToken(c) { _ = await refreshWebToken() }
        return webCookie
    }

    /// Whether requests go through the website session (website sign-in).
    func isWebMode() async -> Bool {
        await ensureConfig()
        return webMode
    }

    /// One of Reddit's app GraphQL operations (persisted: by name and hash), as
    /// the website session, whose token_v2 the API takes as a bearer token. For
    /// what the website's .json endpoints refuse (search). Returns `data`.
    func gql(_ operation: String, _ hash: String, _ variables: JsonObject) async throws -> JsonObject {
        await ensureConfig()
        if let c = webCookie, needsNewToken(c) { _ = await refreshWebToken() }
        let body = Data(JsonElement.object([
            "operationName": .string(operation),
            "variables": .object(variables),
            "extensions": ["persistedQuery": ["version": 1, "sha256Hash": .string(hash)]],
        ]).encoded().utf8)
        func send() async throws -> (status: Int, body: Data) {
            var r = URLRequest(url: URL(string: "https://cf.gql-fed.reddit.com/")!)
            r.httpMethod = "POST"
            r.setValue("Bearer \(webCookie.flatMap { cookieValue($0, "token_v2") } ?? "")", forHTTPHeaderField: "Authorization")
            r.setValue(RedditConstants.webUserAgent, forHTTPHeaderField: "User-Agent")
            r.setValue("application/json", forHTTPHeaderField: "Accept")
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = body
            let res = try await session.send(r)
            return (res.status, res.body)
        }
        var res = try await send()
        // A token Reddit no longer takes gets a 401/403: renew it, retry once.
        if res.status == 401 || res.status == 403, await refreshWebToken(rejected: true) {
            res = try await send()
        }
        let json = await parseLeniently(res.body)
        guard let data = json["data"].obj() else {
            throw RedditApiException(statusCode: res.status, message: json["errors"][0]["message"].str())
        }
        return data
    }

    private nonisolated func parseLeniently(_ data: Data) async -> JsonElement? { try? AppJson.parse(data) }

    private func buildUrl(_ path: String, isGet: Bool, _ query: Fields) -> URL {
        var c = URLComponents(string: reqUrl(path, isGet: isGet))!
        var items = query.compactMap { k, v in v.map { URLQueryItem(name: k, value: $0) } }
        items.append(URLQueryItem(name: "raw_json", value: "1"))
        c.queryItems = items
        // URLComponents leaves "+" as is, and servers read that as a space.
        c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return c.url!
    }

    private func captureRateLimit(_ res: HTTPURLResponse) {
        func number(_ name: String) -> Int? { res.value(forHTTPHeaderField: name).flatMap(Double.init).map { Int($0) } }
        guard res.value(forHTTPHeaderField: "x-ratelimit-remaining") != nil else {
            // A 429 without the usual headers can still say when to come back.
            if res.statusCode == 429, let retry = number("retry-after") {
                onRateLimit(RateLimit(remaining: 0, used: 0, resetSeconds: retry))
            }
            return
        }
        onRateLimit(RateLimit(
            remaining: number("x-ratelimit-remaining") ?? 0,
            used: number("x-ratelimit-used") ?? 0,
            resetSeconds: number("x-ratelimit-reset") ?? 0
        ))
    }

    /// Executes [method] on [url], refreshing the token and retrying once on a
    /// 401 (OAuth mode). Returns status + body.
    private func execute(_ method: String, _ url: URL, body: Data? = nil, contentType: String? = nil) async throws -> (status: Int, body: Data) {
        func once() async throws -> (status: Int, body: Data) {
            var r = URLRequest(url: url)
            r.httpMethod = method
            r.httpBody = body
            if let contentType { r.setValue(contentType, forHTTPHeaderField: "Content-Type") }
            r = await authorize(r, method: method)
            let res = try await session.send(r)
            captureRateLimit(res.response)
            return (res.status, res.body)
        }
        let first = try await once()
        if !webMode, first.status == 401, let newToken = await auth.refresh() {
            token = newToken
            tokenExpiry = await store.tokenExpiry()
            // If the retry itself fails, fall through to the original answer.
            do {
                return try await once()
            } catch is URLError {
                return first
            }
        }
        return first
    }

    /// 4xx/5xx is a real failure: throw, so optimistic UI rolls back and
    /// screens show an error instead of treating the error body as empty.
    /// Big responses (a thread is ~250KB): nonisolated, so parsed off the actor.
    private nonisolated func parseOrThrow(_ status: Int, _ body: Data) async throws -> JsonElement? {
        let blank = body.allSatisfy { $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }
        let json = blank ? nil : try? AppJson.parse(body)
        if status >= 400 {
            throw RedditApiException(statusCode: status, reason: json["reason"].str(), message: json["message"].str())
        }
        return json
    }

    /// Cache key; same shape as the Flutter build's so its cache carries over.
    private func cacheKey(_ path: String, _ query: Fields) -> String {
        "\(cacheUser)|\(path)?" + query.compactMap { k, v in v.map { "\(k)=\($0)" } }.joined(separator: "&")
    }

    /// The last cached response for this exact request, without touching the
    /// network — so a feed can paint instantly and replace it when the network
    /// answers.
    func cached(_ path: String, _ query: Fields = []) async -> JsonElement? {
        if !cacheOn { return nil }
        await ensureConfig()
        return await cache.read(cacheKey(path, query))
    }

    /// GET [path] (relative to the API base). Retries once on a network error
    /// (a stale socket dies on the first attempt), then falls back to the
    /// offline cache when enabled.
    func getResult(_ path: String, _ query: Fields = []) async throws -> ApiResult {
        await ensureConfig()
        let url = buildUrl(path, isGet: true, query)
        // The cache key for the account that made the request: an account
        // switch while it's in flight must not file it under the new one.
        let key = cacheKey(path, query)
        var lastError: URLError?
        for attempt in 0..<2 {
            do {
                let (status, body) = try await execute("GET", url)
                guard let json = try await parseOrThrow(status, body) else {
                    throw RedditApiException(statusCode: status, message: "Unexpected response from Reddit (HTTP \(status)). Please try again.")
                }
                // Don't make the caller wait for the cache write.
                if cacheOn, status == 200, key == cacheKey(path, query) {
                    Task.detached { [cache] in await cache.write(key, body) }
                }
                return ApiResult(json: json)
            } catch let e as URLError {
                if e.code == .cancelled { throw e }
                lastError = e
                if attempt == 0 { try await Task.sleep(for: .milliseconds(250)) }
            }
        }
        if cacheOn, let json = await cache.read(cacheKey(path, query)) { return ApiResult(json: json, fromCache: true) }
        throw lastError!
    }

    func get(_ path: String, _ query: Fields = []) async throws -> JsonElement { try await getResult(path, query).json }

    private static let formType = "application/x-www-form-urlencoded"
    private static let jsonType = "application/json; charset=utf-8"

    /// Form-encoded POST.
    @discardableResult
    func post(_ path: String, _ data: Fields = []) async throws -> JsonElement? {
        await ensureConfig()
        let (status, body) = try await execute("POST", buildUrl(path, isGet: false, []), body: formEncoded(data), contentType: RedditClient.formType)
        return try await parseOrThrow(status, body)
    }

    /// POST with a JSON body (submit_gallery_post, multireddit APIs).
    @discardableResult
    func postJson(_ path: String, _ json: String) async throws -> JsonElement? {
        await ensureConfig()
        let (status, body) = try await execute("POST", buildUrl(path, isGet: false, []), body: Data(json.utf8), contentType: RedditClient.jsonType)
        return try await parseOrThrow(status, body)
    }

    /// Form-encoded PUT (e.g. updating a multireddit's model).
    @discardableResult
    func putForm(_ path: String, _ data: Fields) async throws -> JsonElement? {
        await ensureConfig()
        let (status, body) = try await execute("PUT", buildUrl(path, isGet: false, []), body: formEncoded(data), contentType: RedditClient.formType)
        return try await parseOrThrow(status, body)
    }

    @discardableResult
    func put(_ path: String, _ json: String) async throws -> JsonElement? {
        await ensureConfig()
        let (status, body) = try await execute("PUT", buildUrl(path, isGet: false, []), body: Data(json.utf8), contentType: RedditClient.jsonType)
        return try await parseOrThrow(status, body)
    }

    @discardableResult
    func delete(_ path: String, _ query: Fields = []) async throws -> JsonElement? {
        await ensureConfig()
        let (status, body) = try await execute("DELETE", buildUrl(path, isGet: false, query))
        return try await parseOrThrow(status, body)
    }

    func clearCache() async { await cache.clear() }
}
