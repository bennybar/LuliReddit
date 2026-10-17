package com.bennybar.luli_for_reddit.core.net

import android.webkit.CookieManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlin.coroutines.resume

private const val REDDIT = "https://www.reddit.com/"

/**
 * Puts the active website session ([cookieHeader]) in the WebView cookie jar,
 * which every WebView shares (hidden Home, signed-in pages). The jar may hold
 * a different account's session (the last one that signed in through it).
 */
suspend fun loadWebSessionCookies(cookieHeader: String) = withContext(Dispatchers.Main) {
    val jar = CookieManager.getInstance()
    suspend fun set(cookie: String) = suspendCancellableCoroutine { cont ->
        jar.setCookie(REDDIT, cookie) { if (cont.isActive) cont.resume(Unit) }
    }
    fun session(header: String?) = header?.split(';')
        ?.firstOrNull { it.trim().startsWith("reddit_session=") }?.trim()
    // Same account already in the jar: keep it as is. Wiping it also threw
    // away the cookies Reddit set when the page passed its browser check,
    // so every launch had to pass that check again (an extra page load).
    if (session(jar.getCookie(REDDIT)) != session(cookieHeader)) {
        for (part in jar.getCookie(REDDIT)?.split(';') ?: emptyList()) {
            val name = part.substringBefore('=').trim()
            if (name.isEmpty()) continue
            set("$name=; Domain=.reddit.com; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT")
            set("$name=; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT")
        }
        for (part in cookieHeader.split(';')) {
            val i = part.indexOf('=')
            if (i <= 0) continue
            val name = part.substring(0, i).trim()
            val value = part.substring(i + 1).trim()
            set("$name=$value; Domain=.reddit.com; Path=/; Secure")
        }
    }
    jar.flush()
}
