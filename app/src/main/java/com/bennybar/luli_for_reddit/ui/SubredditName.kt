package com.bennybar.luli_for_reddit.ui

import com.bennybar.luli_for_reddit.app

/**
 * A subreddit's name as it shows on screen (#97): "r/pics", or just "pics"
 * with Settings → Appearance → "r/ before subreddit names" off. Takes the
 * bare name or the prefixed one; a user's profile ("u/name") stays as it is.
 * Display only: links, search syntax and anything sent to Reddit keep the "r/".
 */
fun subredditName(name: String, prefix: Boolean = app.settings.value.subredditPrefix): String {
    val bare = name.removePrefix("r/")
    return if (!prefix || bare.startsWith("u/")) bare else "r/$bare"
}
