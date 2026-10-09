package com.bennybar.luli_for_reddit.core

import android.content.Context
import android.content.Intent
import android.net.Uri
import com.bennybar.luli_for_reddit.core.net.Http
import com.bennybar.luli_for_reddit.nav.Route
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.Request

/** True for reddit.com / *.reddit.com / redd.it / *.redd.it (media) hosts. */
fun isRedditHost(host: String?): Boolean {
    val h = host?.lowercase() ?: return false
    return h == "redd.it" || h.endsWith(".redd.it") || h == "reddit.com" || h.endsWith(".reddit.com")
}

/**
 * A VIEW intent for [uri] outside Ilay. When Ilay is set to open Reddit links
 * by default, a plain VIEW of a reddit.com / redd.it URL would land straight
 * back in Ilay, so those go to the default web browser explicitly.
 */
fun externalViewIntent(context: Context, uri: Uri): Intent {
    val intent = Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    if (!isRedditHost(uri.host)) return intent
    val pm = context.packageManager
    val probe = Intent(Intent.ACTION_VIEW, Uri.parse("https://example.com"))
    val browser = pm.resolveActivity(probe, 0)?.activityInfo?.packageName?.takeIf { it != context.packageName && it != "android" }
        ?: pm.queryIntentActivities(probe, 0).map { it.activityInfo.packageName }.firstOrNull { it != context.packageName }
    browser?.let(intent::setPackage)
    return intent
}

/** Reddit's media hosts (i.redd.it, v.redd.it, preview.redd.it…): open in the image / video viewer. */
fun isRedditMediaHost(host: String?): Boolean = host?.lowercase()?.endsWith(".redd.it") == true

/** A share link (`reddit.com/r/<sub>/s/<code>`): it only redirects to the real post / comment URL. */
fun isShareLink(uri: Uri): Boolean {
    if (!isRedditHost(uri.host)) return false
    val s = uri.pathSegments.filter { it.isNotEmpty() }
    return s.size >= 4 && s[0] == "r" && s[2] == "s"
}

/** Follows a [isShareLink] URL's redirects (up to 3) to the link it stands for; null if it can't. */
suspend fun resolveShareLink(uri: Uri): Uri? = withContext(Dispatchers.IO) {
    val client = Http.client.newBuilder().followRedirects(false).followSslRedirects(false).build()
    var url = uri.toString()
    repeat(3) {
        val next = runCatching {
            client.newCall(Request.Builder().url(url).head().build()).execute().use { it.header("location") }
        }.getOrNull() ?: return@withContext null
        val target = if (next.startsWith("/")) "https://www.reddit.com$next" else next
        val u = Uri.parse(target)
        if (!isShareLink(u)) return@withContext u
        url = target
    }
    null
}

/** Maps a reddit.com / redd.it URL to an in-app route, or null if unsupported. */
fun routeForRedditUrl(uri: Uri): Route? {
    val host = uri.host?.lowercase() ?: return null
    val segs = uri.pathSegments.filter { it.isNotEmpty() }

    // Short links: redd.it/<postId>
    if (host == "redd.it") return segs.firstOrNull()?.let { Route.Post("_", it) }
    if (!(host == "reddit.com" || host.endsWith(".reddit.com"))) return null

    // Comment / post permalinks: /r/<sub>/comments/<id>/<slug>/<commentId> or
    // /comments/<id>. A segment after the title slug is a focused comment.
    val ci = segs.indexOf("comments")
    if (ci != -1 && ci + 1 < segs.size) {
        val id = segs[ci + 1]
        val sub = if (ci >= 2 && segs[ci - 2] == "r") segs[ci - 1] else "_"
        val commentId = if (segs.size > ci + 3) segs[ci + 3] else null
        return Route.Post(sub, id, focusCommentId = commentId)
    }

    // Gallery: /gallery/<id> is the post itself.
    if (segs.size >= 2 && segs[0] == "gallery") return Route.Post("_", segs[1])
    // A share link must be resolved first (resolveShareLink): /r/<sub>/s/<code>
    // is a post, not the subreddit.
    if (segs.size >= 4 && segs[0] == "r" && segs[2] == "s") return null

    // Multireddit: /user/<name>/m/<multi>
    if (segs.size >= 4 && (segs[0] == "user" || segs[0] == "u") && segs[2] == "m") {
        return Route.Multireddit(segs[1], segs[3])
    }
    // User: /u/<name> or /user/<name>
    if (segs.size >= 2 && (segs[0] == "u" || segs[0] == "user")) return Route.User(segs[1])
    // Subreddit: /r/<sub>
    if (segs.size >= 2 && segs[0] == "r") return Route.Subreddit(segs[1])
    return null
}
