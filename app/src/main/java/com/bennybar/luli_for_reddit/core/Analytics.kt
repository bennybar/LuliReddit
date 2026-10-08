package com.bennybar.luli_for_reddit.core

import android.content.Context
import android.os.Build
import com.bennybar.luli_for_reddit.BuildConfig
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
import kotlin.random.Random

/**
 * Privacy-friendly, anonymous usage analytics via Aptabase (the same app key
 * and event shape as the Flutter SDK). No ad IDs, no personal data — just
 * anonymous sessions plus OS/app version and the few events we track.
 * Disabled (a no-op) when [APP_KEY] is empty.
 */
object Analytics {
    private const val APP_KEY = "A-US-2578531885"
    private const val SDK_VERSION = "aptabase_kotlin@ilay"
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
        if (!enabled) return
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

}
