import Foundation
import Security

/// A keychain failure other than "not there".
struct KeychainError: Error {
    let status: OSStatus
}

/// Where SecureStore's values live: the keychain, or a stand-in in tests.
protocol SecureBackend: Sendable {
    func read(_ key: String) throws -> String?
    func write(_ key: String, _ value: String) throws
    func delete(_ key: String) throws
    func deleteAll() throws
    func contains(_ key: String) throws -> Bool
}

/// The Flutter build's flutter_secure_storage items, in place: generic passwords
/// in the service below, account = key name, UTF-8 data, readable after first
/// unlock. They sit in the first keychain group of the entitlements
/// (57L2ULXB7Z.com.bennybar.lulireddit), which is what a query without a group
/// reads and an add without one writes to.
struct KeychainBackend: SecureBackend {
    private static let service = "flutter_secure_storage_service"

    private func query(_ key: String?) -> [CFString: Any] {
        var q: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: KeychainBackend.service]
        if let key { q[kSecAttrAccount] = key }
        return q
    }

    func read(_ key: String) throws -> String? {
        var q = query(key)
        q[kSecReturnData] = true
        q[kSecMatchLimit] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        return (out as? Data).flatMap { String(data: $0, encoding: .utf8) }
    }

    func write(_ key: String, _ value: String) throws {
        let data = Data(value.utf8)
        let update = SecItemUpdate(query(key) as CFDictionary, [kSecValueData: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw KeychainError(status: update) }
        var q = query(key)
        q[kSecValueData] = data
        // `first_unlock` keeps tokens readable after the first unlock post-boot
        // (incl. when the app is resumed/relaunched in the background), avoiding
        // transient null reads that logged users out.
        q[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        let add = SecItemAdd(q as CFDictionary, nil)
        guard add == errSecSuccess else { throw KeychainError(status: add) }
    }

    func delete(_ key: String) throws {
        let status = SecItemDelete(query(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }

    func deleteAll() throws {
        let status = SecItemDelete(query(nil) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }

    func contains(_ key: String) throws -> Bool {
        var q = query(key)
        q[kSecReturnAttributes] = true
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        return true
    }
}

/// Everything sensitive: the user's Reddit API credentials (entered at login),
/// OAuth tokens, website-session cookies and the multi-account map.
///
/// Reads and writes the very same keychain items the Flutter build used, so an
/// existing login simply carries over — nobody has to sign in again.
actor SecureStore {
    private let backend: SecureBackend

    init(backend: SecureBackend = KeychainBackend()) { self.backend = backend }

    /// The keychain can transiently fail right after boot / on a cold start,
    /// which used to bounce a logged-in user to the login screen. Retry.
    private func retrying<T>(_ block: () throws -> T) async throws -> T {
        var last: Error?
        for _ in 0..<3 {
            do {
                return try block()
            } catch {
                last = error
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
        throw last!
    }

    func read(_ key: String) async throws -> String? {
        try await retrying { try backend.read(key) }
    }

    /// Like [read] but never throws (a failure reads as nil).
    func readOrNull(_ key: String) async -> String? { try? await read(key) }

    private func write(_ key: String, _ value: String?) async {
        try? await retrying {
            if let value { try backend.write(key, value) } else { try backend.delete(key) }
        }
    }

    private func delete(_ keys: String...) async {
        try? await retrying { for k in keys { try backend.delete(k) } }
    }

    /// Whether a username is stored. Unlike [username], a read failure throws.
    func hasUsername() async throws -> Bool { try await retrying { try backend.contains(Self.kUsername) } }

    // --- API credentials ---
    func clientId() async -> String? { await readOrNull(Self.kClientId) }
    func redirectUri() async -> String? { await readOrNull(Self.kRedirectUri) }
    func giphyKey() async -> String? { await readOrNull(Self.kGiphyKey) }

    /// OpenAI (or compatible) API key for AI thread summaries. Account-independent.
    func openaiKey() async -> String? { await readOrNull(Self.kOpenaiKey) }
    func saveOpenaiKey(_ value: String?) async { await write(Self.kOpenaiKey, value?.nilIfEmpty) }

    func saveGiphyKey(_ value: String?) async { await write(Self.kGiphyKey, value?.nilIfEmpty) }

    /// Azure Translator key (Settings → Translation service). Account-independent.
    func azureTranslatorKey() async -> String? { await readOrNull(Self.kAzureTranslatorKey) }
    func saveAzureTranslatorKey(_ value: String?) async { await write(Self.kAzureTranslatorKey, value?.nilIfEmpty) }

    func saveCredentials(clientId: String, redirectUri: String, giphyKey: String? = nil) async {
        await write(Self.kClientId, clientId)
        await write(Self.kRedirectUri, redirectUri)
        await write(Self.kGiphyKey, giphyKey?.nilIfEmpty)
    }

    // --- Tokens ---
    func accessToken() async -> String? { await readOrNull(Self.kAccessToken) }
    func refreshToken() async -> String? { await readOrNull(Self.kRefreshToken) }
    func username() async -> String? { await readOrNull(Self.kUsername) }

    /// Access-token expiry, millis since epoch.
    func tokenExpiry() async -> Int? { await readOrNull(Self.kTokenExpiry).flatMap { Int($0) } }

    func saveTokens(accessToken: String, refreshToken: String?, expiryMillis: Int) async {
        await write(Self.kAccessToken, accessToken)
        if let refreshToken { await write(Self.kRefreshToken, refreshToken) }
        await write(Self.kTokenExpiry, String(expiryMillis))
    }

    func saveUsername(_ username: String?) async { await write(Self.kUsername, username) }

    // --- Auth mode + website session (no-API-key fallback) ---
    /// 'oauth' (default), 'web', or 'anon' (browsing without an account).
    func authMode() async -> String { await readOrNull(Self.kAuthMode) ?? "oauth" }
    func webCookie() async -> String? { await readOrNull(Self.kWebCookie) }
    func webModhash() async -> String? { await readOrNull(Self.kWebModhash) }

    func saveWebSession(username: String, cookie: String, modhash: String?) async {
        await write(Self.kAuthMode, "web")
        await write(Self.kWebCookie, cookie)
        await write(Self.kWebModhash, modhash)
        await write(Self.kUsername, username)
        await delete(Self.kAccessToken, Self.kRefreshToken, Self.kTokenExpiry)
    }

    /// Browsing without an account: an app-only token, no user/refresh/cookie.
    func saveAnonymousSession() async {
        await write(Self.kAuthMode, "anon")
        await delete(Self.kRefreshToken, Self.kUsername, Self.kWebCookie, Self.kWebModhash)
    }

    // --- Multi-account ---
    // {username: account} where each value is an OAuth account
    // {"mode":"oauth","rt":...} or a website-session account
    // {"mode":"web","cookie":...,"modhash":...}. Legacy plain-string values are
    // an OAuth refresh token. The "active slot" keys mirror the current account.

    private func accountsMap() async -> OrderedMap<JsonObject> {
        var out = OrderedMap<JsonObject>()
        guard let raw = await readOrNull(Self.kAccounts)?.nilIfEmpty, let m = parseJsonOrNull(raw).obj() else { return out }
        for (k, v) in m {
            out[k] = v.obj() ?? ["mode": "oauth", "rt": .of(v.content())]
        }
        return out
    }

    private func saveAccounts(_ m: OrderedMap<JsonObject>) async {
        var o = JsonObject()
        for (k, v) in m { o[k] = .object(v) }
        await write(Self.kAccounts, o.encoded())
    }

    func accounts() async -> [String] { await accountsMap().keys }

    func accountMode(_ username: String) async -> String? {
        await accountsMap()[username]?["mode"].content()
    }

    func upsertAccount(_ username: String, refreshToken: String) async {
        var m = await accountsMap()
        m[username] = ["mode": "oauth", "rt": .string(refreshToken)]
        await saveAccounts(m)
    }

    func upsertWebAccount(_ username: String, cookie: String, modhash: String?) async {
        var m = await accountsMap()
        m[username] = ["mode": "web", "cookie": .string(cookie), "modhash": .of(modhash)]
        await saveAccounts(m)
    }

    /// The active website session's cookies, renewed (a fresh token_v2; see
    /// WebToken.swift), also in its saved account so switching back keeps them.
    /// [user] is whose they are: the active slot only takes them while [user]
    /// is still the active account.
    func updateWebCookie(_ cookie: String, user: String) async {
        if await username() == user { await write(Self.kWebCookie, cookie) }
        var m = await accountsMap()
        guard var acct = m[user], acct["mode"].content() == "web" else { return }
        acct["cookie"] = .string(cookie)
        m[user] = acct
        await saveAccounts(m)
    }

    func removeAccountEntry(_ username: String) async {
        var m = await accountsMap()
        m.removeValue(forKey: username)
        await saveAccounts(m)
    }

    func clearAccounts() async { await delete(Self.kAccounts) }

    /// Loads [username]'s stored credentials into the active slot. False if unknown.
    func activateAccount(_ username: String) async -> Bool {
        guard let acct = await accountsMap()[username] else { return false }
        let mode = acct["mode"].str() ?? "oauth"
        await write(Self.kUsername, username)
        await delete(Self.kAccessToken, Self.kTokenExpiry)
        if mode == "web" {
            await write(Self.kAuthMode, "web")
            await write(Self.kWebCookie, acct["cookie"].str())
            await write(Self.kWebModhash, acct["modhash"].str())
            await delete(Self.kRefreshToken)
        } else {
            await write(Self.kAuthMode, "oauth")
            await write(Self.kRefreshToken, acct["rt"].str())
            await delete(Self.kWebCookie, Self.kWebModhash)
        }
        return true
    }

    /// Clears the active session but keeps API credentials so re-login is quick.
    func clearSession() async {
        await delete(Self.kAccessToken, Self.kRefreshToken, Self.kTokenExpiry, Self.kUsername, Self.kWebCookie, Self.kWebModhash, Self.kAuthMode)
    }

    /// Full wipe — credentials and session.
    func clearAll() async { try? await retrying { try backend.deleteAll() } }

    private static let kClientId = "client_id"
    private static let kRedirectUri = "redirect_uri"
    private static let kGiphyKey = "giphy_api_key"
    private static let kOpenaiKey = "openai_api_key"
    private static let kAzureTranslatorKey = "azure_translator_key"
    private static let kAccessToken = "access_token"
    private static let kRefreshToken = "refresh_token"
    private static let kTokenExpiry = "token_expiry"
    private static let kUsername = "username"
    private static let kAuthMode = "auth_mode"
    private static let kWebCookie = "web_cookie"
    private static let kWebModhash = "web_modhash"
    private static let kAccounts = "accounts_json"
}
