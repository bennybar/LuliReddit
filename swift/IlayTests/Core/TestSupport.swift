import Foundation
@testable import Ilay

/// Prefs in a throwaway UserDefaults suite, never the real ones.
func testPrefs() -> Prefs {
    let name = "ilay.tests.\(UUID().uuidString)"
    return Prefs(defaults: UserDefaults(suiteName: name)!)
}

func tempDir() -> URL {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent("ilay-tests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

func json(_ s: String) -> JsonElement { try! AppJson.parse(s) }

/// The keychain's stand-in. Never the real keychain in tests.
final class InMemorySecureBackend: SecureBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: String]
    var failReads = false

    init(_ items: [String: String] = [:]) { self.items = items }

    subscript(key: String) -> String? { lock.withLock { items[key] } }

    func read(_ key: String) throws -> String? {
        try lock.withLock {
            if failReads { throw KeychainError(status: -25308) }
            return items[key]
        }
    }
    func write(_ key: String, _ value: String) throws { lock.withLock { items[key] = value } }
    func delete(_ key: String) throws { lock.withLock { items[key] = nil } }
    func deleteAll() throws { lock.withLock { items = [:] } }
    func contains(_ key: String) throws -> Bool {
        try lock.withLock {
            if failReads { throw KeychainError(status: -25308) }
            return items[key] != nil
        }
    }
}

/// Answers every request from [handler]. Never the real network in tests.
final class StubProtocol: URLProtocol {
    struct Reply {
        var status = 200
        var headers: [String: String] = [:]
        var body = ""
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: ((URLRequest) throws -> Reply)?
    nonisolated(unsafe) private static var log: [URLRequest] = []

    static func start(_ h: @escaping (URLRequest) throws -> Reply) {
        lock.withLock {
            handler = h
            log = []
        }
    }

    static var requests: [URLRequest] { lock.withLock { log } }
    static var paths: [String] { requests.map { $0.url!.path } }

    static func session() -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [StubProtocol.self]
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        return URLSession(configuration: c)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let h = StubProtocol.lock.withLock { () -> ((URLRequest) throws -> Reply)? in
            StubProtocol.log.append(request)
            return StubProtocol.handler
        }
        do {
            let r = try h!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: r.status, httpVersion: "HTTP/2", headerFields: r.headers)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(r.body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}

/// A client on the stub session, with a store holding [items].
func stubClient(_ items: [String: String], rateLimit: @escaping @Sendable (RateLimit) -> Void = { _ in }) -> (client: RedditClient, store: SecureStore, backend: InMemorySecureBackend, dir: URL) {
    let backend = InMemorySecureBackend(items)
    let store = SecureStore(backend: backend)
    let session = StubProtocol.session()
    let dir = tempDir()
    let auth = AuthRepository(store: store, session: session)
    let client = RedditClient(store: store, auth: auth, cache: ResponseCache(cacheDir: dir), session: session, onRateLimit: rateLimit)
    return (client, store, backend, dir)
}

/// A signed-in OAuth account's keychain, its token good for an hour.
func oauthItems(token: String = "tok", user: String = "alice") -> [String: String] {
    ["access_token": token, "refresh_token": "rt", "token_expiry": String(nowMillis() + 3_600_000), "username": user, "client_id": "cid"]
}

func jwt(_ payload: String) -> String {
    func part(_ s: String) -> String {
        Data(s.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    return "\(part(#"{"alg":"RS256"}"#)).\(part(payload)).sig"
}

/// A signed-in website session's keychain, its token_v2 good for a day.
func webItems(user: String = "alice") -> [String: String] {
    let token = jwt(#"{"exp":\#(nowMillis() / 1000 + 86_400)}"#)
    return ["auth_mode": "web", "web_cookie": "reddit_session=s; token_v2=\(token)", "web_modhash": "mh", "username": user]
}

func post(_ id: String = "p", title: String = "t", sub: String = "pics", nsfw: Bool = false) -> Post {
    Post(id: id, fullname: "t3_\(id)", title: title, subreddit: sub, subredditPrefixed: "r/\(sub)", author: "someone", score: 1, numComments: 0, upvoteRatio: 1.0, createdUtc: 0, permalink: "", url: "https://example.com", domain: "example.com", type: .link, over18: nsfw)
}

/// Polls until [condition] holds (background file work, Task-based reloads).
@MainActor
func eventually(_ condition: @MainActor () async -> Bool) async -> Bool {
    for _ in 0..<1000 {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return false
}
