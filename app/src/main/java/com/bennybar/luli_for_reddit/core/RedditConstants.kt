package com.bennybar.luli_for_reddit.core

import com.bennybar.luli_for_reddit.BuildConfig

/**
 * Central place for Reddit OAuth + API constants.
 *
 * The client id, redirect uri and (optional) Giphy key are NOT compiled in:
 * they are entered by the user on the login screen and stored securely at
 * runtime (see [com.bennybar.luli_for_reddit.core.storage.SecureStore]).
 *
 * Every "luli" identifier here is deliberate and must not be renamed — the
 * app's display name changed to Ilay, but users registered `luli://oauth`.
 */
object RedditConstants {
    val APP_VERSION: String = BuildConfig.VERSION_NAME
    const val GITHUB_REPO = "bennybar/LuliReddit"

    const val AUTHORIZE_URL = "https://www.reddit.com/api/v1/authorize.compact"
    const val ACCESS_TOKEN_URL = "https://www.reddit.com/api/v1/access_token"
    const val OAUTH_API_BASE = "https://oauth.reddit.com"

    // "Website session" fallback (no API key): talk to the normal site the
    // way a logged-in browser does. See docs/hydra-fallback.md.
    const val WEB_API_BASE = "https://www.reddit.com"
    const val WEB_LOGIN_URL = "https://www.reddit.com/login"
    const val WEB_USER_AGENT =
        "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) " +
            "Chrome/124.0.0.0 Mobile Safari/537.36"

    /** The user must register this exact value at reddit.com/prefs/apps. */
    const val DEFAULT_REDIRECT_URI = "luli://oauth"
    const val CALLBACK_SCHEME = "luli"

    /**
     * Every scheme the OAuth redirect can come back on. Each one is declared on
     * OAuthRedirectActivity in AndroidManifest.xml. `redreader` lets people
     * sign in with a client ID issued to RedReader.
     */
    val CALLBACK_SCHEMES = setOf(CALLBACK_SCHEME, "redreader")
    const val REDREADER_REDIRECT_URI = "redreader://rr_oauth_redir"

    const val RESPONSE_TYPE = "code"
    const val DURATION = "permanent"

    /** `modposts` covers approve / remove / lock / distinguish over OAuth. */
    const val SCOPE =
        "identity edit flair history mysubreddits privatemessages read report " +
            "save submit subscribe vote wikiread account modposts modflair " +
            "modcontributors"

    const val INSTALLED_CLIENT_GRANT = "https://oauth.reddit.com/grants/installed_client"
    const val VALIDATION_DEVICE_ID = "DO_NOT_TRACK_THIS_DEVICE"
    const val GRANT_AUTHORIZATION_CODE = "authorization_code"
    const val GRANT_REFRESH_TOKEN = "refresh_token"

    /** Reddit requires a unique, descriptive UA per its API rules. */
    fun userAgent(username: String?): String {
        val who = if (username.isNullOrEmpty()) "anonymous" else username
        return "android:com.bennybar.luli_for_reddit:${APP_VERSION} (by /u/$who)"
    }
}
