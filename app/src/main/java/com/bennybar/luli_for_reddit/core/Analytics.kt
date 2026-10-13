package com.bennybar.luli_for_reddit.core

import android.content.Context
import android.os.Build
import com.bennybar.luli_for_reddit.BuildConfig
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.core.net.Http
import com.bennybar.luli_for_reddit.core.net.await
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.time.Instant
import java.util.Locale
import java.util.concurrent.atomic.AtomicInteger
import kotlin.random.Random

/**
 * Privacy-friendly, anonymous usage analytics via Aptabase (the same app key
 * and event shape as the Flutter SDK). No ad IDs, no personal data — just
 * anonymous sessions plus OS/app version and the few events we track.
 * Disabled (a no-op) when [APP_KEY] is empty or the user turned it off
 * (Settings → About → Send anonymous usage stats).
 *
 * Counts are sent in coarse buckets ("2-5"), never exact, and nothing names
 * the user, a subreddit or a post.
 */
object Analytics {
    private const val APP_KEY = "A-US-2578531885"
    private const val SDK_VERSION = "aptabase_kotlin@ilay"
    /** The server for a self-hosted Aptabase ("A-SH-…" key), e.g. "https://stats.example.com". */
    private const val SELF_HOST = ""
    private const val SESSION_TIMEOUT_MS = 60 * 60 * 1000L

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var sessionId = newSessionId()
    private var lastTouch = System.currentTimeMillis()
    private lateinit var locale: String

    val enabled: Boolean get() = APP_KEY.isNotEmpty()

    private val apiUrl: String?
        get() = when (APP_KEY.split("-").getOrNull(1)) {
            "EU" -> "https://eu.aptabase.com/api/v0/events"
            "US" -> "https://us.aptabase.com/api/v0/events"
            "SH" -> SELF_HOST.trimEnd('/').takeIf { it.isNotEmpty() }?.let { "$it/api/v0/events" }
            else -> null
        }

    fun init(context: Context) {
        locale = context.resources.configuration.locales[0]?.toLanguageTag() ?: Locale.getDefault().toLanguageTag()
    }

    private fun newSessionId(): String =
        "${System.currentTimeMillis() / 1000}${Random.nextLong(10_000_000, 99_999_999)}"

    @Synchronized
    private fun evalSessionId(): String {
        val now = System.currentTimeMillis()
        if (now - lastTouch > SESSION_TIMEOUT_MS) sessionId = newSessionId()
        lastTouch = now
        return sessionId
    }

    /** Records an anonymous event (no-op when disabled). */
    fun track(event: String, props: Map<String, Any?> = emptyMap()) {
        val url = apiUrl ?: return
        if (!enabled || !app.settings.value.analytics) return
        val body = buildJsonObject {
            put("timestamp", Instant.now().toString())
            put("sessionId", evalSessionId())
            put("eventName", event)
            put("systemProps", buildJsonObject {
                put("isDebug", BuildConfig.DEBUG)
                put("osName", "Android")
                put("osVersion", Build.VERSION.RELEASE)
                put("locale", if (::locale.isInitialized) locale else "en")
                put("appVersion", BuildConfig.VERSION_NAME)
                put("appBuildNumber", BuildConfig.VERSION_CODE.toString())
                put("sdkVersion", SDK_VERSION)
            })
            put("props", buildJsonObject {
                props.forEach { (k, v) ->
                    when (v) {
                        null -> {}
                        is Number -> put(k, v)
                        is Boolean -> put(k, v)
                        else -> put(k, v.toString())
                    }
                }
            })
        }
        scope.launch {
            runCatching {
                Http.client.await(
                    Request.Builder().url(url)
                        .header("App-Key", APP_KEY)
                        .header("User-Agent", SDK_VERSION)
                        .post(JsonArray(listOf(body)).toString().toRequestBody("application/json; charset=UTF-8".toMediaType()))
                        .build(),
                ).close()
            }
        }
    }

    // Posts opened since the app last went to the background: sent as one
    // event per visit instead of one per post, to keep the event count low.
    private val postsOpened = AtomicInteger()

    fun postOpened() {
        postsOpened.incrementAndGet()
    }

    /** The app went to the background: sends this visit's posts-opened count. */
    fun flushPostsOpened() {
        val n = postsOpened.getAndSet(0)
        if (n > 0) track("posts_opened", mapOf("count" to bucket(n, 1, 5, 20)))
    }

    /** [n] as a coarse range, e.g. bucket(3, 1, 5, 20) = "2-5"; [edges] ascending. */
    fun bucket(n: Int, vararg edges: Int): String {
        var low = 0
        for (e in edges) {
            if (n <= e) return if (low + 1 >= e) "$e" else "${low + 1}-$e"
            low = e
        }
        return "${low + 1}+"
    }
}
