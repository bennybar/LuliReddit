package com.bennybar.luli_for_reddit.feature.digest

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Newspaper
import androidx.compose.material.icons.rounded.Star
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.model.Subreddit
import com.bennybar.luli_for_reddit.ui.Overlays
import com.bennybar.luli_for_reddit.ui.subredditName

/** "How Digest works" (the same words on both apps; keep them true to what's built). */
private val DIGEST_EXPLAINED = listOf(
    "What it is" to "The posts that stood out in the last 24 hours in the communities you choose, in one short list.",
    "How it picks" to "By how unusual a post is for its own community: its points and comments against what's " +
        "typical there. A small community's big day counts as much as a big one's, and a quiet day gives a short digest.",
    "What AI adds" to "With \"Use AI\" on, your own AI key picks and explains the posts, and can add a short overview. " +
        "One small request per digest, fewer on refresh since only new posts are sent. Post titles and the " +
        "topics you read go to the AI provider you set up. Nothing is sent unless you turn it on.",
    "Your communities" to "Your starred favourites, or up to ${DigestModule.MAX_COMMUNITIES} you choose.",
    "When it's built" to "When you open it, if it's more than 12 hours old. Pull down for what's new: it only adds " +
        "posts, nothing already there goes away.",
    "Where you'll find it" to "A Digest chip at the top of Posts, a tab in the bottom bar, or only the side bar and the Profile menu: your choice.",
    "Reading it" to "Swipe a post left to mark it read. Digests stay on this phone for 7 days, with what was already checked.",
)

/**
 * The explainer. [ask]: before Digest is first turned on, with Turn on / Not now
 * (true when turned on); otherwise just Close.
 */
suspend fun showDigestExplainer(ask: Boolean): Boolean = Overlays.show<Boolean> { done ->
    AlertDialog(
        onDismissRequest = { done(false) },
        icon = { Icon(Icons.Outlined.Newspaper, null, Modifier.size(36.dp), tint = MaterialTheme.colorScheme.primary) },
        title = { Text("How Digest works", textAlign = TextAlign.Center) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState())) {
                for ((i, part) in DIGEST_EXPLAINED.withIndex()) {
                    if (i > 0) Spacer(Modifier.height(10.dp))
                    Text(part.first, style = MaterialTheme.typography.titleSmall)
                    Text(part.second, style = MaterialTheme.typography.bodyMedium.copy(lineHeight = 20.sp))
                }
            }
        },
        dismissButton = if (ask) ({ TextButton(onClick = { done(false) }) { Text("Not now") } }) else null,
        confirmButton = {
            if (ask) Button(onClick = { done(true) }) { Text("Turn on") }
            else TextButton(onClick = { done(false) }) { Text("Close") }
        },
    )
} == true

/** Turning the Digest on: the explainer first, the first time. */
suspend fun setDigestEnabled(on: Boolean) {
    if (on && app.prefs.getBool(EXPLAINED_KEY) != true) {
        if (!showDigestExplainer(ask = true)) return
        app.prefs.setBool(EXPLAINED_KEY, true)
    }
    app.settings.setDigestEnabled(on)
}

private const val EXPLAINED_KEY = "digestExplained"

/**
 * The communities editor: your subscriptions, favourites first, as a checklist of at
 * most [DigestModule.MAX_COMMUNITIES]; "Use my favourites" follows your favourites again.
 */
suspend fun editDigestCommunities() {
    val subs = runCatching { app.repository.loadedSubscriptions ?: app.repository.getSubscribedSubreddits() }.getOrElse {
        app.navigator.showActionError("load your subscriptions", it)
        return
    }
    val sorted = subs.sortedWith(compareBy<Subreddit>({ !it.userHasFavorited }, { it.name.lowercase() }))
    val start = app.digest.chosen.value ?: sorted.filter { it.userHasFavorited }.map { it.name.lowercase() }.take(DigestModule.MAX_COMMUNITIES)
    // Some(list): save it; Some(null): follow favourites; null: cancelled.
    val result = Overlays.show<Pair<List<String>?, Unit>> { done ->
        var picked by remember { mutableStateOf(start.toSet()) }
        val full = picked.size >= DigestModule.MAX_COMMUNITIES
        AlertDialog(
            onDismissRequest = { done(null) },
            title = { Text("Digest communities") },
            text = {
                Column {
                    Text(
                        if (full) "That's ${DigestModule.MAX_COMMUNITIES}, the most a digest takes." else "${picked.size} of up to ${DigestModule.MAX_COMMUNITIES}",
                        fontSize = 13.sp,
                        color = if (full) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(Modifier.height(8.dp))
                    if (sorted.isEmpty()) Text("You haven't joined any communities yet.")
                    LazyColumn(Modifier.heightIn(max = 420.dp)) {
                        items(sorted, key = { it.name.lowercase() }) { s ->
                            val k = s.name.lowercase()
                            val on = k in picked
                            Row(
                                Modifier
                                    .fillMaxWidth()
                                    .clickable(enabled = on || !full) { picked = if (on) picked - k else picked + k }
                                    .padding(vertical = 2.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Checkbox(on, null, enabled = on || !full)
                                Text(subredditName(s.name), Modifier.weight(1f).padding(start = 8.dp), fontWeight = if (on) FontWeight.Medium else null)
                                if (s.userHasFavorited) Icon(Icons.Rounded.Star, "Favourite", Modifier.size(16.dp), tint = MaterialTheme.colorScheme.primary)
                            }
                        }
                    }
                }
            },
            dismissButton = { TextButton(onClick = { done(null to Unit) }) { Text("Use my favourites") } },
            confirmButton = { Button(onClick = { done(picked.toList() to Unit) }) { Text("Save") } },
        )
    } ?: return
    app.digest.setCommunities(result.first)
}

/** The Communities row's subtitle. */
fun digestCommunitiesLabel(chosen: List<String>?): String = when {
    chosen == null -> "Your favourites"
    chosen.isEmpty() -> "None chosen"
    chosen.size <= 3 -> chosen.joinToString { subredditName(it) }
    else -> "${chosen.size} communities"
}
