package com.bennybar.luli_for_reddit.nav

import kotlinx.serialization.Serializable

/**
 * Every screen. Type-safe Navigation Compose destinations; objects that
 * can't travel in a route (a Post, an InboxItem) go through [NavCache] and
 * the route carries their id.
 */
@Serializable
sealed interface Route {
    @Serializable data object Login : Route
    /** Website-session sign-in. [clearFirst] wipes existing cookies so you can sign into a *different* account (add account). */
    @Serializable data class WebLogin(val clearFirst: Boolean = false) : Route
    @Serializable data object Home : Route
    @Serializable data object Settings : Route
    @Serializable data object ManageForYou : Route
    @Serializable data object ContentFilters : Route
    @Serializable data object Policy : Route
    @Serializable data object History : Route
    @Serializable data object Saved : Route
    @Serializable data object Offline : Route
    @Serializable data class Search(val subreddit: String? = null, val query: String? = null) : Route
    @Serializable data class Submit(val subreddit: String? = null) : Route
    /** A private-message thread; the root InboxItem is in [NavCache] under [fullname]. */
    @Serializable data class MessageThread(val fullname: String) : Route
    @Serializable data class ComposeMessage(val to: String? = null) : Route
    @Serializable data class Subreddit(val name: String) : Route
    @Serializable data class User(val username: String) : Route
    @Serializable data class Multireddit(val username: String, val name: String) : Route
    @Serializable data class ManageMultireddit(val username: String, val name: String) : Route
    /** A post + comments. The already-loaded Post (if any) is in [NavCache] under [postId]. */
    @Serializable data class Post(val subreddit: String, val postId: String, val focusCommentId: String? = null) : Route
}

/** Hands non-serializable objects (posts, inbox items) to the next screen. */
object NavCache {
    private val map = object : LinkedHashMap<String, Any>(64, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Any>?) = size > 200
    }

    fun put(key: String, value: Any) = synchronized(map) { map[key] = value }

    @Suppress("UNCHECKED_CAST")
    fun <T> get(key: String): T? = synchronized(map) { map[key] as? T }
}
