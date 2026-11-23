package com.bennybar.luli_for_reddit.feature.home

import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Forum
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.nav.Route

/** Ilay's own subreddit: news, help, bug reports and ideas. */
const val ILAY_SUBREDDIT = "IlayFR"
private const val ANNOUNCED_PREF = "ilaySubredditAnnounced"

/** Already a member (as far as the loaded subscriptions know). */
fun inIlaySubreddit(): Boolean = app.repository.loadedSubscriptions?.any { it.name.equals(ILAY_SUBREDDIT, ignoreCase = true) } == true

/** Joins r/IlayFR (signed out, or already in: opens it), with Open on the snackbar. */
suspend fun joinIlaySubreddit() {
    val nav = app.navigator
    val signedIn = app.session.session?.anonymous == false
    if (!signedIn || inIlaySubreddit()) {
        nav.push(Route.Subreddit(ILAY_SUBREDDIT))
        return
    }
    try {
        app.repository.setSubscribed(ILAY_SUBREDDIT, true)
        nav.showSnackbar("Joined r/$ILAY_SUBREDDIT", actionLabel = "Open") { nav.push(Route.Subreddit(ILAY_SUBREDDIT)) }
    } catch (e: Exception) {
        nav.showActionError("join r/$ILAY_SUBREDDIT", e)
    }
}

/** Once, on a launch: Ilay has a subreddit. Join (or Open, signed out), or Not now; never asked again. */
internal suspend fun maybeAnnounceIlaySubreddit() {
    if (app.prefs.getBool(ANNOUNCED_PREF) == true) return
    app.prefs.setBool(ANNOUNCED_PREF, true)
    val signedIn = app.session.session?.anonymous == false
    // Members aren't asked (the list is usually loaded already, for Explore).
    if (signedIn && runCatching { app.repository.loadedSubscriptions ?: app.repository.getSubscribedSubreddits() }.getOrNull()
            ?.any { it.name.equals(ILAY_SUBREDDIT, ignoreCase = true) } == true
    ) return
    val join = com.bennybar.luli_for_reddit.ui.Overlays.show<Boolean> { done ->
        AlertDialog(
            onDismissRequest = { done(false) },
            icon = { Icon(Icons.Outlined.Forum, null, Modifier.size(36.dp)) },
            title = { Text("Ilay has a subreddit") },
            text = {
                Text(
                    "r/$ILAY_SUBREDDIT is the place for Ilay news, help, bug reports and ideas." +
                        (if (signedIn) " Join to see it in your feed." else "") +
                        "\n\nYou can join anytime from Settings › About.",
                )
            },
            dismissButton = { TextButton(onClick = { done(false) }) { Text("Not now") } },
            confirmButton = { Button(onClick = { done(true) }) { Text(if (signedIn) "Join" else "Open") } },
        )
    }
    if (join == true) joinIlaySubreddit()
}
