package com.bennybar.luli_for_reddit.settings

import com.bennybar.luli_for_reddit.ui.SearchIcon
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.Reply
import androidx.compose.material.icons.automirrored.rounded.ViewList
import androidx.compose.material.icons.outlined.AccountCircle
import androidx.compose.material.icons.outlined.PlayCircleOutline
import androidx.compose.material.icons.outlined.PostAdd
import androidx.compose.material.icons.outlined.Settings as SettingsIcon // not to shadow [Settings]
import androidx.compose.material.icons.outlined.Spa
import androidx.compose.material.icons.outlined.VideoLibrary
import androidx.compose.material.icons.outlined.ViewAgenda
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.DoNotDisturbOn
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
import com.bennybar.luli_for_reddit.data.TopTime

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

/**
 * A button in the top bar's menu panel (#108). Persisted by [id] (never change one) in
 * `topBarMenuExpandable` / `topBarMenuFull`: the panel's order, a hidden one as "-id".
 * [half]: two in a row share it, like New post / Settings always did.
 */
enum class TopBarMenuItem(val id: String, val label: String, val icon: ImageVector, val half: Boolean = false) {
    SEARCH("search", "Search Reddit", SearchIcon),
    PROFILE("profile", "Your profile", Icons.Outlined.AccountCircle, half = true),
    NEW_POST("newPost", "New post", Icons.Outlined.PostAdd, half = true),
    SETTINGS("settings", "Settings", Icons.Outlined.SettingsIcon, half = true),
    BROWSE_MEDIA("browseMedia", "Browse media", Icons.Outlined.VideoLibrary),
    LAYOUT("layout", "Layout", Icons.Outlined.ViewAgenda),
    AUTOPLAY("autoplay", "Autoplay media", Icons.Outlined.PlayCircleOutline),
    ;

    companion object {
        /** Each mode's panel as it was before #108. The Full bar has search in the bar itself (#78). */
        fun defaults(mode: TopBarMode): List<TopBarMenuItem> = when (mode) {
            TopBarMode.EXPANDABLE -> listOf(SEARCH, NEW_POST, SETTINGS, BROWSE_MEDIA, LAYOUT, AUTOPLAY)
            TopBarMode.FULL -> listOf(PROFILE, SETTINGS, BROWSE_MEDIA, LAYOUT, AUTOPLAY)
        }

        fun prefsKey(mode: TopBarMode) = if (mode == TopBarMode.EXPANDABLE) "topBarMenuExpandable" else "topBarMenuFull"

        /**
         * The stored order for [mode]: ids it doesn't know (or this mode doesn't offer) are
         * dropped, and items missing from it are added, shown, in their default order, so
         * buttons added later still appear. Settings is always shown: the way back in.
         */
        fun parse(stored: List<String>?, mode: TopBarMode): List<TopBarMenuEntry> {
            val offered = defaults(mode)
            val entries = mutableListOf<TopBarMenuEntry>()
            for (raw in stored.orEmpty()) {
                val item = offered.firstOrNull { it.id == raw.removePrefix("-") } ?: continue
                if (entries.none { it.item == item }) entries += TopBarMenuEntry(item, !raw.startsWith("-") || item == SETTINGS)
            }
            for (item in offered) if (entries.none { it.item == item }) entries += TopBarMenuEntry(item, true)
            return entries
        }

        fun toPrefs(entries: List<TopBarMenuEntry>): List<String> = entries.map { if (it.shown) it.item.id else "-${it.item.id}" }
    }
}

@Immutable
data class TopBarMenuEntry(val item: TopBarMenuItem, val shown: Boolean)

/**
 * Settings → Dim read posts (#106). Stored as `dimRead` (off: nothing fades, history
 * is still kept) plus `dimReadTextOnly`, which keeps its meaning from before Off existed.
 */
enum class ReadDim { OFF, CARD, TEXT }

/**
 * The feeds' floating button, on Home (#62) and in subreddits (#90). Persisted
 * by index (`homeFab`, its key from when it was Home's only), so new ones go at the end.
 */
enum class HomeFab(val label: String) {
    OFF("Off"),
    NEW_POST("New post"),
    SEARCH("Search"),
    SCROLL_TOP("Scroll to top"),
    REFRESH("Refresh"),
    HIDE_READ("Hide read posts"), // takes the posts you've read off the list on screen (#99)
}

/** The floating button in a thread (#90). Persisted by index (`threadFab`), so new ones go at the end. */
enum class ThreadFab(val label: String) {
    NEW_COMMENT("New comment"),
    SCROLL_TOP("Scroll to top"),
    OFF("Off"),
}

/** Horizontal position of the floating toolbar in a thread. Persisted by index (`threadFabPosition`). */
enum class ThreadFabPosition(val label: String) {
    LEFT("Left"),
    MIDDLE("Middle"),
    RIGHT("Right"),
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
    DISMISS("dismiss", "Dismiss (Home / For You)", Icons.Rounded.Close), // posts only; local, 24h
    HIDE_SUB("hideSub", "Hide subreddit 7 days (front page)", Icons.Rounded.DoNotDisturbOn), // posts only; local
    COLLAPSE("collapse", "Collapse", Icons.Rounded.UnfoldLess); // comments only

    companion object {
        fun parse(key: String?, fallback: SwipeAction) = entries.firstOrNull { it.key == key } ?: fallback
    }
}

/** How comments look (#54): only two layouts, so "same as posts" follows Calm or not. Persisted by index. */
enum class CommentStyle(val label: String) {
    SAME("Same as posts"),
    CARDS("Cards"),
    CALM("Calm"),
}

/** A subreddit's own default sort (#60). Persisted in `subredditSorts` as "name|sort|time". */
@Immutable
data class SubredditSort(val sort: PostSort, val time: TopTime)

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
    val collapseRepliesOnly: Boolean = false, // collapsing keeps the comment's own text, hides its replies
    val voteEdge: Boolean = true, // comments you voted on get an edge in the vote's color
    val commentAvatars: Boolean = true, // commenters' profile pictures (website sign-in, #133)
    val autoTranslate: Boolean = false, // posts in neither translation language open translated into the phone's
    val translateSecondLanguage: String = "", // language code Translate also offers ("" = none)
    val translateService: String = "openai", // for what the phone can't translate: "openai" (the AI key) or "azure"
    val azureRegion: String = "", // the Azure Translator resource's region ("" = global)
    val volumeKeyNavigation: Boolean = false, // in a thread, volume keys jump between top-level comments
    val collapseBelowScore: Int? = null, // comments scoring below this start collapsed (null = off)
    val collapseTopLevel: Boolean = false, // threads open with top-level comments' replies collapsed
    val hideReadPosts: Boolean = false, // skip already-read posts when feeds load
    val hideReadInSubreddits: Boolean = false, // …in single subreddits too (else front page / custom feeds only)
    val recentSubsByVisits: Boolean = false, // "Recently visited" lists the most visited first (#92), else the newest
    val dimReadTextOnly: Boolean = false, // read posts: dim only title / text (images stay bright), else the whole card
    val dimRead: Boolean = true, // read posts dim at all (#106); off: history is still kept, nothing fades
    val subredditIcons: Boolean = true, // cards show the subreddit's icon (else its first letter)
    val subredditPrefix: Boolean = true, // subreddit names show as "r/name" (else just "name", #97); display only
    val markReadOnScroll: Boolean = false, // a post scrolled past counts as read
    // What swiping does: "start" = from the start edge (rightward in LTR).
    val swipePostStart: SwipeAction = SwipeAction.UPVOTE,
    val swipePostEnd: SwipeAction = SwipeAction.DOWNVOTE,
    val swipeCommentStart: SwipeAction = SwipeAction.UPVOTE,
    val swipeCommentEnd: SwipeAction = SwipeAction.DOWNVOTE,
    val seedColor: Long = DEFAULT_SEED, // ARGB
    val customSeedColor: Long? = null, // ARGB: the last colour picked with "Custom" (#84), kept for its swatch
    val blurNsfw: Boolean = true,
    val defaultSort: PostSort = PostSort.BEST,
    val subredditSorts: Map<String, SubredditSort> = emptyMap(), // by lowercase name; overrides defaultSort there
    val defaultCommentSort: String = "confidence", // reddit comment sort id
    val postDisplay: PostDisplay = PostDisplay.CALM,
    val commentStyle: CommentStyle = CommentStyle.SAME,
    val swipeActions: Boolean = true,
    val floatingChips: Boolean = true, // feeds: filter chips float under the top bar past the list's own
    val floatingChipsSolid: Boolean = true, // the floating chips sit on the top bar's background; off: transparent, as before 2.0.58 (#91)
    val fullBarNewPost: Boolean = true, // Full top bar: a New post button beside your avatar
    val trackHistory: Boolean = true,
    val showRecentlyVisited: Boolean = true, // Explore and the side bar list the subreddits you opened last
    val offlineCache: Boolean = true,
    val checkUpdates: Boolean = true,
    val analytics: Boolean = true, // anonymous usage stats (Aptabase)
    val forYouFeed: Boolean = false, // frontpage uses the "For You" feed
    val postsTabAll: Boolean = false, // the Posts tab shows r/all instead of the frontpage, which Explore's All button opens then
    val blendHome: Boolean = false, // with forYouFeed + Reddit Home allowed: "Blend (Beta)", For You ranking over your Reddit Home too
    val blendReddit: Int = 1, // Blend: Reddit ↔ Ilay — 0 mostly Ilay, 1 balanced, 2 mostly Reddit
    // Experimental Reddit Home: the user accepted its risk warning (allowed),
    // and the frontpage currently shows it (feed).
    val redditHomeAllowed: Boolean = false,
    val redditHomeFeed: Boolean = false,
    val autoHideReadForYou: Boolean = false, // hide already-read items in For You
    val forYouDiscovery: Int = 0, // For You's Familiar (-2) ↔ Discover (+2) slider; 0 = adaptive default
    val midResThumbnails: Boolean = true, // load smaller preview images in feeds
    val subsCacheEnabled: Boolean = true, // cache subscription list in memory
    val subsCacheMinutes: Int = 10, // how long to keep the subs cache
    val imageCacheMb: Int = 512, // image disk cache (Coil); applies on the next start
    val videoCacheMb: Int = 200, // played-video cache (Media3); applies on the next start
    val feedKeepMinutes: Int = 30, // how long the frontpage keeps its posts before returning to it reloads
    val hiddenPostDays: Int = 7, // how long Ilay keeps posts you hid out of every feed (Reddit hides them too)
    val textScale: Double = 1.0, // global text size multiplier (0.8–1.4)
    val autoplayMedia: Boolean = true, // autoplay videos/GIFs in feeds
    val autoplaySound: Boolean = false, // feed videos start unmuted (#23)
    val viewerMuted: Boolean = false, // full-screen videos start muted (#51)
    val feedGalleryCarousel: Boolean = true, // galleries in feeds as the M3 carousel (else one image at a time)
    val showApiUsage: Boolean = false, // show API usage instead of search on Posts screen
    val notifyInbox: Boolean = false, // background-poll the inbox + local notifications
    val redditAppNotifications: Boolean = false, // take over the Reddit app's notifications (needs notification access)
    val homeFab: HomeFab = HomeFab.NEW_POST, // floating button on Home and in subreddits (#90)
    val threadFab: ThreadFab = ThreadFab.NEW_COMMENT, // floating button in a thread (#90)
    val threadFabPosition: ThreadFabPosition = ThreadFabPosition.RIGHT, // horizontal position of the thread toolbar
    val threadJumpOp: Boolean = true, // show OP comments jump button in thread toolbar
    val threadJumpMine: Boolean = true, // show your comments jump button in thread toolbar
    val threadJumpNext: Boolean = true, // the thread toolbar's next top-level comment button (#121)
    val topBarMode: TopBarMode = TopBarMode.EXPANDABLE, // Posts-screen action layout
    // The top bar menu panel's buttons and order, per mode (#108).
    val topBarMenuExpandable: List<TopBarMenuEntry> = TopBarMenuItem.parse(null, TopBarMode.EXPANDABLE),
    val topBarMenuFull: List<TopBarMenuEntry> = TopBarMenuItem.parse(null, TopBarMode.FULL),
    val navLabels: Boolean = true, // show text labels on the bottom nav bar
    val navStyle: Int = 0, // 0 bottom bar, 1 side bar, 2 both (#25)
    val sideBarItems: List<SideBarEntry> = SideBarItem.parse(null), // the side bar's entries under its tabs, and their order (#109)
    val navOutline: Boolean = true, // thin outline around the floating bottom bar (#29)
    val backScrollsToTop: Boolean = true, // back on the Posts tab scrolls the feed to top
    val aiModel: String = "gpt-5.4-mini", // OpenAI(-compatible) model id for summaries
    val aiSummaryStyle: Int = 1, // index into SummaryStyle (Key points)
    val aiSummaryLanguage: String = "", // English name of the language summaries are written in; "" = the thread's own
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

/** Calm comment rows instead of cards. */
val Settings.calmComments: Boolean
    get() = when (commentStyle) {
        CommentStyle.SAME -> postDisplay.isCalm
        CommentStyle.CARDS -> false
        CommentStyle.CALM -> true
    }

val Settings.readDim: ReadDim
    get() = if (!dimRead) ReadDim.OFF else if (dimReadTextOnly) ReadDim.TEXT else ReadDim.CARD

fun Settings.topBarMenu(mode: TopBarMode): List<TopBarMenuEntry> =
    if (mode == TopBarMode.EXPANDABLE) topBarMenuExpandable else topBarMenuFull

/** The Posts tab's feed key: the frontpage, or r/all with [Settings.postsTabAll]. */
val Settings.postsTabKey: String get() = if (postsTabAll) "all" else ""
