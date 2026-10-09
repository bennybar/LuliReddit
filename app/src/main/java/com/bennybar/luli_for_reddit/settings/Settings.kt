package com.bennybar.luli_for_reddit.settings

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.Reply
import androidx.compose.material.icons.automirrored.rounded.ViewList
import androidx.compose.material.icons.outlined.Spa
import androidx.compose.material.icons.outlined.ViewAgenda
import androidx.compose.material.icons.rounded.ArrowDownward
import androidx.compose.material.icons.rounded.ArrowUpward
import androidx.compose.material.icons.rounded.Block
import androidx.compose.material.icons.rounded.Bookmark
import androidx.compose.material.icons.rounded.CalendarViewDay
import androidx.compose.material.icons.rounded.Spa
import androidx.compose.material.icons.rounded.UnfoldLess
import androidx.compose.material.icons.rounded.VisibilityOff
import androidx.compose.runtime.Immutable
import androidx.compose.ui.graphics.vector.ImageVector
import com.bennybar.luli_for_reddit.data.PostSort

/** The app's typeface (Settings → App font). Persisted by [key] (`appFont`). */
enum class AppFont(val key: String, val label: String, val description: String) {
    ROBOTO("roboto", "Roboto", "Android's default"),
    GOOGLE_SANS("googlesans", "Google Sans", "The typeface of Google's own apps"),
    JAKARTA("jakarta", "Plus Jakarta Sans", "Rounder, with Unbounded for headlines");

    companion object {
        fun parse(key: String?, fallback: AppFont) = entries.firstOrNull { it.key == key } ?: fallback
    }
}

/** Order matters: persisted by index (`themeMode`), same as Flutter's ThemeMode. */
enum class ThemeMode { SYSTEM, LIGHT, DARK }

/** Where the Posts-screen actions (search, new post, profile) live. Persisted by index. */
enum class TopBarMode(val label: String, val description: String) {
    FULL("Full top bar", "Search, new post and profile across the top (current)"),
    EXPANDABLE("Expandable", "Just a title with one button that floats the full top bar in on demand"),
}

/** How posts are laid out in feeds. Persisted by index (`postDisplay`). */
enum class PostDisplay(val label: String, val icon: ImageVector) {
    LARGE("Default", Icons.Outlined.ViewAgenda),
    CARD("Cards", Icons.Rounded.CalendarViewDay),
    MINI("Mini cards", Icons.AutoMirrored.Rounded.ViewList),
    CALM("Calm", Icons.Rounded.Spa),
    CALM_CARDS("Calm cards", Icons.Outlined.Spa),
    ;

    /** Both Calm layouts share the Calm post view and the ⋮-sheet read toggle. */
    val isCalm: Boolean get() = this == CALM || this == CALM_CARDS
}

/** What a swipe on a post or comment does. Persisted by [key] (Flutter's enum name). */
enum class SwipeAction(val key: String, val label: String, val icon: ImageVector) {
    NONE("none", "Nothing", Icons.Rounded.Block),
    UPVOTE("upvote", "Upvote", Icons.Rounded.ArrowUpward),
    DOWNVOTE("downvote", "Downvote", Icons.Rounded.ArrowDownward),
    SAVE("save", "Save", Icons.Rounded.Bookmark),
    REPLY("reply", "Reply", Icons.AutoMirrored.Rounded.Reply),
    HIDE("hide", "Hide", Icons.Rounded.VisibilityOff), // posts only
    COLLAPSE("collapse", "Collapse", Icons.Rounded.UnfoldLess); // comments only

    companion object {
        fun parse(key: String?, fallback: SwipeAction) = entries.firstOrNull { it.key == key } ?: fallback
    }
}

/** Every user setting. Keys/defaults match the Flutter build exactly. */
@Immutable
data class Settings(
    val themeMode: ThemeMode = ThemeMode.SYSTEM,
    val amoled: Boolean = false,
    /** Default off so the Bloom palette shows out of the box. */
    val useDynamicColor: Boolean = false,
    val jakartaFont: Boolean = false, // legacy switch, mirrored from appFont (Flutter backups)
    val appFont: AppFont = AppFont.GOOGLE_SANS, // the app's typeface (Google Sans by default from v2)
    val inAppBrowser: Boolean = false, // open web links in a Custom Tab, not the browser app
    val tapToCollapse: Boolean = false, // tap a comment to collapse it (else long-press)
    val hideReadPosts: Boolean = false, // skip already-read posts when feeds load
    val markReadOnScroll: Boolean = false, // a post scrolled past counts as read
    // What swiping does: "start" = from the start edge (rightward in LTR).
    val swipePostStart: SwipeAction = SwipeAction.UPVOTE,
    val swipePostEnd: SwipeAction = SwipeAction.DOWNVOTE,
    val swipeCommentStart: SwipeAction = SwipeAction.UPVOTE,
    val swipeCommentEnd: SwipeAction = SwipeAction.DOWNVOTE,
    val seedColor: Long = DEFAULT_SEED, // ARGB
    val blurNsfw: Boolean = true,
    val defaultSort: PostSort = PostSort.BEST,
    val defaultCommentSort: String = "confidence", // reddit comment sort id
    val postDisplay: PostDisplay = PostDisplay.LARGE,
    val swipeActions: Boolean = true,
    val trackHistory: Boolean = true,
    val offlineCache: Boolean = true,
    val checkUpdates: Boolean = true,
    val forYouFeed: Boolean = false, // frontpage uses the "For You (Beta)" feed
    // Experimental Reddit Home: the user accepted its risk warning (allowed),
    // and the frontpage currently shows it (feed).
    val redditHomeAllowed: Boolean = false,
    val redditHomeFeed: Boolean = false,
    val autoHideReadForYou: Boolean = false, // hide already-read items in For You
    val midResThumbnails: Boolean = true, // load smaller preview images in feeds
    val subsCacheEnabled: Boolean = true, // cache subscription list in memory
    val subsCacheMinutes: Int = 10, // how long to keep the subs cache
    val feedKeepMinutes: Int = 30, // how long the frontpage keeps its posts before returning to it reloads
    val textScale: Double = 1.0, // global text size multiplier (0.8–1.4)
    val autoplayMedia: Boolean = true, // autoplay videos/GIFs in feeds
    val showApiUsage: Boolean = false, // show API usage instead of search on Posts screen
    val notifyInbox: Boolean = false, // background-poll the inbox + local notifications
    val topBarMode: TopBarMode = TopBarMode.EXPANDABLE, // Posts-screen action layout
    val navLabels: Boolean = true, // show text labels on the bottom nav bar
    val aiModel: String = "gpt-5.4-mini", // OpenAI(-compatible) model id for summaries
    val aiSummaryStyle: Int = 1, // index into SummaryStyle (Key points)
    val aiMaxChars: Int = 100_000, // max thread text sent to the model
    val aiUseCustomUrl: Boolean = false, // use a custom API base URL
    val aiBaseUrl: String = "https://api.openai.com", // custom base URL (when enabled)
    val appIcon: String = "violet", // launcher icon colour (AppIcon key)
) {
    companion object {
        /** Bloom primary — the default accent. */
        const val DEFAULT_SEED: Long = 0xFF6750A4
    }
}
