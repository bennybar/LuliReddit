package com.bennybar.luli_for_reddit.feature.about

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bennybar.luli_for_reddit.BuildConfig
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.feature.feed.BloomTopBar
import com.bennybar.luli_for_reddit.nav.Route
import com.bennybar.luli_for_reddit.ui.Overlays

/** One release's highlights, as shown in What's new. */
class Release(val version: String, val date: String, val highlights: List<String>)

/**
 * What's new, newest first: the notable changes of each release since Ilay
 * 2.0 (the native app, with Reddit Home). Add the new release at the top
 * with every release.
 */
val CHANGELOG = listOf(
    Release(
        "2.0.34", "Oct 25, 2026",
        listOf(
            "User flairs next to names in posts and comments, and set your own flair from a community's About",
            "Custom feeds: one screen with all of them, rename, describe, make public or private, share, copy someone's public feed, and tap a community to open it",
            "A ⚙ button opens Settings directly; the Expandable top bar gets a search button",
            "Neater ☰ alignment and a cleaner New post icon",
        ),
    ),
    Release(
        "2.0.33", "Oct 22, 2026",
        listOf("And the other way: replies you opened in Reddit's notifications show as read in Ilay's Inbox (website sign-in)"),
    ),
    Release(
        "2.0.32", "Oct 22, 2026",
        listOf("With the website sign-in, replies you read in the Inbox are marked read in Reddit's notifications too (and Mark all read clears them there)"),
    ),
    Release(
        "2.0.31", "Oct 22, 2026",
        listOf("With the side bar on, swiping back on the main screen opens it, and back again closes it"),
    ),
    Release(
        "2.0.30", "Oct 22, 2026",
        listOf(
            "What's new: this list, once after each update, and any time in Settings → About",
            "Side bar navigation: Settings → Appearance → Navigation (bottom bar, side bar, or both)",
        ),
    ),
    Release(
        "2.0.29", "Oct 21, 2026",
        listOf(
            "AI summaries work with other providers (Groq, OpenRouter…) and any model ID",
            "Add a community to a custom feed from a post's ⋮ menu or the community's top bar",
            "Autoplay with sound, for feed videos (Settings → Media)",
        ),
    ),
    Release(
        "2.0.26 – 2.0.28", "Oct 18, 2026",
        listOf("Remind me about a saved post: pick when, get a notification, and see the reminder on the post"),
    ),
    Release(
        "2.0.24 – 2.0.25", "Oct 17, 2026",
        listOf(
            "Reddit's own notifications in the Inbox (website sign-in), with unread dots and older ones",
            "When Reddit rate-limits you, Ilay says how long to wait",
            "Select and delete several summaries at once",
        ),
    ),
    Release(
        "2.0.22 – 2.0.23", "Oct 17, 2026",
        listOf(
            "Profile tab: your posts, comments, saved and upvoted, with your stuff a tap away",
            "Settings moved to the ⋮ menu at the top of each tab",
            "Reddit Chat, voting in polls and Reddit's account settings (website sign-in)",
            "Poll results and your vote show in the post",
        ),
    ),
    Release(
        "2.0.20 – 2.0.21", "Oct 17, 2026",
        listOf(
            "Your votes stick when you go back into a thread or your profile",
            "Blend: choose Mostly Ilay, Balanced or Mostly Reddit",
            "Already seen elsewhere: drop a post you read in another app",
        ),
    ),
    Release(
        "2.0.19", "Oct 17, 2026",
        listOf(
            "Android 13 support",
            "Follow users",
            "Hide or dim read posts in more places",
        ),
    ),
    Release(
        "2.0.15 – 2.0.18", "Oct 16, 2026",
        listOf(
            "For You is out of beta and learns from more of what you do",
            "Familiar ↔ Discover: how adventurous For You should be",
            "Blend (Beta): your Reddit Home ranked by For You",
        ),
    ),
    Release(
        "2.0.11 – 2.0.14", "Oct 16, 2026",
        listOf(
            "Notification activity, Drafts and Ask AI about a thread",
            "Volume keys jump between comments; saved searches; collapse settings",
            "Smoother scrolling past GIFs in threads",
        ),
    ),
    Release(
        "2.0.1 – 2.0.7", "Oct 14, 2026",
        listOf(
            "Smoother scrolling in image-heavy feeds",
            "GIFs and stickers from your keyboard in replies and messages",
            "Hide a community from your front page, or filter it out everywhere",
            "Back never leaves the app from the main screen",
        ),
    ),
    Release(
        "2.0.0", "Oct 12, 2026",
        listOf(
            "Ilay rebuilt as a native Android app: faster, smoother, same data",
            "Reddit Home (experimental): your real reddit.com Home feed",
        ),
    ),
)

private const val SEEN_PREF = "whatsNewSeen"

private fun parts(v: String) = v.substringBefore(' ').split('.').map { it.toIntOrNull() ?: 0 }

/** Whether release [a] (its first version, for a range) is newer than version [b]. */
internal fun newer(a: String, b: String): Boolean {
    val x = parts(a)
    val y = parts(b)
    for (i in 0 until maxOf(x.size, y.size)) {
        val d = x.getOrElse(i) { 0 } - y.getOrElse(i) { 0 }
        if (d != 0) return d > 0
    }
    return false
}

/**
 * Once after an update: what changed since the version you last saw here
 * (or this release's, the first time). Never on a fresh install.
 */
@OptIn(ExperimentalMaterial3Api::class)
suspend fun maybeShowWhatsNew() {
    val current = BuildConfig.VERSION_NAME
    val seen = app.prefs.getString(SEEN_PREF)
    app.prefs.setString(SEEN_PREF, current)
    if (seen == current) return
    val releases = if (seen == null) {
        val info = runCatching { app.context.packageManager.getPackageInfo(app.context.packageName, 0) }.getOrNull()
        if (info == null || info.firstInstallTime == info.lastUpdateTime) return // a fresh install: nothing is "new"
        CHANGELOG.take(1)
    } else {
        CHANGELOG.filter { newer(it.version.substringAfterLast(' '), seen) }.take(3)
    }
    if (releases.isEmpty()) return
    val all = Overlays.show<Boolean> { done ->
        ModalBottomSheet(onDismissRequest = { done(false) }) {
            Column(
                Modifier.navigationBarsPadding().verticalScroll(rememberScrollState())
                    .padding(start = 20.dp, end = 20.dp, bottom = 12.dp),
            ) {
                Text("What's new in Ilay $current", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.ExtraBold)
                Spacer(Modifier.height(12.dp))
                for (r in releases) ReleaseNotes(r, showVersion = releases.size > 1)
                Row(Modifier.fillMaxWidth().padding(top = 8.dp), horizontalArrangement = Arrangement.End) {
                    TextButton(onClick = { done(true) }) { Text("All changes") }
                    Spacer(Modifier.width(8.dp))
                    Button(onClick = { done(false) }) { Text("Got it") }
                }
            }
        }
    }
    if (all == true) app.navigatorOrNull?.push(Route.WhatsNew)
}

@Composable
private fun ReleaseNotes(r: Release, showVersion: Boolean = true) {
    val cs = MaterialTheme.colorScheme
    Column(Modifier.padding(bottom = 12.dp)) {
        if (showVersion) {
            Row {
                Text(r.version, fontWeight = FontWeight.Bold, color = cs.primary)
                Spacer(Modifier.width(8.dp))
                Text(r.date, fontSize = 13.sp, color = cs.onSurfaceVariant)
            }
            Spacer(Modifier.height(6.dp))
        }
        for (h in r.highlights) {
            Row(Modifier.padding(bottom = 6.dp)) {
                Text("•", color = cs.primary)
                Spacer(Modifier.width(10.dp))
                Text(h)
            }
        }
    }
}

/** Settings → About → What's new: every release's highlights. */
@Composable
fun WhatsNewScreen() {
    val cs = MaterialTheme.colorScheme
    Scaffold(topBar = { BloomTopBar("What's new") }, containerColor = cs.surface) { padding ->
        LazyColumn(
            Modifier.fillMaxSize().padding(top = padding.calculateTopPadding()),
            contentPadding = PaddingValues(start = 12.dp, top = 8.dp, end = 12.dp, bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            items(CHANGELOG, key = { it.version }) { r ->
                Surface(Modifier.fillMaxWidth(), shape = RoundedCornerShape(28.dp), color = cs.surfaceContainerLow) {
                    Column(Modifier.padding(start = 18.dp, top = 16.dp, end = 18.dp, bottom = 6.dp)) { ReleaseNotes(r) }
                }
            }
        }
    }
}
