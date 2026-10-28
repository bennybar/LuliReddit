package com.bennybar.luli_for_reddit.core.net

import com.bennybar.luli_for_reddit.core.AppJson
import com.bennybar.luli_for_reddit.core.RedditConstants
import com.bennybar.luli_for_reddit.core.get
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.util.Base64

// Website sign-in sends the cookies captured at login. Their `token_v2` (a
// JWT, valid for about a day) is also the bearer token for Reddit's app
// GraphQL API, which search needs (RedditClient.gql). Page loads stopped
// renewing it in October 2026, but a request to the website that carries no
// token_v2 still gets a new one.

/** The value of cookie [name] in a Cookie header. */
fun cookieValue(header: String, name: String): String? =
    header.split(';').map { it.trim() }.firstOrNull { it.startsWith("$name=") }?.substring(name.length + 1)

/** [header] with cookie [name] set to [value] (in place), or removed when [value] is null. */
fun withCookie(header: String, name: String, value: String?): String {
    val parts = header.split(';').map { it.trim() }.filter { it.isNotEmpty() }.toMutableList()
    val i = parts.indexOfFirst { it.startsWith("$name=") }
    when {
        value == null -> if (i >= 0) parts.removeAt(i)
        i >= 0 -> parts[i] = "$name=$value"
        else -> parts.add("$name=$value")
    }
    return parts.joinToString("; ")
}

/** When a token_v2 JWT expires (epoch millis); null if it can't be read. */
fun tokenExpiry(token: String): Long? = runCatching {
    val payload = String(Base64.getUrlDecoder().decode(token.split('.')[1].trimEnd('=')))
    // A number of seconds, with a fraction in Reddit's tokens.
    (AppJson.parseToJsonElement(payload)["exp"] as? JsonPrimitive)?.doubleOrNull?.let { (it * 1000).toLong() }
}.getOrNull()

/** Whether [cookieHeader]'s token_v2 is missing or expires within 5 minutes. */
fun needsNewToken(cookieHeader: String, now: Long = System.currentTimeMillis()): Boolean {
    val expiry = cookieValue(cookieHeader, "token_v2")?.let(::tokenExpiry)
    return expiry == null || expiry < now + 5 * 60_000
}

/** [header] with the cookies a response's Set-Cookie headers set (a deleted or emptied cookie is left out). */
fun mergeSetCookies(header: String, setCookies: List<String>): String {
    var out = header
    for (sc in setCookies) {
        val pair = sc.substringBefore(';')
        val i = pair.indexOf('=')
        if (i <= 0) continue
        val value = pair.substring(i + 1).trim()
        val gone = value.isEmpty() || sc.lowercase().contains("max-age=0")
        out = withCookie(out, pair.substring(0, i).trim(), if (gone) null else value)
    }
    return out
}

/**
 * Gets a new token_v2 for [cookieHeader]'s session: the page (which sets it,
 * with loid, csrf_token…), then the website's GraphQL proxy, which also sets
 * it even though it rejects the empty request. Returns the updated header,
 * or null when Reddit didn't issue a fresh token.
 */
suspend fun renewWebToken(cookieHeader: String): String? {
    // Reddit only issues a token to a request that doesn't carry one.
    var cookie = withCookie(cookieHeader, "token_v2", null)
    fun request(url: String) = Request.Builder().url(url)
        .header("cookie", cookie)
        .header("User-Agent", RedditConstants.WEB_USER_AGENT)
    try {
        Http.client.await(request("${RedditConstants.WEB_API_BASE}/").head().build()).use { res ->
            cookie = mergeSetCookies(cookie, res.headers("set-cookie"))
        }
        val proxy = request("${RedditConstants.WEB_API_BASE}/svc/shreddit/graphql")
            .header("Accept", "application/json")
            .post("{}".toRequestBody(JSON))
            .build()
        Http.client.await(proxy).use { res -> cookie = mergeSetCookies(cookie, res.headers("set-cookie")) }
    } catch (_: IOException) {
        return null
    }
    return if (needsNewToken(cookie)) null else cookie
}

private val JSON = "application/json".toMediaType()
