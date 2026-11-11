package com.bennybar.luli_for_reddit.feature.settings

import androidx.compose.material.icons.rounded.Repeat
import androidx.compose.material.icons.rounded.AccountCircle
import androidx.compose.material.icons.outlined.Folder
import android.provider.DocumentsContract
import com.bennybar.luli_for_reddit.ui.SearchIcon
import androidx.compose.material.icons.outlined.PostAdd
import androidx.compose.material.icons.rounded.FilterList
import androidx.compose.material.icons.rounded.Tag
import androidx.compose.material.icons.rounded.AlternateEmail
import androidx.compose.material.icons.rounded.Storage
import androidx.compose.material.icons.rounded.Notifications
import androidx.compose.material.icons.rounded.PermMedia
import androidx.compose.material.icons.rounded.Forum
import androidx.compose.material.icons.rounded.DynamicFeed
import com.bennybar.luli_for_reddit.settings.HomeFab
import com.bennybar.luli_for_reddit.settings.ThreadFab
import com.bennybar.luli_for_reddit.settings.ThreadFabPosition
import androidx.compose.material.icons.rounded.Person
import androidx.compose.material.icons.rounded.RecordVoiceOver
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material.icons.outlined.ModeComment
import androidx.compose.material.icons.rounded.ViewCarousel
import com.bennybar.luli_for_reddit.ui.PickOneMenu
import androidx.compose.material.icons.rounded.CropFree
import androidx.compose.material.icons.rounded.Menu
import com.bennybar.luli_for_reddit.BuildConfig
import androidx.compose.material.icons.rounded.NewReleases
import androidx.compose.material.icons.rounded.NoAdultContent
import com.bennybar.luli_for_reddit.feature.web.RedditWeb
import androidx.compose.material.icons.rounded.ManageAccounts
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.VerticalAlignTop
import androidx.compose.material.icons.rounded.Translate
import androidx.compose.material.icons.rounded.DoNotDisturbOn
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.Sort
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material.icons.outlined.FilterAlt
import androidx.compose.material.icons.outlined.Forum
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.Image
import androidx.compose.material.icons.outlined.VideoLibrary
import androidx.compose.material.icons.outlined.Key
import androidx.compose.material.icons.outlined.MarkEmailRead
import androidx.compose.material.icons.outlined.NotificationsActive
import androidx.compose.material.icons.outlined.PlayCircleOutline
import androidx.compose.material.icons.outlined.SmartToy
import androidx.compose.material.icons.outlined.Timer
import androidx.compose.material.icons.outlined.Insights
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material.icons.rounded.Api
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Merge
import androidx.compose.material.icons.rounded.Backup
import androidx.compose.material.icons.rounded.BlurOn
import androidx.compose.material.icons.rounded.Cached
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.CloudOff
import androidx.compose.material.icons.rounded.CreateNewFolder
import androidx.compose.material.icons.rounded.DeleteForever
import androidx.compose.material.icons.rounded.Description
import androidx.compose.material.icons.rounded.Dns
import androidx.compose.material.icons.rounded.DoneAll
import androidx.compose.material.icons.rounded.ExpandMore
import androidx.compose.material.icons.rounded.ThumbsUpDown
import androidx.compose.material.icons.rounded.Translate
import androidx.compose.material.icons.rounded.UnfoldLess
import androidx.compose.material.icons.automirrored.rounded.VolumeOff
import androidx.compose.material.icons.automirrored.rounded.VolumeUp
import androidx.compose.material.icons.rounded.FontDownload
import androidx.compose.material.icons.rounded.FormatSize
import androidx.compose.material.icons.rounded.Gavel
import androidx.compose.material.icons.rounded.Gif
import androidx.compose.material.icons.rounded.History
import androidx.compose.material.icons.rounded.Info
import androidx.compose.material.icons.rounded.Link
import androidx.compose.material.icons.rounded.OpenInBrowser
import androidx.compose.material.icons.rounded.Image
import androidx.compose.material.icons.rounded.Palette
import androidx.compose.material.icons.rounded.Public
import androidx.compose.material.icons.rounded.Restore
import androidx.compose.material.icons.rounded.Speed
import androidx.compose.material.icons.rounded.Straighten
import androidx.compose.material.icons.rounded.Swipe
import androidx.compose.material.icons.rounded.SystemUpdate
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.KeyboardArrowUp
import androidx.compose.material.icons.rounded.Tune
import androidx.compose.material.icons.rounded.Update
import androidx.compose.material.icons.rounded.ViewHeadline
import androidx.compose.material.icons.rounded.VpnKey
import androidx.compose.material.icons.rounded.WarningAmber
import androidx.compose.material.icons.outlined.Dns
import androidx.compose.material.icons.automirrored.outlined.Label
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Slider
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.SliderState
import androidx.compose.material3.PlainTooltip
import androidx.compose.material3.Label
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bennybar.luli_for_reddit.feature.inbox.RedditAppNotifications
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.core.Translate
import com.bennybar.luli_for_reddit.feature.media.clearVideoCache
import com.bennybar.luli_for_reddit.core.Backup
import com.bennybar.luli_for_reddit.core.RedditConstants
import com.bennybar.luli_for_reddit.core.UpdateChecker
import com.bennybar.luli_for_reddit.data.COMMENT_SORTS
import com.bennybar.luli_for_reddit.data.PostSort
import com.bennybar.luli_for_reddit.feature.media.MediaFolderSettingRow
import com.bennybar.luli_for_reddit.nav.LocalNavigator
import com.bennybar.luli_for_reddit.feature.home.LocalSideBar
import com.bennybar.luli_for_reddit.feature.home.SideBarButton
import androidx.compose.material.icons.rounded.Reorder
import com.bennybar.luli_for_reddit.nav.Route
import com.bennybar.luli_for_reddit.settings.CommentStyle
import com.bennybar.luli_for_reddit.settings.PostDisplay
import com.bennybar.luli_for_reddit.settings.AppFont
import com.bennybar.luli_for_reddit.settings.Settings
import com.bennybar.luli_for_reddit.settings.SwipeAction
import com.bennybar.luli_for_reddit.settings.ThemeMode
import com.bennybar.luli_for_reddit.settings.TopBarMode
import com.bennybar.luli_for_reddit.settings.TopBarMenuItem
import com.bennybar.luli_for_reddit.settings.ReadDim
import com.bennybar.luli_for_reddit.settings.readDim
import com.bennybar.luli_for_reddit.settings.topBarMenu
import com.bennybar.luli_for_reddit.ui.switchThumb
import com.bennybar.luli_for_reddit.ui.Overlays
import kotlinx.coroutines.CoroutineScope
import coil3.SingletonImageLoader
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import kotlin.math.roundToInt
import com.bennybar.luli_for_reddit.core.AppIcon
import com.bennybar.luli_for_reddit.ui.AppIconPreview
import androidx.compose.ui.draw.clip

/** Summary languages: the English name (what the AI is told) to its label. "" = the thread's own. */
private val SUMMARY_LANGUAGES = listOf(
    "" to "Same as the thread",
    "English" to "English",
    "Hebrew" to "Hebrew · עברית",
    "Spanish" to "Spanish · Español",
    "French" to "French · Français",
    "German" to "German · Deutsch",
    "Portuguese" to "Portuguese · Português",
    "Italian" to "Italian · Italiano",
    "Russian" to "Russian · Русский",
    "Arabic" to "Arabic · العربية",
    "Simplified Chinese" to "Chinese · 中文",
    "Japanese" to "Japanese · 日本語",
    "Hindi" to "Hindi · हिन्दी",
)

/** AI summary styles, by persisted index (`aiSummaryStyle`). */
private val SUMMARY_STYLE_LABELS = listOf("TL;DR", "Key points", "Consensus & disagreements", "Explain like I'm 5")

private val AI_MODELS = listOf("gpt-6.1-sol", "gpt-5.5", "gpt-5.4-mini", "gpt-5.4-nano")
internal val NAV_STYLES = listOf(
    "Bottom bar" to "The floating bar at the bottom",
    "Side bar" to "The ☰ at the top of each tab opens it, or swipe back from the top of Posts",
    "Both" to "The bottom bar, plus the side bar (☰, or swipe back from the top of Posts)",
)
private const val CUSTOM_MODEL = "\u0000custom"

// Where saved media goes (same prefs keys as the Flutter build). null = the
// gallery's "Ilay" album.

/** The main page's categories (#68), in groups: a section of the list, what's in it, its icon. */
private val SETTINGS_CATEGORIES = listOf(
    listOf(
        Triple("Feed", "Layout, sort, For You, what's hidden", Icons.Rounded.DynamicFeed),
        Triple("Appearance", "Theme, font, app icon, navigation", Icons.Rounded.Palette),
        Triple("Posts & comments", "Comment style, collapsing, swipes", Icons.Rounded.Forum),
        Triple("Media", "Autoplay, NSFW blur, saving", Icons.Rounded.PermMedia),
    ),
    listOf(
        Triple("Notifications", "Inbox alerts", Icons.Rounded.Notifications),
        Triple("Translation", "Languages and service", Icons.Rounded.Translate),
        Triple("AI summaries", "Key, model, style", Icons.Rounded.AutoAwesome),
    ),
    listOf(
        Triple("Data & storage", "History, cache, backup", Icons.Rounded.Storage),
        Triple("Account & keys", "Login, API keys, clear data", Icons.Rounded.ManageAccounts),
        Triple("Power-user features", "API usage", Icons.Rounded.Tune),
    ),
    listOf(Triple("About", "Version, updates, licenses", Icons.Rounded.Info)),
)

/** Settings: the categories, or the one [section] (a page of its own). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(section: String? = null) {
    val nav = LocalNavigator.current
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(section ?: "Settings") },
                navigationIcon = {
                    // Opened from the side bar (#111): ☰ instead of ←.
                    if (LocalSideBar.current != null) SideBarButton()
                    else IconButton(onClick = { nav.pop() }) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Back") }
                },
            )
        },
    ) { padding ->
        SettingsList(contentPadding = padding, section = section)
    }
}

/** One row of the settings list; [search] = its title + subtitle, null = not searchable. */
private class Entry(val key: String, val search: String?, val content: @Composable () -> Unit)

/**
 * The settings list — reusable both as the full Settings screen and embedded
 * (e.g. inside the You tab). Pass [embedded] when nesting in a scroll view.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsList(
    modifier: Modifier = Modifier,
    embedded: Boolean = false,
    contentPadding: PaddingValues = PaddingValues(),
    section: String? = null,
) {
    val s by app.settings.state.collectAsStateWithLifecycle()
    val ctrl = app.settings
    val nav = LocalNavigator.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val cs = MaterialTheme.colorScheme
    var query by remember { mutableStateOf("") }

    // Secure-storage state, re-read after edits and account changes.
    var secureVersion by remember { mutableIntStateOf(0) }
    val session by app.session.state.collectAsStateWithLifecycle()
    var aiKeySet by remember { mutableStateOf(false) }
    var giphyKeySet by remember { mutableStateOf(false) }
    var azureKeySet by remember { mutableStateOf(false) }
    var authMode by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(secureVersion, session) {
        aiKeySet = !app.secureStore.openaiKey().isNullOrEmpty()
        giphyKeySet = !app.secureStore.giphyKey().isNullOrEmpty()
        azureKeySet = !app.secureStore.azureTranslatorKey().isNullOrEmpty()
        authMode = runCatching { app.secureStore.authMode() }.getOrNull()
    }
    val web = authMode == "web"
    // Notification access is granted in Android's settings: re-check on return.
    var redditAccess by remember { mutableStateOf(RedditAppNotifications.hasAccess(context)) }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { redditAccess = RedditAppNotifications.hasAccess(context) }
    val hiddenSubs by app.hiddenHomeSubs.ids.collectAsStateWithLifecycle()
    val filters by app.contentFilters.state.collectAsStateWithLifecycle()
    // What Ilay keeps in its cache folder: saved pages, images, videos.
    var cacheBytes by remember { mutableStateOf<Long?>(null) }
    LaunchedEffect(Unit) { cacheBytes = withContext(Dispatchers.IO) { context.cacheDir.walk().filter { it.isFile }.sumOf { it.length() } } }

    val pickBackup = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) scope.launch { restoreData(context, uri) }
    }
    // Backups go to a folder picked once (#116); picking it (again) then backs up there.
    var backupFolder by remember { mutableStateOf(backupFolder(context)) }
    val pickBackupFolder = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        if (uri != null) {
            context.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            app.prefs.setString(BACKUP_FOLDER, uri.toString())
            backupFolder = uri
            scope.launch { backupData(context, uri) }
        }
    }

    val all = buildList {
        fun section(title: String) = add(Entry("h:$title", null) { SectionHeader(title) })
        fun divider(k: String) = add(Entry("d:$k", null) { Spacer(Modifier.height(12.dp)) })
        fun tile(
            title: String,
            subtitle: String? = null,
            icon: ImageVector? = null,
            enabled: Boolean = true,
            titleColor: Color? = null,
            iconTint: Color? = null,
            leadingSpacer: Boolean = false,
            onClick: (() -> Unit)? = null,
        ) = add(Entry("t:$title", "$title ${subtitle ?: ""}") {
            SettingTile(title, subtitle, icon, enabled, titleColor, iconTint, leadingSpacer, onClick = onClick)
        })
        fun switch(title: String, subtitle: String?, icon: ImageVector, checked: Boolean, onChange: ((Boolean) -> Unit)?) =
            add(Entry("s:$title", "$title ${subtitle ?: ""}") { SwitchTile(title, subtitle, icon, checked, onChange = onChange) })
        fun launch(block: suspend CoroutineScope.() -> Unit): () -> Unit = { scope.launch(block = block) }

        // ---------------------------------------------------------------- Feed
        section("Feed")
        tile("Post display", s.postDisplay.label, s.postDisplay.icon, onClick = launch {
            pickOption(PostDisplay.entries.map { PickOption(it, it.label, icon = it.icon) }, s.postDisplay)
                ?.let(ctrl::setPostDisplay)
        })
        switch(
            "Subreddit icons", "Show each community's icon on posts instead of its first letter",
            Icons.Rounded.Image, s.subredditIcons, ctrl::setSubredditIcons,
        )
        tile("Default sort", s.defaultSort.label, Icons.AutoMirrored.Rounded.Sort, onClick = launch {
            pickOption(PostSort.entries.map { PickOption(it, it.label) }, s.defaultSort)?.let(ctrl::setDefaultSort)
        })
        switch(
            "Posts tab shows r/all", "Instead of your frontpage, which Explore's All button opens then. For You, Blend and Reddit Home don't apply.",
            Icons.Rounded.Public, s.postsTabAll, ctrl::setPostsTabAll,
        )
        switch(
            "\"For You\" feed",
            "A personalized frontpage, built on your phone from what you read and like",
            Icons.Rounded.AutoAwesome, s.forYouFeed, ctrl::setForYouFeed,
        )
        switch(
            "Auto-hide read items in \"For You\"", "Hide posts you've marked/opened as read",
            Icons.Outlined.MarkEmailRead, s.autoHideReadForYou, ctrl::setAutoHideReadForYou,
        )
        add(Entry("forYouDiscovery", "For You mix familiar discover new communities") {
            ForYouMixSlider(s.forYouDiscovery, ctrl::setForYouDiscovery)
        })
        tile("Manage \"For You\" subreddits", "Review and undo muted / show-less subreddits", Icons.Rounded.Tune) {
            nav.push(Route.ManageForYou)
        }
        val homeSubtitle = if (web) "Unofficial, against Reddit's terms. Shows your real reddit.com Home"
        else "Needs website sign-in"
        add(Entry("s:redditHome", "Reddit Home (experimental) $homeSubtitle") {
            SwitchTile(
                "Reddit Home (experimental)", homeSubtitle, Icons.Rounded.WarningAmber, s.redditHomeAllowed,
                accent = homeAmber(),
                onChange = if (!web && !s.redditHomeAllowed) null else { v ->
                    if (!v) ctrl.setRedditHomeAllowed(false)
                    else scope.launch { if (confirmRedditHome()) ctrl.setRedditHomeAllowed(true) }
                },
            )
        })
        if (s.redditHomeAllowed) {
            switch(
                "Blend (Beta)",
                "For You also ranks your Reddit Home: Reddit's recommendations, under your For You choices",
                Icons.Rounded.Merge, s.forYouFeed && s.blendHome,
            ) { v ->
                ctrl.setBlendHome(v)
                if (v) ctrl.setForYouFeed(true)
            }
            if (s.forYouFeed && s.blendHome) {
                val blendLabels = listOf("Mostly Ilay", "Balanced", "Mostly Reddit")
                val blendHints = listOf(
                    "Reddit's picks get a small nudge, no reserved spots",
                    "About 1 post in 5 is from your Reddit Home",
                    "About 1 in 3 from your Reddit Home, and they count more",
                )
                tile(
                    "Reddit ↔ Ilay",
                    "${blendLabels[s.blendReddit]}: ${blendHints[s.blendReddit].replaceFirstChar { it.lowercase() }}",
                    Icons.Rounded.Merge,
                    onClick = launch {
                        pickOption((0..2).map { PickOption(it, blendLabels[it], blendHints[it]) }, s.blendReddit)?.let(ctrl::setBlendReddit)
                    },
                )
            }
        }
        switch(
            "Floating filter chips", "On Home, subreddits and custom feeds, show the chips under the top bar when you scroll back up",
            Icons.Rounded.FilterList, s.floatingChips, ctrl::setFloatingChips,
        )
        if (s.floatingChips) {
            // #91: the solid top-bar background of 2.0.58, or the outlined chips over the posts as before.
            tile("Floating chips background", if (s.floatingChipsSolid) "Solid" else "Transparent", Icons.Rounded.FilterList, onClick = launch {
                pickOption(
                    listOf(
                        PickOption(false, "Transparent", "Just the outlined chips, over the posts"),
                        PickOption(true, "Solid", "On the top bar's background, so posts don't show between the chips"),
                    ),
                    s.floatingChipsSolid,
                )?.let(ctrl::setFloatingChipsSolid)
            })
        }
        divider("feed-lists")
        tile("Keep feed for", "Home / For You: ${keepLabel(s.feedKeepMinutes)}, then a new feed (pull down to refresh anytime)", Icons.Outlined.Timer, onClick = launch {
            pickOption(listOf(10, 30, 60, 180).map { PickOption(it, keepLabel(it)) }, s.feedKeepMinutes)
                ?.let(ctrl::setFeedKeepMinutes)
        })
        switch(
            "Hide read posts", "Skip posts you've already read when your front page, For You and custom feeds load or refresh",
            Icons.Outlined.VisibilityOff, s.hideReadPosts, ctrl::setHideReadPosts,
        )
        if (s.hideReadPosts) {
            switch(
                "Also in subreddits", "Hide read posts when browsing a single subreddit too",
                Icons.Outlined.VisibilityOff, s.hideReadInSubreddits, ctrl::setHideReadInSubreddits,
            )
        }
        switch(
            "Mark read as you scroll",
            if (s.trackHistory) "A post you scroll past counts as read" else "Needs history tracking turned on",
            Icons.Rounded.DoneAll, s.markReadOnScroll, if (s.trackHistory) ctrl::setMarkReadOnScroll else null,
        )
        tile("Content filters", "Hide posts by keyword, domain, flair or subreddit", Icons.Outlined.FilterAlt) {
            nav.push(Route.ContentFilters)
        }
        tile(
            "Hide posts for",
            "Posts you hide stay out of every feed for ${dayLabel(s.hiddenPostDays)}",
            Icons.Outlined.VisibilityOff,
            onClick = launch {
                pickOption(listOf(1, 3, 7, 30, 90).map { PickOption(it, dayLabel(it)) }, s.hiddenPostDays)
                    ?.let(ctrl::setHiddenPostDays)
            },
        )
        tile(
            "Hidden subreddits",
            "Hidden from your front page for 7 days" + (if (hiddenSubs.isEmpty()) " · none now" else " · ${hiddenSubs.size} now"),
            Icons.Rounded.DoNotDisturbOn,
        ) { showHiddenSubsDialog() }
        divider("feed")

        // ---------------------------------------------------------------- Appearance
        section("Appearance")
        // Light / dark, AMOLED, wallpaper colours, the accent and the palette style: one page (#114).
        add(Entry("t:Theme & colours", "Theme & colours ${themeSummary(s)} dark light AMOLED black accent color colour wallpaper dynamic palette style hex") {
            SettingTile("Theme & colours", themeSummary(s), Icons.Rounded.Palette, onClick = { nav.push(Route.ThemeColors) })
        })
        tile("App font", s.appFont.label, Icons.Rounded.FontDownload, onClick = launch {
            pickOption(AppFont.entries.map { PickOption(it, it.label, subtitle = it.description) }, s.appFont)?.let(ctrl::setAppFont)
        })
        switch(
            "r/ before subreddit names", "Show \"r/pics\" on posts and lists. Off: just \"pics\"",
            Icons.Rounded.Tag, s.subredditPrefix, ctrl::setSubredditPrefix,
        )
        switch(
            "u/ before your name in the side bar", "Show \"u/you\" at the top of the side bar. Off: just \"you\"",
            Icons.Rounded.AlternateEmail, s.sideBarUserPrefix, ctrl::setSideBarUserPrefix,
        )
        add(Entry("appIcon", "App icon launcher home screen colour") {
            val current = AppIcon.parse(s.appIcon)
            SettingTile("App icon", current.label, onClick = {
                scope.launch {
                    val picked = pickAppIcon(current) ?: return@launch
                    if (picked == current) return@launch
                    ctrl.setAppIcon(picked.key)
                    AppIcon.apply(context, picked)
                    nav.showSnackbar("App icon changed. Your home screen can take a few seconds to update.")
                }
            }, leading = { AppIconPreview(current, 24.dp) })
        })
        tile("Font size", "${(s.textScale * 100).roundToInt()}% of normal", Icons.Rounded.FormatSize)
        add(Entry("fontSlider", null) {
            val sliderInteraction = remember { MutableInteractionSource() }
            val sliderState = remember { SliderState(s.textScale.toFloat(), 11, 0.8f..1.4f) }
            LaunchedEffect(s.textScale) { sliderState.value = s.textScale.toFloat() }
            Row(Modifier.padding(start = 16.dp, end = 16.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("A", fontSize = 13.sp)
                Slider(
                    state = sliderState,
                    onValueChange = { ctrl.setTextScale((it * 20).roundToInt() / 20.0) },
                    modifier = Modifier.weight(1f).padding(horizontal = 8.dp),
                    interactionSource = sliderInteraction,
                    // The percentage floats over the thumb while dragging, as in Flutter.
                    thumb = {
                        Label(
                            label = { PlainTooltip { Text("${(s.textScale * 100).roundToInt()}%") } },
                            interactionSource = sliderInteraction,
                        ) { SliderDefaults.Thumb(sliderInteraction) }
                    },
                )
                Text("A", fontSize = 22.sp)
            }
        })
        add(Entry("fontPreview", null) {
            Text(
                "The quick brown fox jumps over the lazy dog.",
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.padding(start = 16.dp, end = 16.dp, bottom = 12.dp),
            )
        })
        divider("appearance-nav")
        tile("Top bar", s.topBarMode.label, Icons.Rounded.ViewHeadline, onClick = launch {
            pickOption(TopBarMode.entries.map { PickOption(it, it.label, it.description) }, s.topBarMode)
                ?.let(ctrl::setTopBarMode)
        })
        if (s.topBarMode == TopBarMode.FULL) {
            switch(
                "New post in the top bar", "A New post button beside your profile picture",
                Icons.Outlined.PostAdd, s.fullBarNewPost, ctrl::setFullBarNewPost,
            )
        }
        tile(
            "Top bar menu", "Choose and order the buttons in the menu " + if (s.topBarMode == TopBarMode.EXPANDABLE) "⋯ opens" else "your profile picture opens",
            Icons.Rounded.Tune,
        ) { showTopBarMenuSettings(s.topBarMode) }
        tile("Floating button", s.homeFab.label, Icons.Rounded.Edit, onClick = launch {
            pickOption(HomeFab.entries.map { PickOption(it, it.label) }, s.homeFab)?.let(ctrl::setHomeFab)
        })
        tile("Floating button in threads", s.threadFab.label, Icons.Outlined.ModeComment, onClick = launch {
            pickOption(ThreadFab.entries.map { PickOption(it, it.label) }, s.threadFab)?.let(ctrl::setThreadFab)
        })
        tile("Jump button position in threads", s.threadFabPosition.label, Icons.Rounded.KeyboardArrowDown, onClick = launch {
            pickOption(ThreadFabPosition.entries.map { PickOption(it, it.label) }, s.threadFabPosition)?.let(ctrl::setThreadFabPosition)
        })
        switch(
            "Next comment button",
            "Jump to the next top-level comment in threads (long-press: the previous one)",
            Icons.Rounded.KeyboardArrowDown, s.threadJumpNext, ctrl::setThreadJumpNext,
        )
        switch(
            "Jump to OP's comments button",
            "Show a button in threads to jump between comments by the original poster",
            Icons.Rounded.RecordVoiceOver, s.threadJumpOp, ctrl::setThreadJumpOp,
        )
        switch(
            "Jump to your comments button",
            "Show a button in threads to jump between your own comments",
            Icons.Rounded.Person, s.threadJumpMine, ctrl::setThreadJumpMine,
        )
        tile("Navigation", NAV_STYLES[s.navStyle.coerceIn(0, 2)].first, Icons.Rounded.Menu, onClick = launch {
            pickOption(NAV_STYLES.mapIndexed { i, (l, d) -> PickOption(i, l, d) }, s.navStyle)?.let(ctrl::setNavStyle)
        })
        if (s.navStyle != 0) {
            tile(
                "Side bar entries",
                s.sideBarItems.filter { it.shown }.joinToString { it.item.label },
                Icons.Rounded.Reorder,
                onClick = ::showSideBarItems,
            )
        }
        if (s.navStyle != 1) {
            switch(
                "Bottom bar labels", "Show text labels under the navigation icons",
                Icons.AutoMirrored.Outlined.Label, s.navLabels, ctrl::setNavLabels,
            )
            switch(
                "Bottom bar outline", "A thin outline around the bottom bar. Off: just its shadow, Material 3 style",
                Icons.Rounded.CropFree, s.navOutline, ctrl::setNavOutline,
            )
        }
        switch(
            "Back scrolls Posts to top", "On the Posts tab, back scrolls the feed to the top. Back never leaves the app",
            Icons.Rounded.VerticalAlignTop, s.backScrollsToTop, ctrl::setBackScrollsToTop,
        )
        divider("appearance")

        // ---------------------------------------------------------------- Posts & comments
        section("Posts & comments")
        tile("Comment style", s.commentStyle.label, Icons.Outlined.ModeComment, onClick = launch {
            pickOption(CommentStyle.entries.map { PickOption(it, it.label) }, s.commentStyle)
                ?.let(ctrl::setCommentStyle)
        })
        tile(
            "Default comment sort",
            COMMENT_SORTS.firstOrNull { it.first == s.defaultCommentSort }?.second ?: s.defaultCommentSort,
            Icons.Outlined.Forum,
            onClick = launch {
                pickOption(COMMENT_SORTS.map { PickOption(it.first, it.second) }, s.defaultCommentSort, radio = false)
                    ?.let(ctrl::setDefaultCommentSort)
            },
        )
        switch(
            "Tap a comment to collapse it",
            "Otherwise long-press. Comment text can't be selected while this is on",
            Icons.Rounded.UnfoldLess, s.tapToCollapse, ctrl::setTapToCollapse,
        )
        switch(
            "Collapse only the replies",
            "Collapsing a comment keeps its own text and hides its replies",
            Icons.Rounded.UnfoldLess, s.collapseRepliesOnly, ctrl::setCollapseRepliesOnly,
        )
        switch(
            "Profile pictures in comments",
            "With the website sign-in: one more request per thread brings its commenters' pictures",
            Icons.Rounded.AccountCircle, s.commentAvatars, ctrl::setCommentAvatars,
        )
        // Glow (and on the thread's post too), the edge line it replaced, or nothing (#141).
        val voteMarks = listOf(
            PickOption(1, "Glow", subtitle = "A soft glow in the vote's color, on the post too"),
            PickOption(2, "Edge line", subtitle = "A line in the vote's color down the comment's side"),
            PickOption(0, "Off"),
        )
        val voteMark = if (!s.voteEdge) 0 else if (s.voteGlow) 1 else 2
        tile("Mark what you voted on", voteMarks.first { it.value == voteMark }.label, Icons.Rounded.ThumbsUpDown, onClick = launch {
            pickOption(voteMarks, voteMark)?.let {
                ctrl.setVoteEdge(it != 0)
                if (it != 0) ctrl.setVoteGlow(it == 1)
            }
        })
        tile(
            "Collapse low-scoring comments",
            s.collapseBelowScore?.let { "Comments below $it points start collapsed" } ?: "Off",
            Icons.Rounded.UnfoldLess,
            onClick = launch {
                val choices = listOf<Int?>(null, 1, 0, -5, -10)
                pickOption(
                    choices.map { PickOption(it ?: Int.MIN_VALUE, if (it == null) "Off" else "Below $it points") },
                    s.collapseBelowScore ?: Int.MIN_VALUE,
                )?.let { ctrl.setCollapseBelowScore(it.takeIf { v -> v != Int.MIN_VALUE }) }
            },
        )
        switch(
            "Open threads collapsed",
            "Top-level comments show without their replies, each with a \"Show replies\" button",
            Icons.Rounded.UnfoldLess, s.collapseTopLevel, ctrl::setCollapseTopLevel,
        )
        switch(
            "Volume keys move between comments",
            "In a thread, volume down goes to the next top-level comment, volume up to the previous",
            Icons.AutoMirrored.Rounded.VolumeUp, s.volumeKeyNavigation, ctrl::setVolumeKeyNavigation,
        )
        switch("Swipe actions", "Swipe posts and comments sideways", Icons.Rounded.Swipe, s.swipeActions, ctrl::setSwipeActions)
        if (s.swipeActions) {
            tile(
                "Customize swipes",
                "Posts: ${s.swipePostStart.label} / ${s.swipePostEnd.label} · " +
                    "Comments: ${s.swipeCommentStart.label} / ${s.swipeCommentEnd.label}",
                leadingSpacer = true,
            ) { showSwipeSettings() }
        }
        switch(
            "Open links inside the app",
            "Web links open in an in-app browser tab instead of your browser app",
            Icons.Rounded.OpenInBrowser, s.inAppBrowser, ctrl::setInAppBrowser,
        )
        divider("posts")

        // ---------------------------------------------------------------- Media
        section("Media")
        switch(
            "Autoplay videos", if (s.autoplaySound) "Play videos as you scroll the feed" else "Play videos muted as you scroll the feed",
            Icons.Outlined.PlayCircleOutline, s.autoplayMedia, ctrl::setAutoplayMedia,
        )
        if (s.autoplayMedia) {
            switch(
                "Autoplay with sound", "Feed videos start with sound; tap the speaker to mute one",
                Icons.AutoMirrored.Rounded.VolumeUp, s.autoplaySound, ctrl::setAutoplaySound,
            )
        }
        switch(
            "Open videos muted", "Full-screen videos start muted; tap the speaker for sound",
            Icons.AutoMirrored.Rounded.VolumeOff, s.viewerMuted, ctrl::setViewerMuted,
        )
        switch(
            "Loop videos", "Full-screen videos start over at the end. Off: they stop, with a replay button. GIFs always loop",
            Icons.Rounded.Repeat, s.loopVideos, ctrl::setLoopVideos,
        )
        switch(
            "Gallery carousel in feeds", "Galleries show a big image with the next ones beside it. Off: one image at a time",
            Icons.Rounded.ViewCarousel, s.feedGalleryCarousel, ctrl::setFeedGalleryCarousel,
        )
        switch("Blur NSFW media", "Tap to reveal blurred images", Icons.Rounded.BlurOn, s.blurNsfw, ctrl::setBlurNsfw)
        // Content filters' switch, here too: beside the blur is where people look for it (#94).
        switch(
            "Hide NSFW posts", "Remove them from feeds and search instead of blurring",
            Icons.Rounded.NoAdultContent, filters.hideNsfw, app.contentFilters::setHideNsfw,
        )
        switch(
            "Data-saver thumbnails", "Load smaller preview images in feeds (faster, less data)",
            Icons.Outlined.Image, s.midResThumbnails, ctrl::setMidResThumbnails,
        )
        add(Entry("mediaFolder", "Save media to folder gallery") { MediaFolderSettingRow() })
        divider("media")

        // ---------------------------------------------------------------- Notifications
        section("Notifications")
        switch(
            "Inbox notifications",
            "Check for replies & messages in the background (~every 15 min) and notify you. No Firebase — polling only.",
            Icons.Outlined.NotificationsActive, s.notifyInbox,
        ) { v -> scope.launch { toggleInboxNotifications(v) } }
        switch(
            "Open Reddit app notifications in Ilay",
            when {
                !s.redditAppNotifications -> "Replaces the official Reddit app's notifications with Ilay's, which open here. Needs notification access."
                redditAccess -> "Reddit app notifications now open in Ilay"
                else -> "Needs notification access: turn on Ilay in the next screen. If Android says \"Restricted setting\", open Ilay's App info → ⋮ → Allow restricted settings, then try again."
            },
            Icons.Outlined.NotificationsActive, s.redditAppNotifications && redditAccess,
        ) { v -> scope.launch { toggleRedditAppNotifications(v) } }
        tile("Notification activity", "What Ilay notified you about, what it couldn't, and why · Check now", Icons.Outlined.History) {
            nav.push(Route.NotificationActivity)
        }
        divider("notifications")

        // ---------------------------------------------------------------- Translation
        section("Translation")
        tile(
            "Second language",
            s.translateSecondLanguage.ifEmpty { null }?.let { "Translate also offers ${Translate.languageName(it)}" }
                ?: "Off: Translate offers your phone's language only",
            Icons.Rounded.Translate,
            onClick = launch {
                val options = listOf(PickOption("", "Off")) +
                    TRANSLATE_LANGUAGES.filter { it != Translate.primary }
                        .map { PickOption(it, Translate.languageName(it)) }.sortedBy { it.label }
                pickOption(options, s.translateSecondLanguage, radio = false)?.let(ctrl::setTranslateSecondLanguage)
            },
        )
        switch(
            "Auto-translate posts",
            "Posts in neither language open translated into your phone's",
            Icons.Rounded.Translate, s.autoTranslate, ctrl::setAutoTranslate,
        )
        tile(
            "Translation service",
            (if (s.translateService == "azure") "Azure Translator" else "OpenAI (your AI key)") +
                " · for languages your phone can't translate",
            Icons.Outlined.Dns,
            onClick = launch {
                pickOption(
                    listOf(
                        PickOption("openai", "OpenAI", "Your AI summaries key; each translation costs a little"),
                        PickOption("azure", "Azure Translator", "Your Azure key; 2 million characters a month free"),
                    ),
                    s.translateService,
                )?.let(ctrl::setTranslateService)
            },
        )
        if (s.translateService == "azure") {
            tile(
                "Azure Translator key",
                if (azureKeySet) "Key set — tap to change or remove" else "Add your Translator resource's key",
                Icons.Outlined.Key,
                onClick = launch {
                    val r = textDialog(
                        "Azure Translator key", secret = true, removable = azureKeySet,
                        note = "Stored securely on this device (never in backups). Translations send the text to Microsoft.",
                    ) ?: return@launch
                    when (r) {
                        TextResult.Remove -> app.secureStore.saveAzureTranslatorKey(null)
                        is TextResult.Save -> if (r.text.isNotBlank()) app.secureStore.saveAzureTranslatorKey(r.text.trim())
                    }
                    secureVersion++
                },
            )
            tile("Azure region", s.azureRegion.ifEmpty { "Global" }, Icons.Rounded.Link, onClick = launch {
                val r = textDialog(
                    "Azure region", initial = s.azureRegion, hint = "e.g. westeurope",
                    note = "Your Translator resource's location. Leave empty for a global resource.",
                ) as? TextResult.Save ?: return@launch
                ctrl.setAzureRegion(r.text.trim())
            })
        }
        divider("translation")

        // ---------------------------------------------------------------- AI
        section("AI summaries")
        // With a custom endpoint the key is that provider's (Groq, OpenRouter, a LiteLLM key…).
        val keyLabel = if (s.aiUseCustomUrl) "API key" else "OpenAI API key"
        tile(
            keyLabel,
            if (aiKeySet) "Key set — tap to change or remove" else "Add a key to enable thread summaries",
            Icons.Outlined.Key,
            onClick = launch {
                val r = textDialog(
                    keyLabel, hint = if (s.aiUseCustomUrl) "Your provider's API key" else "sk-…", secret = true, removable = aiKeySet,
                    note = "Stored securely on this device (never in backups). Summaries send the thread text to your AI endpoint.",
                ) ?: return@launch
                when (r) {
                    TextResult.Remove -> app.secureStore.saveOpenaiKey(null)
                    is TextResult.Save -> if (r.text.isNotBlank()) app.secureStore.saveOpenaiKey(r.text.trim())
                }
                secureVersion++
            },
        )
        tile("Model", s.aiModel, Icons.Outlined.SmartToy, enabled = aiKeySet, onClick = launch {
            // The presets are OpenAI's; any other provider's model is typed in.
            val presets = (AI_MODELS + listOfNotNull(s.aiModel.takeIf { it !in AI_MODELS })).map { PickOption(it, it) }
            val picked = pickOption(presets + PickOption(CUSTOM_MODEL, "Custom model…", "Type your provider's model ID"), s.aiModel, radio = false)
                ?: return@launch
            if (picked != CUSTOM_MODEL) return@launch ctrl.setAiModel(picked)
            val r = textDialog(
                "Model ID", initial = s.aiModel, hint = "e.g. llama-3.3-70b-versatile",
                note = "Exactly as your provider names it.",
            ) as? TextResult.Save ?: return@launch
            if (r.text.isNotBlank()) ctrl.setAiModel(r.text.trim())
        })
        tile(
            "Summary style",
            SUMMARY_STYLE_LABELS[s.aiSummaryStyle.coerceIn(0, SUMMARY_STYLE_LABELS.size - 1)],
            Icons.Rounded.AutoAwesome, enabled = aiKeySet,
            onClick = launch {
                pickOption(SUMMARY_STYLE_LABELS.mapIndexed { i, l -> PickOption(i, l) }, s.aiSummaryStyle, radio = false)
                    ?.let(ctrl::setAiSummaryStyle)
            },
        )
        tile(
            "Summary language",
            SUMMARY_LANGUAGES.firstOrNull { it.first == s.aiSummaryLanguage }?.second ?: s.aiSummaryLanguage,
            Icons.Rounded.Translate, enabled = aiKeySet,
            onClick = launch {
                pickOption(SUMMARY_LANGUAGES.map { PickOption(it.first, it.second) }, s.aiSummaryLanguage, radio = false)
                    ?.let(ctrl::setAiSummaryLanguage)
            },
        )
        tile(
            "Max thread size",
            "${(s.aiMaxChars / 1000.0).roundToInt()}k characters (~${(s.aiMaxChars / 4000.0).roundToInt()}k tokens)",
            Icons.Rounded.Straighten, enabled = aiKeySet,
            onClick = launch {
                pickOption(
                    listOf(50_000, 100_000, 200_000, 400_000).map {
                        PickOption(it, "${it / 1000}k characters", "~${(it / 4000.0).roundToInt()}k tokens")
                    },
                    s.aiMaxChars, radio = false,
                )?.let(ctrl::setAiMaxChars)
            },
        )
        switch(
            "Custom API base URL", "Advanced — use an OpenAI-compatible endpoint (e.g. Groq, OpenRouter, LiteLLM)",
            Icons.Rounded.Dns, s.aiUseCustomUrl, ctrl::setAiUseCustomUrl,
        )
        if (s.aiUseCustomUrl) {
            tile("API base URL", s.aiBaseUrl, Icons.Rounded.Link, onClick = launch {
                val r = textDialog(
                    "API base URL", initial = s.aiBaseUrl, hint = "https://api.groq.com/openai/v1", keyboardType = KeyboardType.Uri,
                    note = "With or without /v1, as your provider shows it. Then set the Model to one of theirs.",
                ) as? TextResult.Save ?: return@launch
                if (r.text.isNotBlank()) ctrl.setAiBaseUrl(r.text.trim())
            })
        }
        divider("ai")

        // ---------------------------------------------------------------- Data & storage
        section("Data & storage")
        switch(
            "Track history", if (s.dimRead) "Remember and dim viewed posts (local only)" else "Remember viewed posts (local only)",
            Icons.Outlined.Visibility, s.trackHistory, ctrl::setTrackHistory,
        )
        if (s.trackHistory) {
            // Like Sync for Reddit's: the subreddits you open most stay on top (#92).
            tile(
                "Recently visited order", if (s.recentSubsByVisits) "Most visited first" else "Most recent first", Icons.Rounded.History,
                onClick = launch {
                    pickOption(
                        listOf(PickOption(false, "Most recent first"), PickOption(true, "Most visited first", "The subreddits you open most stay on top")),
                        s.recentSubsByVisits,
                    )?.let(ctrl::setRecentSubsByVisits)
                },
            )
            tile(
                "Dim read posts",
                when (s.readDim) {
                    ReadDim.OFF -> "Off: read posts look like new ones"
                    ReadDim.CARD -> "Whole card"
                    ReadDim.TEXT -> "Text only: titles and text fade, images stay bright"
                },
                Icons.Outlined.Visibility,
                onClick = launch {
                    pickOption(
                        listOf(PickOption(ReadDim.CARD, "Whole card"), PickOption(ReadDim.TEXT, "Text only", "Images and videos stay bright"), PickOption(ReadDim.OFF, "Off", "History is still kept")),
                        s.readDim,
                    )?.let(ctrl::setReadDim)
                },
            )
        }
        switch(
            "Recently visited", "List the subreddits you opened last on Explore and in the side bar",
            Icons.Rounded.History, s.showRecentlyVisited, ctrl::setShowRecentlyVisited,
        )
        switch("Offline cache", "Show the last loaded content when offline", Icons.Rounded.CloudOff, s.offlineCache, ctrl::setOfflineCache)
        switch(
            "Cache subscriptions", "Keep your subreddit list in memory to speed up \"For You\"",
            Icons.Outlined.Dns, s.subsCacheEnabled, ctrl::setSubsCacheEnabled,
        )
        tile("Subscriptions cache time", "${s.subsCacheMinutes} minutes", Icons.Outlined.Timer, enabled = s.subsCacheEnabled, onClick = launch {
            pickOption(listOf(5, 10, 30, 60).map { PickOption(it, "$it minutes") }, s.subsCacheMinutes)
                ?.let(ctrl::setSubsCacheMinutes)
        })
        tile("Image cache size", "Up to ${s.imageCacheMb} MB · after restarting Ilay", Icons.Outlined.Image, onClick = launch {
            pickOption(listOf(256, 512, 1024, 2048).map { PickOption(it, "$it MB") }, s.imageCacheMb)
                ?.let(ctrl::setImageCacheMb)
        })
        tile("Video cache size", "Up to ${s.videoCacheMb} MB · after restarting Ilay", Icons.Outlined.VideoLibrary, onClick = launch {
            pickOption(listOf(100, 200, 500, 1000).map { PickOption(it, "$it MB") }, s.videoCacheMb)
                ?.let(ctrl::setVideoCacheMb)
        })
        tile("Clear cache", cacheBytes?.let { "${it shr 20} MB of saved pages, images and videos" }, Icons.Rounded.Cached, onClick = launch {
            app.client.clearCache()
            withContext(Dispatchers.IO) {
                SingletonImageLoader.get(context).let { it.memoryCache?.clear(); it.diskCache?.clear() }
                clearVideoCache(context)
                cacheBytes = context.cacheDir.walk().filter { it.isFile }.sumOf { it.length() }
            }
            nav.showSnackbar("Cache cleared")
        })
        tile("Back up data", "Export settings, For You model & history (no login/keys)", Icons.Rounded.Backup) {
            val folder = backupFolder
            if (folder != null) scope.launch { backupData(context, folder) }
            else runCatching { pickBackupFolder.launch(null) }.onFailure { scope.launch { backupData(context, null) } }
        }
        tile("Backup folder", backupFolder?.let(::folderLabel) ?: "Chosen on your first backup", Icons.Outlined.Folder) {
            runCatching { pickBackupFolder.launch(backupFolder) }.onFailure { nav.showSnackbar("Couldn't open the folder picker: ${it.message}") }
        }
        tile("Restore data", "Import a backup file", Icons.Rounded.Restore) {
            runCatching { pickBackup.launch(arrayOf("application/json", "application/octet-stream", "text/*")) }
                .onFailure { nav.showSnackbar("Restore failed: ${it.message}") }
        }
        divider("data")

        // ---------------------------------------------------------------- Account
        section("Account & keys")
        tile(
            "Login method",
            if (web) "Website session (no API key) — unofficial" else "Reddit API key (recommended)",
            if (web) Icons.Rounded.Public else Icons.Rounded.Api,
            onClick = launch { showLoginMethodInfo(web) },
        )
        if (web) {
            tile("Reddit account settings", "Reddit's own settings: Home recommendations, notifications, muted communities", Icons.Rounded.ManageAccounts) {
                nav.push(Route.RedditWeb(RedditWeb.SETTINGS, "Reddit settings"))
            }
        }
        tile("Reddit API credentials", "Re-enter your Client ID / Redirect URI", Icons.Rounded.VpnKey, onClick = launch {
            if (confirmDialog(
                    "Re-enter credentials?",
                    "You will be logged out and returned to the login screen. Your saved Client ID and Redirect URI will be pre-filled.",
                    "Continue",
                )
            ) app.session.logout()
        })
        tile(
            "Giphy API key",
            if (giphyKeySet) "Key set — tap to change or remove" else "Optional — enables the GIF picker",
            Icons.Rounded.Gif,
            onClick = launch {
                val r = textDialog("Giphy API key", secret = true, removable = giphyKeySet, note = "Stored securely on this device (never in backups).")
                    ?: return@launch
                when (r) {
                    TextResult.Remove -> app.secureStore.saveGiphyKey(null)
                    is TextResult.Save -> if (r.text.isNotBlank()) app.secureStore.saveGiphyKey(r.text.trim())
                }
                secureVersion++
            },
        )
        tile(
            "Clear all data", "Wipes credentials, tokens and login", Icons.Rounded.DeleteForever,
            titleColor = cs.error, iconTint = cs.error,
            onClick = launch {
                if (confirmDialog(
                        "Clear all data?",
                        "This wipes your API credentials, tokens and session from this device. You will need to set everything up again.",
                        "Clear",
                    )
                ) {
                    app.secureStore.clearAll()
                    app.client.clearCache()
                    app.session.logout()
                }
            },
        )
        divider("account")

        // ---------------------------------------------------------------- Power-user
        section("Power-user features")
        switch(
            "Show API usage instead of search",
            "Replace the search bar on the Posts screen with your live Reddit API rate-limit usage",
            Icons.Rounded.Speed, s.showApiUsage, ctrl::setShowApiUsage,
        )
        add(Entry("rateLimit", "API usage") { RateLimitTile() })
        divider("power")

        // ---------------------------------------------------------------- About
        section("About")
        tile("What's new", "Ilay ${BuildConfig.VERSION_NAME} · what changed in each release", Icons.Rounded.NewReleases) { nav.push(Route.WhatsNew) }
        switch("Check for updates", "Check GitHub releases on launch", Icons.Rounded.SystemUpdate, s.checkUpdates, ctrl::setCheckUpdates)
        tile("Check now", icon = Icons.Rounded.Update, onClick = launch { checkUpdatesNow() })
        switch(
            "Send anonymous usage stats",
            "App starts, which feed you use, whether Reddit Home loads. Never your account or what you read",
            Icons.Outlined.Insights, s.analytics, ctrl::setAnalytics,
        )
        tile(
            "Open reddit links in Ilay",
            "Already supported via the Android \"open with\" chooser. To make Ilay the verified default, " +
                "enable it under system app settings › Open by default.",
            Icons.Rounded.Link,
        )
        tile("Content & conduct policy", icon = Icons.Rounded.Gavel) { nav.push(Route.Policy) }
        tile("Open-source licenses", "Fonts: Google Sans, Plus Jakarta Sans, Unbounded (SIL OFL 1.1)", Icons.Rounded.Description, onClick = launch {
            val text = withContext(Dispatchers.IO) {
                fun read(f: String) = runCatching { context.assets.open(f).bufferedReader().use { it.readText() } }.getOrDefault("")
                "Google Sans\n\n" + read("OFL-GoogleSans.txt") + "\n\nPlus Jakarta Sans, Unbounded\n\n" + read("OFL.txt")
            }
            infoDialog("Licenses", text)
        })
        tile("Version", RedditConstants.APP_VERSION, Icons.Rounded.Info)
    }

    val q = query.trim().lowercase()
    val sections = all.map { it.key }.filter { it.startsWith("h:") }
    val shown = when {
        q.isNotEmpty() -> all.filter { it.search?.lowercase()?.contains(q) == true }
        // One section's rows.
        section != null -> all.dropWhile { it.key != "h:$section" }.drop(1).takeWhile { !it.key.startsWith("h:") }
        // The main page.
        else -> buildList {
            SETTINGS_CATEGORIES.forEachIndexed { i, group ->
                if (i > 0) add(Entry("d:group$i", null) { Spacer(Modifier.height(12.dp)) })
                for ((title, subtitle, icon) in group) {
                    if ("h:$title" !in sections) continue
                    add(Entry("c:$title", null) { SettingTile(title, subtitle, icon, onClick = { nav.push(Route.SettingsSection(title)) }) })
                }
            }
        }
    }

    // Rows sit in rounded containers, joined until a gap ("d:"): a row's outer
    // corners are round only where the container starts or ends (#68).
    val row = @Composable { i: Int ->
        val e = shown[i]
        if (e.key.startsWith("d:")) {
            e.content()
        } else {
            val first = shown.getOrNull(i - 1)?.key?.startsWith("d:") != false
            val last = shown.getOrNull(i + 1)?.key?.startsWith("d:") != false
            Column(
                Modifier
                    .fillMaxWidth()
                    .padding(start = 16.dp, end = 16.dp, bottom = if (last) 0.dp else 2.dp)
                    .clip(
                        RoundedCornerShape(
                            topStart = if (first) 24.dp else 4.dp,
                            topEnd = if (first) 24.dp else 4.dp,
                            bottomStart = if (last) 24.dp else 4.dp,
                            bottomEnd = if (last) 24.dp else 4.dp,
                        ),
                    )
                    .background(cs.surfaceContainerLow),
            ) { e.content() }
        }
    }

    val searchField = @Composable {
        TextField(
            value = query,
            onValueChange = { query = it },
            singleLine = true,
            placeholder = { Text("Search settings") },
            leadingIcon = { Icon(SearchIcon, null) },
            shape = RoundedCornerShape(28.dp),
            colors = TextFieldDefaults.colors(
                focusedContainerColor = cs.surfaceContainerHigh,
                unfocusedContainerColor = cs.surfaceContainerHigh,
                focusedIndicatorColor = Color.Transparent,
                unfocusedIndicatorColor = Color.Transparent,
            ),
            modifier = Modifier.fillMaxWidth().padding(start = 16.dp, top = 12.dp, end = 16.dp, bottom = 12.dp),
        )
    }
    val noResults = @Composable {
        Box(Modifier.fillMaxWidth().padding(40.dp), contentAlignment = Alignment.Center) { Text("No settings found") }
    }

    if (embedded) {
        Column(modifier) {
            if (section == null) searchField()
            shown.indices.forEach { row(it) }
            if (q.isNotEmpty() && shown.isEmpty()) noResults()
        }
    } else {
        LazyColumn(modifier.fillMaxSize(), contentPadding = contentPadding) {
            if (section == null) item(key = "search") { searchField() }
            items(shown.size, key = { shown[it].key }) { row(it) }
            if (q.isNotEmpty() && shown.isEmpty()) item(key = "none") { noResults() }
            item(key = "bottom") { Spacer(Modifier.height(24.dp)) }
        }
    }
}

private suspend fun pickAppIcon(current: AppIcon): AppIcon? = Overlays.show { done ->
    OverlaySheet<AppIcon>(done) { close ->
        Text(
            "App icon",
            style = MaterialTheme.typography.titleLarge,
            modifier = Modifier.padding(start = 24.dp, end = 24.dp, bottom = 16.dp),
        )
        FlowRow(
            Modifier.fillMaxWidth().padding(horizontal = 16.dp),
            horizontalArrangement = Arrangement.SpaceEvenly,
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            for (icon in AppIcon.entries) {
                val selected = icon == current
                Column(
                    Modifier.clip(RoundedCornerShape(20.dp)).clickable { close(icon) }.padding(8.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Box(
                        Modifier.border(
                            width = 3.dp,
                            color = if (selected) MaterialTheme.colorScheme.primary else Color.Transparent,
                            shape = CircleShape,
                        ).padding(5.dp),
                    ) { AppIconPreview(icon, 56.dp) }
                    Text(
                        icon.label,
                        style = MaterialTheme.typography.labelLarge,
                        color = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface,
                    )
                }
            }
        }
        Text(
            "Your home screen shows the new icon after a few seconds.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(start = 24.dp, end = 24.dp, top = 16.dp, bottom = 16.dp),
        )
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun RateLimitTile() {
    val rl by app.rateLimit.collectAsStateWithLifecycle()
    SettingTile(
        "API usage",
        rl?.let { "${it.used}/${it.total} used this window · resets in ${it.secondsLeft()}s" }
            ?: "Reddit allows roughly 100 requests/minute. No data yet.",
        Icons.Rounded.Speed,
    )
}

/** "Save media to" sheet: true = gallery, false = choose a folder, null = dismissed. */

/**
 * Settings → Top bar menu (#108): which buttons [mode]'s menu panel shows, and their
 * order. Every change applies at once; Settings can't be hidden, so it's never a dead end.
 */
private fun showTopBarMenuSettings(mode: TopBarMode) {
    Overlays.launch { dismiss ->
        OverlaySheet<Unit>(done = { dismiss() }) { _ ->
            val s by app.settings.state.collectAsStateWithLifecycle()
            val entries = s.topBarMenu(mode)
            Text(
                "Top bar menu",
                style = MaterialTheme.typography.titleLarge,
                modifier = Modifier.padding(start = 24.dp, end = 24.dp, bottom = 4.dp),
            )
            Text(
                if (mode == TopBarMode.EXPANDABLE) "The panel the ⋯ button opens" else "The panel your profile picture opens",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(start = 24.dp, end = 24.dp, bottom = 8.dp),
            )
            fun move(from: Int, to: Int) {
                app.settings.setTopBarMenu(mode, entries.toMutableList().apply { add(to, removeAt(from)) })
            }
            entries.forEachIndexed { i, e ->
                val always = e.item == TopBarMenuItem.SETTINGS
                SettingTile(
                    e.item.label,
                    when {
                        always -> "Always shown"
                        e.item == TopBarMenuItem.PROFILE -> "When signed in"
                        else -> null
                    },
                    e.item.icon,
                    trailing = {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            IconButton(onClick = { move(i, i - 1) }, enabled = i > 0) { Icon(Icons.Rounded.KeyboardArrowUp, "Move up") }
                            IconButton(onClick = { move(i, i + 1) }, enabled = i < entries.lastIndex) { Icon(Icons.Rounded.KeyboardArrowDown, "Move down") }
                            Switch(
                                thumbContent = switchThumb(e.shown),
                                checked = e.shown,
                                enabled = !always,
                                onCheckedChange = { on ->
                                    app.settings.setTopBarMenu(mode, entries.map { if (it.item == e.item) it.copy(shown = on) else it })
                                },
                            )
                        }
                    },
                )
            }
            TextButton(
                onClick = { app.settings.setTopBarMenu(mode, null) },
                modifier = Modifier.padding(start = 12.dp, top = 4.dp, bottom = 12.dp),
            ) { Text("Reset to default") }
        }
    }
}

/** Picks what each swipe direction does, for posts and for comments. */
private fun showSwipeSettings() {
    Overlays.launch { dismiss ->
        OverlaySheet<Unit>(done = { dismiss() }) { _ ->
            val s by app.settings.state.collectAsStateWithLifecycle()
            // "Right"/"left" as the user sees them; mirrored in RTL languages.
            val rtl = LocalLayoutDirection.current == LayoutDirection.Rtl
            val startLabel = if (rtl) "Swipe left" else "Swipe right"
            val endLabel = if (rtl) "Swipe right" else "Swipe left"

            @Composable
            fun SwipeRow(label: String, key: String, value: SwipeAction, forPosts: Boolean) {
                val options = SwipeAction.entries.filter {
                    if (forPosts) it != SwipeAction.COLLAPSE
                    else it != SwipeAction.HIDE && it != SwipeAction.DISMISS && it != SwipeAction.HIDE_SUB
                }
                var open by remember { mutableStateOf(false) }
                SettingTile(label, trailing = {
                    Box {
                        TextButton(onClick = { open = true }) {
                            Icon(value.icon, null, Modifier.size(18.dp))
                            Spacer(Modifier.width(8.dp))
                            Text(value.label)
                            Icon(Icons.Rounded.ExpandMore, null)
                        }
                        PickOneMenu(open, { open = false }, options.map { it to it.label }, value, { a -> app.settings.setSwipeAction(key, a) }, icon = { it.icon })
                    }
                })
            }

            SectionHeader("Posts")
            SwipeRow(startLabel, "swipePostStart", s.swipePostStart, true)
            SwipeRow(endLabel, "swipePostEnd", s.swipePostEnd, true)
            SectionHeader("Comments")
            SwipeRow(startLabel, "swipeCommentStart", s.swipeCommentStart, false)
            SwipeRow(endLabel, "swipeCommentEnd", s.swipeCommentEnd, false)
            Spacer(Modifier.height(12.dp))
        }
    }
}

/** Amber for Reddit Home's caution (readable on light and dark surfaces). */
@Composable
internal fun homeAmber(): Color =
    if (MaterialTheme.colorScheme.surface.luminance() > 0.5f) Color(0xFF9A6700) else Color(0xFFFFC94D)

/** What Reddit Home is (unofficial, can break) before turning it on. True to turn it on. */
internal suspend fun confirmRedditHome(): Boolean = Overlays.show<Boolean> { done ->
    val amber = homeAmber()
    AlertDialog(
        onDismissRequest = { done(false) },
        icon = { Icon(Icons.Rounded.WarningAmber, null, Modifier.size(40.dp), tint = amber) },
        title = { Text("About Reddit Home", textAlign = TextAlign.Center) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState())) {
                val body = MaterialTheme.typography.bodyMedium.copy(lineHeight = 20.sp)
                Text(
                    "Reddit Home shows your real reddit.com Home feed. Ilay loads reddit.com in a hidden browser " +
                        "with your website sign-in and reads which posts it shows.",
                    style = body,
                )
                Spacer(Modifier.height(10.dp))
                Text(
                    "• Unofficial: Reddit's terms don't allow automated use of its site, so use it at your own discretion.",
                    style = body,
                )
                Spacer(Modifier.height(6.dp))
                Text("• It can stop working when Reddit changes its site. Ilay then shows For You.", style = body)
                Spacer(Modifier.height(6.dp))
                Text("• Website sign-in only; it talks only to reddit.com.", style = body)
            }
        },
        dismissButton = { TextButton(onClick = { done(false) }) { Text("Cancel") } },
        confirmButton = { Button(onClick = { done(true) }) { Text("Turn on") } },
    )
} == true

private suspend fun showLoginMethodInfo(isWeb: Boolean) = infoDialog(
    "Login method",
    if (isWeb) {
        "You're signed in with a website session (no API key).\n\n" +
            "This isn't Reddit's official API. It can stop working if Reddit changes their site, and Reddit may " +
            "consider it against their usage policy and restrict or ban accounts that use it. Use at your own risk.\n\n" +
            "To switch to the official API key method, log out and choose \"Connect Reddit account\" on the login screen."
    } else {
        "You're signed in with Reddit's official API using your own API key — the recommended, supported method.\n\n" +
            "If you can no longer create an API key, you can log out and choose \"Sign in via website\" on the login " +
            "screen, but that unofficial method carries account risk."
    },
)

private suspend fun toggleRedditAppNotifications(enable: Boolean) {
    app.settings.setRedditAppNotifications(enable)
    if (!enable) return
    if (!app.inbox.requestPermission()) {
        app.navigatorOrNull?.showSnackbar("Notification permission denied. Enable it in system settings.")
        app.settings.setRedditAppNotifications(false)
        return
    }
    val ctx = app.context
    if (!RedditAppNotifications.hasAccess(ctx)) ctx.startActivity(RedditAppNotifications.accessSettingsIntent(ctx))
}

private suspend fun toggleInboxNotifications(enable: Boolean) {
    val nav = app.navigatorOrNull
    if (!enable) {
        app.settings.setNotifyInbox(false)
        app.inbox.cancelPolling()
        return
    }
    if (!app.inbox.requestPermission()) {
        nav?.showSnackbar("Notification permission denied. Enable it in system settings to get inbox alerts.")
        return
    }
    app.settings.setNotifyInbox(true)
    // Prime the "seen" set with current unread so turning this on doesn't fire a
    // notification for every pre-existing item, then start the periodic poll.
    runCatching { app.inbox.pollInbox(notify = false) }
    app.inbox.registerPolling()
    nav?.showSnackbar("Inbox notifications on. Reddit is checked about every 15 minutes.")
}

private suspend fun checkUpdatesNow() {
    val nav = app.navigatorOrNull ?: return
    nav.showSnackbar("Checking…")
    val info = UpdateChecker.check()
    if (info == null) {
        nav.showSnackbar("You're on the latest version (${RedditConstants.APP_VERSION}).")
        return
    }
    nav.snackbar.currentSnackbarData?.dismiss()
    val download = Overlays.show<Boolean> { done ->
        AlertDialog(
            onDismissRequest = { done(false) },
            title = { Text("Update available — v${info.version}") },
            text = { Text("A newer version is available on GitHub.") },
            dismissButton = { TextButton(onClick = { done(false) }) { Text("Later") } },
            confirmButton = { Button(onClick = { done(true) }) { Text("Download") } },
        )
    } == true
    if (download) {
        runCatching {
            nav.context.startActivity(
                Intent(Intent.ACTION_VIEW, Uri.parse(info.apkUrl ?: info.url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        }
    }
}

private const val BACKUP_FOLDER = "backupFolderUri"

/** The backup folder picked before, while Ilay may still write there. */
private fun backupFolder(context: Context): Uri? {
    val uri = app.prefs.getString(BACKUP_FOLDER)?.let(Uri::parse) ?: return null
    return uri.takeIf { u -> context.contentResolver.persistedUriPermissions.any { it.uri == u && it.isWritePermission } }
}

/** "Download/Ilay" from a picked folder's tree id ("primary:Download/Ilay"). */
private fun folderLabel(uri: Uri): String =
    runCatching { DocumentsContract.getTreeDocumentId(uri).substringAfter(':').ifEmpty { "Internal storage" } }.getOrDefault(uri.toString())

/**
 * Writes the prefs backup into [folder] as `ilay-backup-<date>.json` (#116); without
 * one (no folder picker on the device), shares it as `ilay-backup.json` instead.
 */
private suspend fun backupData(context: Context, folder: Uri?) {
    try {
        val json = Backup.export(app.prefs)
        if (folder != null) {
            val name = "ilay-backup-${java.text.SimpleDateFormat("yyyy-MM-dd-HHmm", java.util.Locale.US).format(java.util.Date())}.json"
            withContext(Dispatchers.IO) {
                val dir = DocumentsContract.buildDocumentUriUsingTree(folder, DocumentsContract.getTreeDocumentId(folder))
                val doc = DocumentsContract.createDocument(context.contentResolver, dir, "application/json", name)
                    ?: throw java.io.IOException("Couldn't create the file")
                context.contentResolver.openOutputStream(doc)!!.use { it.write(json.toByteArray()) }
            }
            app.navigatorOrNull?.showSnackbar("Backed up to ${folderLabel(folder)}/$name")
            return
        }
        val file = withContext(Dispatchers.IO) {
            File(context.cacheDir, "ilay-backup.json").apply { writeText(json) }
        }
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", file)
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "application/json"
            putExtra(Intent.EXTRA_STREAM, uri)
            putExtra(Intent.EXTRA_SUBJECT, "Ilay backup")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(send, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    } catch (e: Exception) {
        app.navigatorOrNull?.showSnackbar("Backup failed: ${e.message ?: e}")
    }
}

internal suspend fun restoreData(context: Context, uri: Uri) {
    try {
        val text = withContext(Dispatchers.IO) {
            context.contentResolver.openInputStream(uri)?.use { it.readBytes().toString(Charsets.UTF_8) }
        } ?: return
        val n = Backup.import(app.prefs, text)
        reloadLocalData()
        infoDialog("Restore complete", "Imported $n settings. Restart Ilay to apply everything.", close = "OK")
    } catch (e: Exception) {
        app.navigatorOrNull?.showSnackbar("Restore failed: ${e.message ?: e}")
    }
}

/**
 * Re-reads everything a restore may have changed: settings, every per-account
 * store, and the session. ([com.bennybar.luli_for_reddit.AppContainer.start]
 * must not run twice, so this reloads the stores directly.)
 */
internal fun reloadLocalData() {
    app.settings.reload()
    // A restored icon choice only takes effect once its launcher entry is switched.
    AppIcon.apply(app.context, AppIcon.parse(app.settings.value.appIcon))
    val user = app.session.username
    listOf(
        app.postOverrides, app.commentVotes, app.redditNotifications, app.hiddenPosts, app.dismissedPosts, app.hiddenHomeSubs, app.summaries, app.history, app.threadVisits, app.contentFilters,
        app.offline, app.feed, app.post, app.forYou, app.inbox, app.media,
    ).forEach { it.onUserChanged(user) }
    app.session.reload()
}

/** "Keep feed for" choices: how long Home / For You keep their posts before returning to them loads new ones. */
private fun keepLabel(minutes: Int): String = when {
    minutes < 60 -> "$minutes minutes"
    minutes == 60 -> "1 hour"
    else -> "${minutes / 60} hours"
}

private fun dayLabel(days: Int): String = if (days == 1) "1 day" else "$days days"

/** For You's Familiar ↔ Discover mix: how often posts from communities you don't follow come up. */
@Composable
private fun ForYouMixSlider(value: Int, onChange: (Int) -> Unit) {
    val cs = MaterialTheme.colorScheme
    // Filled from the centre (Material 3 Expressive's centred track): 0 is
    // Balanced, so the fill shows which way and how far the mix leans.
    val state = remember { SliderState(value.toFloat(), 3, -2f..2f) }
    LaunchedEffect(value) { state.value = value.toFloat() }
    val v = state.value
    Column(Modifier.fillMaxWidth().padding(start = 56.dp, end = 24.dp, top = 8.dp, bottom = 4.dp)) {
        Text("For You mix", style = MaterialTheme.typography.bodyLarge)
        Text(
            when (v.roundToInt()) {
                -2 -> "Almost only your communities"
                -1 -> "Mostly your communities"
                1 -> "More from communities you don't follow"
                2 -> "Lots of new communities"
                else -> "Balanced: adapts to what you open (next refresh)"
            },
            style = MaterialTheme.typography.bodyMedium,
            color = cs.onSurfaceVariant,
        )
        Slider(
            state = state,
            onValueChange = { state.value = it },
            onValueChangeFinished = { onChange(state.value.roundToInt()) },
            track = { SliderDefaults.CenteredTrack(it) },
        )
        Row {
            Text("Familiar", Modifier.weight(1f), fontSize = 12.sp, color = cs.onSurfaceVariant)
            Text("Discover", fontSize = 12.sp, color = cs.onSurfaceVariant)
        }
    }
}

/** Settings → Second language: the languages Ilay can translate into (phone or service). */
private val TRANSLATE_LANGUAGES = listOf(
    "ar", "de", "en", "es", "fr", "he", "hi", "id", "it", "ja", "ko", "nl", "pl", "pt", "ru", "th", "tr", "uk", "vi", "zh",
)
