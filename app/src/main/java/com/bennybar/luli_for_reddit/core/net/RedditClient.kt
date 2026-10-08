package com.bennybar.luli_for_reddit.core.net

import com.bennybar.luli_for_reddit.auth.AuthRepository
import com.bennybar.luli_for_reddit.core.AppJson
import com.bennybar.luli_for_reddit.core.RedditConstants
import com.bennybar.luli_for_reddit.core.get
import com.bennybar.luli_for_reddit.core.storage.SecureStore
import com.bennybar.luli_for_reddit.core.str
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonElement
import okhttp3.FormBody
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import java.io.IOException

/**
 * A non-2xx answer from Reddit. [reason] is Reddit's machine-readable cause
 * when it sends one, e.g. "private", "banned" or "quarantined".
 */
class RedditApiException(val statusCode: Int, val reason: String? = null, override val message: String? = null) :
    Exception("HTTP $statusCode${if (reason != null) " ($reason)" else ""}") {
    override fun toString(): String = "HTTP $statusCode${if (reason != null) " ($reason)" else ""}"
}

/** A GET result: the JSON body and whether it was served from the offline cache. */
data class ApiResult(val json: JsonElement, val fromCache: Boolean = false)

/**
 * Authenticated client for oauth.reddit.com. Attaches the bearer token, a
 * compliant User-Agent and `raw_json=1`, transparently refreshes the access
 * token once on a 401, surfaces rate-limit headers, serves a disk-cache copy
 * when offline, and in website-session mode talks to www.reddit.com like a
 * logged-in browser instead.
 */
class RedditClient(
    private val store: SecureStore,
    private val auth: AuthRepository,
    private val cache: ResponseCache,
    private val onRateLimit: (RateLimit) -> Unit,
    private val cacheEnabled: () -> Boolean,
) {
    private val http = Http.client

    // Auth-mode config, lazily loaded and refreshed on login / switch / resume.
    private val configLock = Mutex()
    @Volatile private var configured = false
    @Volatile private var webMode = false
    @Volatile private var webCookie: String? = null
    @Volatile private var webModhash: String? = null
    // Prefix for response-cache keys, so one account's cached pages are never
    // served to another.
    @Volatile private var cacheUser = ""
    // Held in memory rather than read from encrypted storage on every request.
    @Volatile private var username = ""
    @Volatile private var token: String? = null
    @Volatile private var tokenExpiry: Long? = null

    /** Force a re-read of the auth mode on the next request (login / account switch). */
    fun invalidateAuthConfig() {
        configured = false
        token = null
        tokenExpiry = null
    }

    private suspend fun ensureConfig() {
        if (configured) return
        configLock.withLock {
            if (configured) return
            webMode = store.authMode() == "web"
            webCookie = if (webMode) store.webCookie() else null
            webModhash = if (webMode) store.webModhash() else null
            username = store.username() ?: ""
            cacheUser = username.lowercase()
            configured = true
        }
    }

    /** The request URL for the current mode. Web mode appends `.json` to listing GETs. */
    private fun reqUrl(path: String, isGet: Boolean): String {
        if (!webMode) return RedditConstants.OAUTH_API_BASE + path
        val base = RedditConstants.WEB_API_BASE
        return if (isGet && !path.contains("/api/")) "$base$path.json" else "$base$path"
    }

    private suspend fun validToken(): String {
        if (token == null) {
            token = store.accessToken()
            tokenExpiry = store.tokenExpiry()
        }
        val expiry = tokenExpiry
        val expired = expiry == null || System.currentTimeMillis() > expiry
        if (token.isNullOrEmpty() || expired) {
            auth.refresh()?.let {
                token = it
                tokenExpiry = store.tokenExpiry()
                return it
            }
        }
        return token ?: ""
    }

    private suspend fun authorize(b: Request.Builder, method: String): Request.Builder {
        if (webMode) {
            b.header("User-Agent", RedditConstants.WEB_USER_AGENT)
            webCookie?.let { b.header("cookie", it) }
            if (method != "GET") webModhash?.let { b.header("X-Modhash", it) }
        } else {
            b.header("Authorization", "bearer ${validToken()}")
            b.header("User-Agent", RedditConstants.userAgent(username.ifEmpty { null }))
        }
        return b
    }

    private fun buildUrl(path: String, isGet: Boolean, query: Map<String, Any?>): String {
        val url = reqUrl(path, isGet).toHttpUrl().newBuilder()
        for ((k, v) in query) if (v != null) url.addQueryParameter(k, v.toString())
        url.addQueryParameter("raw_json", "1")
        return url.build().toString()
    }

    private fun captureRateLimit(res: Response) {
        val rem = res.header("x-ratelimit-remaining") ?: return
        onRateLimit(
            RateLimit(
                remaining = rem.toDoubleOrNull()?.toInt() ?: 0,
                used = res.header("x-ratelimit-used")?.toDoubleOrNull()?.toInt() ?: 0,
                resetSeconds = res.header("x-ratelimit-reset")?.toDoubleOrNull()?.toInt() ?: 0,
            ),
        )
    }

    /**
     * Executes [method] on [url], refreshing the token and retrying once on a
     * 401 (OAuth mode). Returns status + body text.
     */
    private suspend fun execute(method: String, url: String, body: RequestBody?): Pair<Int, String> {
        suspend fun once(): Pair<Int, String> {
            val req = authorize(Request.Builder().url(url).method(method, body), method).build()
            http.await(req).use { res ->
                captureRateLimit(res)
                return res.code to withContext(Dispatchers.IO) { res.body.string() }
            }
        }
        val first = once()
        if (!webMode && first.first == 401) {
            val newToken = auth.refresh()
            if (newToken != null) {
                token = newToken
                tokenExpiry = store.tokenExpiry()
                return once()
            }
        }
        return first
    }

    /**
     * 4xx/5xx is a real failure: throw, so optimistic UI rolls back and
     * screens show an error instead of treating the error body as empty.
     */
    private fun parseOrThrow(status: Int, text: String): JsonElement? {
        val json = if (text.isBlank()) null else runCatching { AppJson.parseToJsonElement(text) }.getOrNull()
        if (status >= 400) {
            throw RedditApiException(status, reason = json["reason"].str(), message = json["message"].str())
        }
        return json
    }

    private val cacheOn: Boolean get() = cacheEnabled()

    /** Cache key; same shape as the Flutter build's so its cache carries over. */
    private fun cacheKey(path: String, query: Map<String, Any?>): String =
        "$cacheUser|$path?" + query.entries.filter { it.value != null }.joinToString("&") { "${it.key}=${it.value}" }

    /**
     * The last cached response for this exact request, without touching the
     * network — so a feed can paint instantly and replace it when the network
     * answers.
     */
    suspend fun cached(path: String, query: Map<String, Any?> = emptyMap()): JsonElement? {
        if (!cacheOn) return null
        ensureConfig()
        return cache.read(cacheKey(path, query))
    }

    /**
     * GET [path] (relative to the API base). Retries once on a network error
     * (a stale socket dies on the first attempt), then falls back to the
     * offline cache when enabled.
     */
    suspend fun getResult(path: String, query: Map<String, Any?> = emptyMap()): ApiResult {
        ensureConfig()
        val url = buildUrl(path, isGet = true, query)
        var lastError: IOException? = null
        for (attempt in 0 until 2) {
            try {
                val (status, text) = execute("GET", url, null)
                val json = parseOrThrow(status, text)
                    ?: throw RedditApiException(status, message = "Unexpected response from Reddit (HTTP $status). Please try again.")
                if (cacheOn && status == 200) cache.write(cacheKey(path, query), text)
                return ApiResult(json)
            } catch (e: IOException) {
                lastError = e
                if (attempt == 0) delay(250)
            }
        }
        if (cacheOn) cache.read(cacheKey(path, query))?.let { return ApiResult(it, fromCache = true) }
        throw lastError!!
    }

    suspend fun get(path: String, query: Map<String, Any?> = emptyMap()): JsonElement = getResult(path, query).json

    /** Form-encoded POST. */
    suspend fun post(path: String, data: Map<String, Any?> = emptyMap()): JsonElement? {
        ensureConfig()
        val form = FormBody.Builder().apply {
            for ((k, v) in data) if (v != null) add(k, v.toString())
        }.build()
        val (status, text) = execute("POST", buildUrl(path, isGet = false, emptyMap()), form)
        return parseOrThrow(status, text)
    }

    /** POST with a JSON body (submit_gallery_post, multireddit APIs). */
    suspend fun postJson(path: String, json: String): JsonElement? {
        ensureConfig()
        val (status, text) = execute("POST", buildUrl(path, isGet = false, emptyMap()), json.toRequestBody(JSON))
        return parseOrThrow(status, text)
    }

    suspend fun put(path: String, json: String): JsonElement? {
        ensureConfig()
        val (status, text) = execute("PUT", buildUrl(path, isGet = false, emptyMap()), json.toRequestBody(JSON))
        return parseOrThrow(status, text)
    }

    suspend fun delete(path: String, query: Map<String, Any?> = emptyMap()): JsonElement? {
        ensureConfig()
        val (status, text) = execute("DELETE", buildUrl(path, isGet = false, query), null)
        return parseOrThrow(status, text)
    }

    suspend fun clearCache() = cache.clear()

    companion object {
        private val JSON = "application/json; charset=utf-8".toMediaType()
    }
}
