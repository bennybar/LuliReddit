package com.bennybar.luli_for_reddit.auth

import android.content.Context
import android.net.Uri
import android.util.Base64
import com.bennybar.luli_for_reddit.core.AppJson
import com.bennybar.luli_for_reddit.core.RedditConstants
import com.bennybar.luli_for_reddit.core.get
import com.bennybar.luli_for_reddit.core.int
import com.bennybar.luli_for_reddit.core.net.Http
import com.bennybar.luli_for_reddit.core.net.await
import com.bennybar.luli_for_reddit.core.storage.SecureStore
import com.bennybar.luli_for_reddit.core.str
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonElement
import okhttp3.FormBody
import okhttp3.Request
import java.io.IOException

/** Outcome of validating an entered client id (exists + is an "installed app"). */
data class ConfigCheckResult(val valid: Boolean, val message: String) {
    companion object {
        val OK = ConfigCheckResult(true, "Client ID is valid and registered as an installed app.")
        fun failed(message: String) = ConfigCheckResult(false, message)
    }
}

/** Thrown during the interactive login with a human-readable, actionable message. */
class AuthException(override val message: String) : Exception(message) {
    override fun toString() = message
}

class AuthRepository(private val store: SecureStore) {
    private val http = Http.client

    private fun basicAuth(clientId: String): String =
        "Basic " + Base64.encodeToString("$clientId:".toByteArray(), Base64.NO_WRAP)

    private suspend fun tokenRequest(clientId: String, form: Map<String, String>, username: String? = null): Pair<Int, JsonElement?> {
        val body = FormBody.Builder().apply { form.forEach { (k, v) -> add(k, v) } }.build()
        val req = Request.Builder().url(RedditConstants.ACCESS_TOKEN_URL).post(body)
            .header("Authorization", basicAuth(clientId))
            .header("User-Agent", RedditConstants.userAgent(username))
            .build()
        http.await(req).use { res ->
            val text = withContext(Dispatchers.IO) { res.body.string() }
            return res.code to runCatching { AppJson.parseToJsonElement(text) }.getOrNull()
        }
    }

    /**
     * Pre-flight check: confirms the client id exists at Reddit AND is an
     * installed-app credential (the only correct type — the app has no client
     * secret). The redirect URI is checked by Reddit during authorize.
     */
    suspend fun validateClientId(clientId: String): ConfigCheckResult {
        if (clientId.isBlank()) return ConfigCheckResult.failed("Enter your Reddit Client ID.")
        return try {
            val (code, data) = tokenRequest(
                clientId.trim(),
                mapOf(
                    "grant_type" to RedditConstants.INSTALLED_CLIENT_GRANT,
                    "device_id" to RedditConstants.VALIDATION_DEVICE_ID,
                ),
            )
            when {
                code == 200 && data["access_token"].str() != null -> ConfigCheckResult.OK
                code == 401 -> ConfigCheckResult.failed(
                    "Reddit rejected this Client ID (401). Check that you copied the ID " +
                        "shown under your app name at reddit.com/prefs/apps, and that the app " +
                        "type is \"installed app\" (no secret).",
                )
                else -> ConfigCheckResult.failed(
                    "Unexpected response from Reddit (HTTP $code). Verify the app exists and is an installed app.",
                )
            }
        } catch (e: IOException) {
            ConfigCheckResult.failed("Could not reach Reddit to validate the Client ID: ${e.message}")
        }
    }

    /**
     * Full interactive login through a Custom Tab. Reddit validates the
     * redirect URI itself (an error on the redirect if it isn't registered).
     * Persists tokens + username on success and returns the username.
     */
    suspend fun login(context: Context, clientId: String, redirectUri: String, ephemeral: Boolean = false): String {
        val cid = clientId.trim()
        val redirect = redirectUri.trim()

        // The browser only returns to us on a scheme the app listens for.
        val scheme = runCatching { Uri.parse(redirect).scheme?.lowercase() }.getOrNull() ?: ""
        if (scheme !in RedditConstants.CALLBACK_SCHEMES) {
            throw AuthException(
                "Redirect URIs starting with \"$scheme://\" aren't supported. Use " +
                    "${RedditConstants.DEFAULT_REDIRECT_URI}, or " +
                    "${RedditConstants.REDREADER_REDIRECT_URI} with a RedReader client ID.",
            )
        }

        val authUri = Uri.parse(RedditConstants.AUTHORIZE_URL).buildUpon()
            .appendQueryParameter("client_id", cid)
            .appendQueryParameter("response_type", RedditConstants.RESPONSE_TYPE)
            .appendQueryParameter("state", STATE)
            .appendQueryParameter("redirect_uri", redirect)
            .appendQueryParameter("duration", RedditConstants.DURATION)
            .appendQueryParameter("scope", RedditConstants.SCOPE)
            .build()

        val returned = try {
            OAuthFlow.authenticate(context, authUri, ephemeral)
        } catch (e: Exception) {
            throw AuthException("Login was cancelled or the browser failed: ${e.message ?: e}")
        }

        val error = returned.getQueryParameter("error")
        if (error != null) {
            if (error == "access_denied") throw AuthException("You declined the authorization request.")
            throw AuthException(
                "Reddit returned an error: \"$error\". This usually means the Redirect " +
                    "URI does not exactly match the one registered at reddit.com/prefs/apps. " +
                    "It must be exactly: $redirect",
            )
        }
        if (returned.getQueryParameter("state") != STATE) {
            throw AuthException("Security check failed (state mismatch). Try again.")
        }
        val code = returned.getQueryParameter("code")
        if (code.isNullOrEmpty()) throw AuthException("No authorization code was returned by Reddit.")

        // Exchange the code for tokens.
        val (status, data) = try {
            tokenRequest(
                cid,
                mapOf(
                    "grant_type" to RedditConstants.GRANT_AUTHORIZATION_CODE,
                    "code" to code,
                    "redirect_uri" to redirect,
                ),
            )
        } catch (e: IOException) {
            throw AuthException("Failed to exchange the login code: ${e.message}")
        }
        if (status != 200 || data == null) {
            throw AuthException(
                "Token exchange failed (HTTP $status). The Redirect URI may not match the registered value: $redirect",
            )
        }
        val accessToken = data["access_token"].str() ?: throw AuthException("Reddit did not return an access token.")
        val refreshToken = data["refresh_token"].str()
        val expiresIn = data["expires_in"].int() ?: 3600

        // Resolve the account before saving anything: a login without a
        // username used to be stored as a placeholder account that broke later.
        val username = fetchUsername(accessToken) ?: fetchUsername(accessToken)
            ?: throw AuthException("Signed in, but couldn't load your Reddit username. Check your connection and try again.")

        store.saveTokens(accessToken, refreshToken, System.currentTimeMillis() + (expiresIn - 60) * 1000L)
        store.saveUsername(username)
        store.saveCredentials(clientId = cid, redirectUri = redirect, giphyKey = store.giphyKey())
        return username
    }

    /**
     * Website-session login (no API key). The UI captures reddit.com cookies
     * in a WebView; verify them by fetching the logged-in user (which also
     * yields the modhash for write actions) and persist the session.
     */
    suspend fun completeWebLogin(cookie: String): Pair<String, String?> {
        val req = Request.Builder().url("${RedditConstants.WEB_API_BASE}/api/me.json")
            .header("cookie", cookie)
            .header("User-Agent", RedditConstants.WEB_USER_AGENT)
            .build()
        val body = try {
            http.await(req).use { res -> withContext(Dispatchers.IO) { res.body.string() } }
        } catch (e: IOException) {
            throw AuthException("Could not reach Reddit: ${e.message}")
        }
        val data = runCatching { AppJson.parseToJsonElement(body) }.getOrNull()["data"]
        val username = data["name"].str()
        val modhash = data["modhash"].str()
        if (username.isNullOrEmpty()) {
            throw AuthException("Reddit login didn't complete. Please finish signing in and try again.")
        }
        store.saveWebSession(username, cookie, modhash)
        return username to modhash
    }

    private suspend fun fetchUsername(accessToken: String): String? = try {
        val req = Request.Builder().url("${RedditConstants.OAUTH_API_BASE}/api/v1/me")
            .header("Authorization", "bearer $accessToken")
            .header("User-Agent", RedditConstants.userAgent(null))
            .build()
        http.await(req).use { res ->
            if (!res.isSuccessful) null
            else AppJson.parseToJsonElement(withContext(Dispatchers.IO) { res.body.string() })["name"].str()
        }
    } catch (_: Exception) {
        null
    }

    /**
     * Starts browsing without an account, using [clientId]'s app-only token
     * (Reddit's "installed client" grant). Throws [AuthException] if refused.
     */
    suspend fun startAnonymous(clientId: String) {
        val cid = clientId.trim()
        appOnlyToken(cid) ?: throw AuthException(
            "Reddit didn't accept this Client ID. Check it, and that the app type is \"installed app\".",
        )
        store.saveAnonymousSession()
        store.saveCredentials(clientId = cid, redirectUri = RedditConstants.DEFAULT_REDIRECT_URI, giphyKey = store.giphyKey())
    }

    /** Fetches and stores an app-only access token for [clientId]; null if refused/unreachable. */
    private suspend fun appOnlyToken(clientId: String): String? = try {
        val (code, data) = tokenRequest(
            clientId,
            mapOf(
                "grant_type" to RedditConstants.INSTALLED_CLIENT_GRANT,
                "device_id" to RedditConstants.VALIDATION_DEVICE_ID,
            ),
        )
        val token = if (code == 200) data["access_token"].str() else null
        if (token != null) {
            val expiresIn = data["expires_in"].int() ?: 3600
            store.saveTokens(token, null, System.currentTimeMillis() + (expiresIn - 60) * 1000L)
        }
        token
    } catch (_: Exception) {
        null
    }

    // Single-flight guard: concurrent 401s share one in-flight refresh so the
    // refresh token isn't spent multiple times in parallel.
    private val refreshLock = Mutex()
    @Volatile private var refreshing: Deferred<String?>? = null
    private val refreshScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /** Refreshes the access token. Returns it, or null if refresh isn't possible (re-login). */
    suspend fun refresh(): String? {
        val job = refreshLock.withLock {
            // Its own scope, so one caller being cancelled doesn't fail the rest.
            refreshing?.takeIf { it.isActive } ?: refreshScope.async { doRefresh() }.also { refreshing = it }
        }
        return job.await()
    }

    private suspend fun doRefresh(): String? {
        val refreshToken = store.refreshToken()
        val clientId = store.clientId()
        // Browsing without an account: app-only tokens can't be refreshed,
        // so mint a new one the same way.
        if (refreshToken == null && clientId != null && store.authMode() == "anon") return appOnlyToken(clientId)
        if (refreshToken == null || clientId == null) return null
        return try {
            val (code, data) = tokenRequest(
                clientId,
                mapOf("grant_type" to RedditConstants.GRANT_REFRESH_TOKEN, "refresh_token" to refreshToken),
                username = store.username(),
            )
            if (code != 200) return null
            val accessToken = data["access_token"].str() ?: return null
            val expiresIn = data["expires_in"].int() ?: 3600
            store.saveTokens(accessToken, null, System.currentTimeMillis() + (expiresIn - 60) * 1000L)
            accessToken
        } catch (_: Exception) {
            null
        }
    }

    companion object {
        // A fixed, opaque CSRF state value checked on the redirect.
        private const val STATE = "luli_oauth_state"
    }
}

