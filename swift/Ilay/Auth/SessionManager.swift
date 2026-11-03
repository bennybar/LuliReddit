import Foundation
import Observation

/// The signed-in session.
struct AuthSession: Equatable, Sendable {
    let username: String // "" when [anonymous]
    /// Browsing without an account (app-only token): read-only.
    var anonymous = false

    /// Identity for "did the account change?" checks (anonymous is its own identity).
    var identity: String { anonymous ? "\0anon" : username }
}

enum SessionState: Equatable, Sendable {
    case loading
    case loggedOut
    case loggedIn(AuthSession)
}

/// Owns the auth state (the counterpart of Flutter's AuthController):
/// restores the session from secure storage, logs in/out, adds and switches
/// accounts.
@MainActor @Observable
final class SessionManager {
    static let hasAccountKey = "has_account"

    @ObservationIgnored private let store: SecureStore
    @ObservationIgnored private let repo: AuthRepository
    @ObservationIgnored private let prefs: Prefs
    @ObservationIgnored private let lock = AsyncMutex()
    /// Runs on every change of [state] (AppContainer's wiring).
    @ObservationIgnored var onStateChanged: ((SessionState) -> Void)?

    private(set) var state: SessionState = .loading

    /// Bumped when the stored account list changes.
    private(set) var accountsVersion = 0

    init(store: SecureStore, repo: AuthRepository, prefs: Prefs) {
        self.store = store
        self.repo = repo
        self.prefs = prefs
    }

    private func publish(_ next: SessionState) {
        if next == state { return }
        state = next
        onStateChanged?(next)
    }

    var session: AuthSession? {
        if case .loggedIn(let s) = state { return s }
        return nil
    }

    var username: String { session?.username ?? "" }

    /// Durable "an account exists on this device" flag, kept in plain prefs so
    /// the UI can tell a real logout from a transient keychain read failure
    /// (which must not bounce the user to the login screen).
    var hasAccount: Bool { prefs.getBool(SessionManager.hasAccountKey) ?? false }

    private func setHasAccount(_ v: Bool) { prefs.setBool(SessionManager.hasAccountKey, v) }

    /// Re-reads the session from storage (cold start, and on every resume).
    func reload() {
        Task {
            await lock.lock()
            defer { lock.unlock() }
            publish(await load())
        }
    }

    /// The keychain can transiently return nil (not just throw) on a cold
    /// start or resume, which used to bounce a signed-in user to the login
    /// screen. Retry the critical reads (3 × 150ms), as the Flutter build did.
    private func readRetry(_ read: () async -> String?) async -> String? {
        for _ in 0..<3 {
            if let v = await read() { return v }
            try? await Task.sleep(for: .milliseconds(150))
        }
        return await read()
    }

    private func load() async -> SessionState {
        if await store.authMode() == "anon" {
            if await readRetry({ await store.clientId() }) == nil { return .loggedOut }
            setHasAccount(true)
            return .loggedIn(AuthSession(username: "", anonymous: true))
        }
        guard let username = await readRetry({ await store.username() }) else {
            // If the store reads fine and simply holds no account (e.g.
            // restored onto a new phone, where it isn't backed up), clear
            // the flag so the login screen shows instead of an empty Home.
            if let has = try? await store.hasUsername(), !has { setHasAccount(false) }
            return .loggedOut
        }
        if await store.authMode() == "web" {
            guard let cookie = await readRetry({ await store.webCookie() }) else { return .loggedOut }
            if await !store.accounts().contains(username) {
                await store.upsertWebAccount(username, cookie: cookie, modhash: await store.webModhash())
            }
            setHasAccount(true)
            return .loggedIn(AuthSession(username: username))
        }
        // OAuth (default).
        let refresh = await readRetry { await store.refreshToken() }
        let token = await store.accessToken()
        if token == nil, refresh == nil { return .loggedOut }
        // Migrate pre-multi-account installs: ensure the current user is in the map.
        if let refresh, await !store.accounts().contains(username) {
            await store.upsertAccount(username, refreshToken: refresh)
        }
        setHasAccount(true)
        return .loggedIn(AuthSession(username: username))
    }

    /// Website-session login (no API key). [cookie] is captured by the WebView.
    func loginWithWebSession(cookie: String) async throws {
        let (username, modhash) = try await repo.completeWebLogin(cookie: cookie)
        await lock.lock()
        defer { lock.unlock() }
        await store.upsertWebAccount(username, cookie: cookie, modhash: modhash)
        await repo.forgetRefresh()
        setHasAccount(true)
        publish(.loggedIn(AuthSession(username: username)))
    }

    /// The full interactive login (first account or another one).
    func login(clientId: String, redirectUri: String, ephemeral: Bool = false) async throws {
        let username = try await repo.login(clientId: clientId, redirectUri: redirectUri, ephemeral: ephemeral)
        await lock.lock()
        defer { lock.unlock() }
        if let rt = await store.refreshToken() { await store.upsertAccount(username, refreshToken: rt) }
        setHasAccount(true)
        publish(.loggedIn(AuthSession(username: username)))
    }

    /// Starts browsing without an account (needs only a Client ID).
    func browseAnonymously(clientId: String) async throws {
        try await repo.startAnonymous(clientId: clientId)
        setHasAccount(true)
        publish(.loggedIn(AuthSession(username: "", anonymous: true)))
    }

    /// Adds another account, reusing the saved API credentials.
    func addAccount() async throws {
        guard let clientId = await store.clientId(), let redirectUri = await store.redirectUri() else {
            throw AuthException(message: "No saved API credentials on this device.")
        }
        try await login(clientId: clientId, redirectUri: redirectUri, ephemeral: true)
    }

    // Account changes hold [lock], like reload(): a resume's reload reading the
    // old account mid-switch could otherwise publish it over the new one.
    func switchAccount(_ username: String) async {
        await lock.lock()
        defer { lock.unlock() }
        if username == session?.username { return }
        guard await store.activateAccount(username) else { return }
        await repo.forgetRefresh()
        publish(.loggedIn(AuthSession(username: username)))
    }

    /// Signs out one account; switches to another if any remain.
    func removeAccount(_ username: String) async {
        await lock.lock()
        defer { lock.unlock() }
        await store.removeAccountEntry(username)
        if username != session?.username {
            accountsVersion += 1 // accounts list changed; screens re-query
            return
        }
        let remaining = await store.accounts()
        if let next = remaining.first {
            _ = await store.activateAccount(next)
            await repo.forgetRefresh()
            publish(.loggedIn(AuthSession(username: next)))
        } else {
            await store.clearSession()
            await store.clearAccounts()
            setHasAccount(false)
            publish(.loggedOut)
        }
        accountsVersion += 1
    }

    /// Full sign-out of every account.
    func logout() async {
        await lock.lock()
        defer { lock.unlock() }
        await store.clearSession()
        await store.clearAccounts()
        await repo.forgetRefresh()
        setHasAccount(false)
        publish(.loggedOut)
        accountsVersion += 1
    }

    func accounts() async -> [String] { await store.accounts() }

    /// 'oauth' (API key), 'web' (website session) or 'anon'.
    func authMode() async -> String { await store.authMode() }
}
