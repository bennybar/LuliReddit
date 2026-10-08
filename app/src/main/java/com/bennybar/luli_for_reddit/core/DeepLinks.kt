package com.bennybar.luli_for_reddit.core

import android.net.Uri
import com.bennybar.luli_for_reddit.nav.Route

/** True for reddit.com / *.reddit.com / redd.it hosts. */
fun isRedditHost(host: String?): Boolean {
    val h = host?.lowercase() ?: return false
    return h == "redd.it" || h == "reddit.com" || h.endsWith(".reddit.com")
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
