package com.bennybar.luli_for_reddit.ui

import com.bennybar.luli_for_reddit.app

/**
 * A subreddit's name as it shows on screen (#97): "r/pics", or just "pics"
 * with Settings → Appearance → "r/ and u/ before names" off. Takes the
 * bare name or the prefixed one; a user's profile ("u/name", or its "u_name" subreddit) shows as the user ([userName]).
 * Display only: links, search syntax and anything sent to Reddit keep the "r/".
 */
fun subredditName(name: String, prefix: Boolean = app.settings.value.subredditPrefix): String {
    val bare = name.removePrefix("r/")
    // A profile's own subreddit is "u_name": it reads as the user.
    if (bare.startsWith("u_")) return userName(bare.removePrefix("u_"), prefix)
    if (bare.startsWith("u/")) return userName(bare.removePrefix("u/"), prefix)
    return if (prefix) "r/$bare" else bare
}

/**
 * A user's name as it shows on posts, comments and profiles: "u/name", or just "name"
 * with the same setting off (#289). Display only, as [subredditName].
 */
fun userName(name: String, prefix: Boolean = app.settings.value.subredditPrefix): String {
    val bare = name.removePrefix("u/")
    return if (prefix) "u/$bare" else bare
}
