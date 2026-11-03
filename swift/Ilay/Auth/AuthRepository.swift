import Foundation

/// Outcome of validating an entered client id (exists + is an "installed app").
struct ConfigCheckResult: Equatable, Sendable {
    let valid: Bool
    let message: String

    static let ok = ConfigCheckResult(valid: true, message: "Client ID is valid and registered as an installed app.")
    static func failed(_ message: String) -> ConfigCheckResult { ConfigCheckResult(valid: false, message: message) }
}

/// Thrown during the interactive login with a human-readable, actionable message.
struct AuthException: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

actor AuthRepository {
    private let store: SecureStore
    private let session: URLSession

    init(store: SecureStore, session: URLSession = Http.session) {
        self.store = store
        self.session = session
    }

    private func basicAuth(_ clientId: String) -> String {
        "Basic " + Data("\(clientId):".utf8).base64EncodedString()
    }

    private func tokenRequest(_ clientId: String, _ form: Fields, username: String? = nil) async throws -> (status: Int, data: JsonElement?) {
        var req = URLRequest(url: URL(string: RedditConstants.accessTokenUrl)!)
        req.httpMethod = "POST"
        req.httpBody = formEncoded(form)
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue(basicAuth(clientId), forHTTPHeaderField: "Authorization")
        req.setValue(RedditConstants.userAgent(username), forHTTPHeaderField: "User-Agent")
        let res = try await session.send(req)
        return (res.status, try? AppJson.parse(res.body))
    }

    /// Pre-flight check: confirms the client id exists at Reddit AND is an
    /// installed-app credential (the only correct type — the app has no client
    /// secret). The redirect URI is checked by Reddit during authorize.
    func validateClientId(_ clientId: String) async -> ConfigCheckResult {
        if clientId.isBlank { return .failed("Enter your Reddit Client ID.") }
        do {
            let (code, data) = try await tokenRequest(clientId.trimmed, [
                ("grant_type", RedditConstants.installedClientGrant),
                ("device_id", RedditConstants.validationDeviceId),
            ])
            if code == 200, data["access_token"].str() != nil { return .ok }
            if code == 401 {
                return .failed(
                    "Reddit rejected this Client ID (401). Check that you copied the ID "
                        + "shown under your app name at reddit.com/prefs/apps, and that the app "
                        + "type is \"installed app\" (no secret).")
            }
            return .failed("Unexpected response from Reddit (HTTP \(code)). Verify the app exists and is an installed app.")
        } catch {
            return .failed("Could not reach Reddit to validate the Client ID: \(error.localizedDescription)")
        }
    }

    /// Full interactive login through an ASWebAuthenticationSession. Reddit
    /// validates the redirect URI itself (an error on the redirect if it isn't
    /// registered). Persists tokens + username on success and returns the username.
    func login(clientId: String, redirectUri: String, ephemeral: Bool = false) async throws -> String {
        let cid = clientId.trimmed
        let redirect = redirectUri.trimmed

        // The browser only returns to us on a scheme the app listens for.
        let scheme = URL(string: redirect)?.scheme?.lowercased() ?? ""
        if !RedditConstants.callbackSchemes.contains(scheme) {
            throw AuthException(message:
                "Redirect URIs starting with \"\(scheme)://\" aren't supported. Use "
                    + "\(RedditConstants.defaultRedirectUri), or "
                    + "\(RedditConstants.redReaderRedirectUri) with a RedReader client ID.")
        }

        // A fresh random state per login: the redirect is accepted only if it
        // carries this login's value (a fixed one let any page complete a
        // pending login with someone else's code).
        let state = UUID().uuidString
        var auth = URLComponents(string: RedditConstants.authorizeUrl)!
        auth.queryItems = [
            URLQueryItem(name: "client_id", value: cid),
            URLQueryItem(name: "response_type", value: RedditConstants.responseType),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "duration", value: RedditConstants.duration),
            URLQueryItem(name: "scope", value: RedditConstants.scope),
        ]

        let returned: URL
        do {
            returned = try await OAuthFlow.authenticate(auth.url!, scheme: scheme, ephemeral: ephemeral)
        } catch {
            throw AuthException(message: "Login was cancelled or the browser failed: \(error.localizedDescription)")
        }

        if let error = returned.queryParameter("error") {
            if error == "access_denied" { throw AuthException(message: "You declined the authorization request.") }
            throw AuthException(message:
                "Reddit returned an error: \"\(error)\". This usually means the Redirect "
                    + "URI does not exactly match the one registered at reddit.com/prefs/apps. "
                    + "It must be exactly: \(redirect)")
        }
        if returned.queryParameter("state") != state {
            throw AuthException(message: "Security check failed (state mismatch). Try again.")
        }
        guard let code = returned.queryParameter("code")?.nilIfEmpty else {
            throw AuthException(message: "No authorization code was returned by Reddit.")
        }

        // Exchange the code for tokens.
        let status: Int
        let data: JsonElement?
        do {
            (status, data) = try await tokenRequest(cid, [
                ("grant_type", RedditConstants.grantAuthorizationCode),
                ("code", code),
                ("redirect_uri", redirect),
            ])
        } catch {
            throw AuthException(message: "Failed to exchange the login code: \(error.localizedDescription)")
        }
        guard status == 200, data != nil else {
            throw AuthException(message: "Token exchange failed (HTTP \(status)). The Redirect URI may not match the registered value: \(redirect)")
        }
        guard let accessToken = data["access_token"].str() else {
            throw AuthException(message: "Reddit did not return an access token.")
        }
        let refreshToken = data["refresh_token"].str()
        let expiresIn = data["expires_in"].int() ?? 3600

        // Resolve the account before saving anything: a login without a
        // username used to be stored as a placeholder account that broke later.
        var name = await fetchUsername(accessToken)
        if name == nil { name = await fetchUsername(accessToken) }
        guard let username = name else {
            throw AuthException(message: "Signed in, but couldn't load your Reddit username. Check your connection and try again.")
        }

        await store.saveTokens(accessToken: accessToken, refreshToken: refreshToken, expiryMillis: nowMillis() + (expiresIn - 60) * 1000)
        await store.saveUsername(username)
        await store.saveCredentials(clientId: cid, redirectUri: redirect, giphyKey: await store.giphyKey())
        return username
    }

    /// Website-session login (no API key). The UI captures reddit.com cookies
    /// in a WebView; verify them by fetching the logged-in user (which also
    /// yields the modhash for write actions) and persist the session.
    func completeWebLogin(cookie: String) async throws -> (username: String, modhash: String?) {
        var req = URLRequest(url: URL(string: "\(RedditConstants.webApiBase)/api/me.json")!)
        req.setValue(cookie, forHTTPHeaderField: "cookie")
        req.setValue(RedditConstants.webUserAgent, forHTTPHeaderField: "User-Agent")
        let body: Data
        do {
            body = try await session.send(req).body
        } catch {
            throw AuthException(message: "Could not reach Reddit: \(error.localizedDescription)")
        }
        let data = (try? AppJson.parse(body))["data"]
        guard let username = data["name"].str()?.nilIfEmpty else {
            throw AuthException(message: "Reddit login didn't complete. Please finish signing in and try again.")
        }
        let modhash = data["modhash"].str()
        await store.saveWebSession(username: username, cookie: cookie, modhash: modhash)
        return (username, modhash)
    }

    private func fetchUsername(_ accessToken: String) async -> String? {
        var req = URLRequest(url: URL(string: "\(RedditConstants.oauthApiBase)/api/v1/me")!)
        req.setValue("bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue(RedditConstants.userAgent(nil), forHTTPHeaderField: "User-Agent")
        guard let res = try? await session.send(req), (200..<300).contains(res.status) else { return nil }
        return (try? AppJson.parse(res.body))["name"].str()
    }

    /// Starts browsing without an account, using [clientId]'s app-only token
    /// (Reddit's "installed client" grant). Throws [AuthException] if refused.
    func startAnonymous(clientId: String) async throws {
        let cid = clientId.trimmed
        if await appOnlyToken(cid) == nil {
            throw AuthException(message: "Reddit didn't accept this Client ID. Check it, and that the app type is \"installed app\".")
        }
        await store.saveAnonymousSession()
        await store.saveCredentials(clientId: cid, redirectUri: RedditConstants.defaultRedirectUri, giphyKey: await store.giphyKey())
    }

    /// Fetches and stores an app-only access token for [clientId]; nil if refused/unreachable.
    private func appOnlyToken(_ clientId: String) async -> String? {
        guard let (code, data) = try? await tokenRequest(clientId, [
            ("grant_type", RedditConstants.installedClientGrant),
            ("device_id", RedditConstants.validationDeviceId),
        ]), code == 200, let token = data["access_token"].str() else { return nil }
        let expiresIn = data["expires_in"].int() ?? 3600
        await store.saveTokens(accessToken: token, refreshToken: nil, expiryMillis: nowMillis() + (expiresIn - 60) * 1000)
        return token
    }

    // Single-flight guard: concurrent 401s share one in-flight refresh so the
    // refresh token isn't spent multiple times in parallel.
    private var refreshing: Task<String?, Never>?

    /// Refreshes the access token. Returns it, or nil if refresh isn't possible (re-login).
    func refresh() async -> String? {
        if let refreshing { return await refreshing.value }
        // Its own task, so one caller being cancelled doesn't fail the rest.
        let job = Task.detached { await self.doRefresh() }
        refreshing = job
        let token = await job.value
        if refreshing == job { refreshing = nil }
        return token
    }

    /// Drops a refresh in flight (an account switch): its token belongs to the old account.
    func forgetRefresh() { refreshing = nil }

    private func doRefresh() async -> String? {
        let forUser = await store.username()
        let refreshToken = await store.refreshToken()
        let clientId = await store.clientId()
        // Browsing without an account: app-only tokens can't be refreshed,
        // so mint a new one the same way.
        if refreshToken == nil, let clientId, await store.authMode() == "anon" { return await appOnlyToken(clientId) }
        guard let refreshToken, let clientId else { return nil }
        guard let (code, data) = try? await tokenRequest(clientId, [
            ("grant_type", RedditConstants.grantRefreshToken),
            ("refresh_token", refreshToken),
        ], username: forUser), code == 200, let accessToken = data["access_token"].str() else { return nil }
        // The account was switched while this was in flight: the token is
        // the old account's — storing it would act as them under the new one.
        let nowUser = await store.username()
        let nowRefresh = await store.refreshToken()
        if nowUser != forUser || nowRefresh != refreshToken { return nil }
        let expiresIn = data["expires_in"].int() ?? 3600
        await store.saveTokens(accessToken: accessToken, refreshToken: nil, expiryMillis: nowMillis() + (expiresIn - 60) * 1000)
        return accessToken
    }
}
