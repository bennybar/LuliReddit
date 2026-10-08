package com.bennybar.luli_for_reddit.core.net

import android.net.Uri
import com.bennybar.luli_for_reddit.core.AppJson
import com.bennybar.luli_for_reddit.core.get
import com.bennybar.luli_for_reddit.core.str
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.Request
import java.util.concurrent.TimeUnit

// RedGifs links point at a web page, not a playable file. Their public API
// hands out an anonymous temporary token, which then resolves a clip id to
// its HD (with sound) / SD mp4.
object Redgifs {
    private val client by lazy {
        Http.client.newBuilder().connectTimeout(8, TimeUnit.SECONDS).readTimeout(8, TimeUnit.SECONDS).build()
    }
    @Volatile private var token: String? = null

    /** The clip id in a RedGifs URL (`/watch/<id>`, `/ifr/<id>`, `i.redgifs.com/i/<id>.jpg`). */
    fun id(url: String): String? {
        val u = runCatching { Uri.parse(url) }.getOrNull() ?: return null
        if (u.host?.lowercase()?.endsWith("redgifs.com") != true) return null
        val segs = u.pathSegments.filter { it.isNotEmpty() }
        if (segs.size < 2 || segs[0] !in setOf("watch", "ifr", "i")) return null
        return segs[1].substringBefore('.').substringBefore('-').lowercase().ifEmpty { null }
    }

    /** The best playable mp4 for a RedGifs URL, or null if it can't be resolved. */
    suspend fun resolve(url: String): String? = withContext(Dispatchers.IO) {
        val id = id(url) ?: return@withContext null
        // One retry with a fresh token: temporary tokens expire (~24h).
        repeat(2) {
            try {
                val t = token ?: client.newCall(Request.Builder().url("https://api.redgifs.com/v2/auth/temporary").build())
                    .execute().use { AppJson.parseToJsonElement(it.body.string())["token"].str() }
                    ?.also { token = it } ?: return@withContext null
                client.newCall(
                    Request.Builder().url("https://api.redgifs.com/v2/gifs/$id").header("Authorization", "Bearer $t").build(),
                ).execute().use { res ->
                    if (res.code == 401) {
                        token = null
                        return@repeat
                    }
                    if (!res.isSuccessful) return@withContext null
                    val urls = AppJson.parseToJsonElement(res.body.string())["gif"]["urls"]
                    return@withContext urls["hd"].str() ?: urls["sd"].str()
                }
            } catch (_: Exception) {
                return@withContext null
            }
        }
        null
    }
}
