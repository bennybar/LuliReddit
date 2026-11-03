import Foundation

/// Central place for Reddit OAuth + API constants.
///
/// The client id, redirect uri and (optional) Giphy key are NOT compiled in:
/// they are entered by the user on the login screen and stored securely at
/// runtime (see SecureStore).
///
/// Every "luli" identifier here is deliberate and must not be renamed — the
/// app's display name changed to Ilay, but users registered `luli://oauth`.
enum RedditConstants {
    static let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    static let appBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    static let githubRepo = "bennybar/LuliReddit"

    static let authorizeUrl = "https://www.reddit.com/api/v1/authorize.compact"
    static let accessTokenUrl = "https://www.reddit.com/api/v1/access_token"
    static let oauthApiBase = "https://oauth.reddit.com"

    // "Website session" fallback (no API key): talk to the normal site the
    // way a logged-in browser does. See docs/hydra-fallback.md.
    static let webApiBase = "https://www.reddit.com"
    static let webLoginUrl = "https://www.reddit.com/login"
    // The same UA as the Flutter build on iOS: Reddit's edge knows this one.
    static let webUserAgent = "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) "
        + "Chrome/124.0.0.0 Mobile Safari/537.36"

    /// The user must register this exact value at reddit.com/prefs/apps.
    static let defaultRedirectUri = "luli://oauth"
    static let callbackScheme = "luli"

    /// Every scheme the OAuth redirect can come back on. `redreader` lets
    /// people sign in with a client ID issued to RedReader.
    static let callbackSchemes: Set<String> = [callbackScheme, "redreader"]
    static let redReaderRedirectUri = "redreader://rr_oauth_redir"

    static let responseType = "code"
    static let duration = "permanent"

    /// `modposts` covers approve / remove / lock / distinguish over OAuth.
    static let scope = "identity edit flair history mysubreddits privatemessages read report "
        + "save submit subscribe vote wikiread account modposts modflair modcontributors"

    static let installedClientGrant = "https://oauth.reddit.com/grants/installed_client"
    static let validationDeviceId = "DO_NOT_TRACK_THIS_DEVICE"
    static let grantAuthorizationCode = "authorization_code"
    static let grantRefreshToken = "refresh_token"

    /// Reddit requires a unique, descriptive UA per its API rules.
    static func userAgent(_ username: String?) -> String {
        let who = username?.nilIfEmpty ?? "anonymous"
        return "android:com.bennybar.luli_for_reddit:\(appVersion) (by /u/\(who))"
    }
}
