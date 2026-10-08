package com.bennybar.luli_for_reddit.feature.settings

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
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.Sort
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material.icons.outlined.FilterAlt
import androidx.compose.material.icons.outlined.Forum
import androidx.compose.material.icons.outlined.Image
import androidx.compose.material.icons.outlined.Key
import androidx.compose.material.icons.outlined.MarkEmailRead
import androidx.compose.material.icons.outlined.NotificationsActive
import androidx.compose.material.icons.outlined.PlayCircleOutline
import androidx.compose.material.icons.outlined.SmartToy
import androidx.compose.material.icons.outlined.Timer
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material.icons.rounded.Api
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Backup
import androidx.compose.material.icons.rounded.BlurOn
import androidx.compose.material.icons.rounded.Brightness6
import androidx.compose.material.icons.rounded.Cached
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.CloudOff
import androidx.compose.material.icons.rounded.CreateNewFolder
import androidx.compose.material.icons.rounded.DarkMode
import androidx.compose.material.icons.rounded.DeleteForever
import androidx.compose.material.icons.rounded.Description
import androidx.compose.material.icons.rounded.Dns
import androidx.compose.material.icons.rounded.DoneAll
import androidx.compose.material.icons.rounded.ExpandMore
import androidx.compose.material.icons.rounded.FontDownload
import androidx.compose.material.icons.rounded.FormatSize
import androidx.compose.material.icons.rounded.Gavel
import androidx.compose.material.icons.rounded.Gif
import androidx.compose.material.icons.rounded.History
import androidx.compose.material.icons.rounded.Info
import androidx.compose.material.icons.rounded.Link
import androidx.compose.material.icons.rounded.OpenInBrowser
import androidx.compose.material.icons.rounded.Palette
import androidx.compose.material.icons.rounded.Public
import androidx.compose.material.icons.rounded.Restore
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Speed
import androidx.compose.material.icons.rounded.Straighten
import androidx.compose.material.icons.rounded.Swipe
import androidx.compose.material.icons.rounded.SystemUpdate
import androidx.compose.material.icons.rounded.Tune
import androidx.compose.material.icons.rounded.Update
import androidx.compose.material.icons.rounded.ViewHeadline
import androidx.compose.material.icons.rounded.VpnKey
import androidx.compose.material.icons.rounded.WarningAmber
import androidx.compose.material.icons.outlined.Dns
import androidx.compose.material.icons.automirrored.outlined.LabelImportant
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CheckboxDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.TopAppBar
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
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
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
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.core.Backup
import com.bennybar.luli_for_reddit.core.RedditConstants
import com.bennybar.luli_for_reddit.core.UpdateChecker
import com.bennybar.luli_for_reddit.data.COMMENT_SORTS
import com.bennybar.luli_for_reddit.data.PostSort
import com.bennybar.luli_for_reddit.feature.media.MediaFolderSettingRow
import com.bennybar.luli_for_reddit.nav.LocalNavigator
import com.bennybar.luli_for_reddit.nav.Route
import com.bennybar.luli_for_reddit.settings.PostDisplay
import com.bennybar.luli_for_reddit.settings.Settings
import com.bennybar.luli_for_reddit.settings.SwipeAction
import com.bennybar.luli_for_reddit.settings.ThemeMode
import com.bennybar.luli_for_reddit.settings.TopBarMode
import com.bennybar.luli_for_reddit.ui.Overlays
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import kotlin.math.roundToInt

private val ACCENT_SWATCHES = listOf(
    0xFF6750A4L, // Bloom lavender (default)
    0xFFEA4335L, // red
    0xFFFF7043L, // orange
    0xFFFFB300L, // amber
    0xFF34A853L, // green
    0xFF00897BL, // teal
    0xFF1E88E5L, // blue
    0xFF8E24AAL, // purple
    0xFFD81B60L, // pink
)

/** AI summary styles, by persisted index (`aiSummaryStyle`). */
private val SUMMARY_STYLE_LABELS = listOf("TL;DR", "Key points", "Consensus & disagreements", "Explain like I'm 5")

private val AI_MODELS = listOf("gpt-6.1-sol", "gpt-5.5", "gpt-5.4-mini", "gpt-5.4-nano")

// Where saved media goes (same prefs keys as the Flutter build). null = the
// gallery's "Ilay" album.

private fun themeLabel(m: ThemeMode) = when (m) {
    ThemeMode.SYSTEM -> "Follow system"
    ThemeMode.LIGHT -> "Light"
    ThemeMode.DARK -> "Dark"
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen() {
    val nav = LocalNavigator.current
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Settings") },
                navigationIcon = {
                    IconButton(onClick = { nav.pop() }) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Back") }
                },
            )
        },
    ) { padding ->
        SettingsList(contentPadding = padding)
    }
}

/** One row of the settings list; [search] = its title + subtitle, null = not searchable. */
private class Entry(val key: String, val search: String?, val content: @Composable () -> Unit)

/**
 * The settings list — reusable both as the full Settings screen and embedded
 * (e.g. inside the Account tab). Pass [embedded] when nesting in a scroll view.
 */
@Composable
fun SettingsList(
    modifier: Modifier = Modifier,
    embedded: Boolean = false,
    contentPadding: PaddingValues = PaddingValues(),
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
    var authMode by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(secureVersion, session) {
        aiKeySet = !app.secureStore.openaiKey().isNullOrEmpty()
        giphyKeySet = !app.secureStore.giphyKey().isNullOrEmpty()
        authMode = runCatching { app.secureStore.authMode() }.getOrNull()
    }
    val web = authMode == "web"

    val pickBackup = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) scope.launch { restoreData(context, uri) }
    }

    val all = buildList {
        fun section(title: String) = add(Entry("h:$title", null) { SectionHeader(title) })
        fun divider(k: String) = add(Entry("d:$k", null) { HorizontalDivider(Modifier.padding(vertical = 4.dp)) })
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

        // ---------------------------------------------------------------- Appearance
        section("Appearance")
        tile("Theme", themeLabel(s.themeMode), Icons.Rounded.Brightness6, onClick = launch {
            pickOption(ThemeMode.entries.map { PickOption(it, themeLabel(it)) }, s.themeMode)?.let(ctrl::setThemeMode)
        })
        switch("AMOLED black", "Pure black surfaces in dark mode", Icons.Rounded.DarkMode, s.amoled, ctrl::setAmoled)
        switch(
            "Plus Jakarta Sans font", "Use the app's own font instead of the default (Roboto)",
            Icons.Rounded.FontDownload, s.jakartaFont, ctrl::setJakartaFont,
        )
        switch("Dynamic color", "Use colors from your wallpaper", Icons.Rounded.Palette, s.useDynamicColor, ctrl::setUseDynamicColor)
        add(Entry("accent", null) { AccentPicker(s) })
        tile("Font size", "${(s.textScale * 100).roundToInt()}% of normal", Icons.Rounded.FormatSize)
        add(Entry("fontSlider", null) {
            Row(Modifier.padding(start = 16.dp, end = 16.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("A", fontSize = 13.sp)
                Slider(
                    value = s.textScale.toFloat(),
                    onValueChange = { ctrl.setTextScale((it * 20).roundToInt() / 20.0) },
                    valueRange = 0.8f..1.4f,
                    steps = 11,
                    modifier = Modifier.weight(1f).padding(horizontal = 8.dp),
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
        tile("Top bar", s.topBarMode.label, Icons.Rounded.ViewHeadline, onClick = launch {
            pickOption(TopBarMode.entries.map { PickOption(it, it.label, it.description) }, s.topBarMode)
                ?.let(ctrl::setTopBarMode)
        })
        switch(
            "Bottom bar labels", "Show text labels under the navigation icons",
            Icons.AutoMirrored.Outlined.LabelImportant, s.navLabels, ctrl::setNavLabels,
        )
        divider("appearance")

        // ---------------------------------------------------------------- Feed
        section("Feed")
        tile("Default sort", s.defaultSort.label, Icons.AutoMirrored.Rounded.Sort, onClick = launch {
            pickOption(PostSort.entries.map { PickOption(it, it.label) }, s.defaultSort)?.let(ctrl::setDefaultSort)
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
            Icons.Rounded.ExpandMore, s.tapToCollapse, ctrl::setTapToCollapse,
        )
        tile("Post display", s.postDisplay.label, s.postDisplay.icon, onClick = launch {
            pickOption(PostDisplay.entries.map { PickOption(it, it.label, icon = it.icon) }, s.postDisplay)
                ?.let(ctrl::setPostDisplay)
        })
        switch("Blur NSFW media", "Tap to reveal blurred images", Icons.Rounded.BlurOn, s.blurNsfw, ctrl::setBlurNsfw)
        switch(
            "Data-saver thumbnails", "Load smaller preview images in feeds (faster, less data)",
            Icons.Outlined.Image, s.midResThumbnails, ctrl::setMidResThumbnails,
        )
        switch(
            "\"For You\" feed (Beta)",
            "Personalized frontpage built on-device. Reddit's own recommendations aren't available to third-party apps.",
            Icons.Rounded.AutoAwesome, s.forYouFeed, ctrl::setForYouFeed,
        )
        switch(
            "Auto-hide read items in \"For You\"", "Hide posts you've marked/opened as read",
            Icons.Outlined.MarkEmailRead, s.autoHideReadForYou, ctrl::setAutoHideReadForYou,
        )
        val homeSubtitle = if (web) "RISK TO YOUR ACCOUNT: against Reddit's terms. Shows your real reddit.com Home"
        else "Needs website sign-in"
        add(Entry("s:redditHome", "Reddit Home (experimental) $homeSubtitle") {
            SwitchTile(
                "Reddit Home (experimental)", homeSubtitle, Icons.Rounded.WarningAmber, s.redditHomeAllowed,
                accent = cs.error, titleWeight = FontWeight.Bold,
                onChange = if (!web && !s.redditHomeAllowed) null else { v ->
                    if (!v) ctrl.setRedditHomeAllowed(false)
                    else scope.launch { if (confirmRedditHome()) ctrl.setRedditHomeAllowed(true) }
                },
            )
        })
        switch(
            "Hide read posts", "Skip posts you've already read when feeds load or refresh",
            Icons.Outlined.VisibilityOff, s.hideReadPosts, ctrl::setHideReadPosts,
        )
        switch(
            "Mark read as you scroll",
            if (s.trackHistory) "A post you scroll past counts as read" else "Needs history tracking turned on",
            Icons.Rounded.DoneAll, s.markReadOnScroll, if (s.trackHistory) ctrl::setMarkReadOnScroll else null,
        )
        tile("Manage \"For You\" subreddits", "Review and undo muted / show-less subreddits", Icons.Rounded.Tune) {
            nav.push(Route.ManageForYou)
        }
        tile("Content filters", "Hide posts by keyword, domain or flair", Icons.Outlined.FilterAlt) {
            nav.push(Route.ContentFilters)
        }
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
            "Autoplay videos", "Play videos muted as you scroll the feed",
            Icons.Outlined.PlayCircleOutline, s.autoplayMedia, ctrl::setAutoplayMedia,
        )
        add(Entry("mediaFolder", "Save media to folder gallery") { MediaFolderSettingRow() })
        switch(
            "Open links inside the app",
            "Web links open in an in-app browser tab instead of your browser app",
            Icons.Rounded.OpenInBrowser, s.inAppBrowser, ctrl::setInAppBrowser,
        )
        divider("feed")

        // ---------------------------------------------------------------- Power-user
        section("Power-user features")
        switch(
            "Show API usage instead of search",
            "Replace the search bar on the Posts screen with your live Reddit API rate-limit usage",
            Icons.Rounded.Speed, s.showApiUsage, ctrl::setShowApiUsage,
        )
        add(Entry("rateLimit", "API usage") { RateLimitTile() })
        divider("power")

        // ---------------------------------------------------------------- Notifications
        section("Notifications")
        switch(
            "Inbox notifications",
            "Check for replies & messages in the background (~every 15 min) and notify you. No Firebase — polling only.",
            Icons.Outlined.NotificationsActive, s.notifyInbox,
        ) { v -> scope.launch { toggleInboxNotifications(v) } }
        divider("notifications")

        // ---------------------------------------------------------------- AI
        section("AI summaries")
        tile(
            "OpenAI API key",
            if (aiKeySet) "Key set — tap to change or remove" else "Add a key to enable thread summaries",
            Icons.Outlined.Key,
            onClick = launch {
                val r = textDialog(
                    "OpenAI API key", hint = "sk-…", secret = true, removable = aiKeySet,
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
            pickOption(AI_MODELS.map { PickOption(it, it) }, s.aiModel, radio = false)?.let(ctrl::setAiModel)
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
            "Custom API base URL", "Advanced — use an OpenAI-compatible endpoint (e.g. LiteLLM)",
            Icons.Rounded.Dns, s.aiUseCustomUrl, ctrl::setAiUseCustomUrl,
        )
        if (s.aiUseCustomUrl) {
            tile("API base URL", s.aiBaseUrl, Icons.Rounded.Link, onClick = launch {
                val r = textDialog(
                    "API base URL", initial = s.aiBaseUrl, hint = "https://your-litellm-host", keyboardType = KeyboardType.Uri,
                ) as? TextResult.Save ?: return@launch
                if (r.text.isNotBlank()) ctrl.setAiBaseUrl(r.text.trim())
            })
        }
        divider("ai")

        // ---------------------------------------------------------------- History & data
        section("History & data")
        tile("Saved", "Search your saved posts & comments", Icons.Outlined.BookmarkBorder) { nav.push(Route.Saved) }
        tile("History", "Recently viewed (stored on this device)", Icons.Rounded.History) { nav.push(Route.History) }
        switch("Track history", "Remember and dim viewed posts (local only)", Icons.Outlined.Visibility, s.trackHistory, ctrl::setTrackHistory)
        switch("Offline cache", "Show the last loaded content when offline", Icons.Rounded.CloudOff, s.offlineCache, ctrl::setOfflineCache)
        switch(
            "Cache subscriptions", "Keep your subreddit list in memory to speed up \"For You\"",
            Icons.Outlined.Dns, s.subsCacheEnabled, ctrl::setSubsCacheEnabled,
        )
        tile("Subscriptions cache time", "${s.subsCacheMinutes} minutes", Icons.Outlined.Timer, enabled = s.subsCacheEnabled, onClick = launch {
            pickOption(listOf(5, 10, 30, 60).map { PickOption(it, "$it minutes") }, s.subsCacheMinutes)
                ?.let(ctrl::setSubsCacheMinutes)
        })
        tile("Clear cache", icon = Icons.Rounded.Cached, onClick = launch {
            app.client.clearCache()
            nav.showSnackbar("Cache cleared")
        })
        tile("Back up data", "Export settings, For You model & history (no login/keys)", Icons.Rounded.Backup) {
            scope.launch { backupData(context) }
        }
        tile("Restore data", "Import a backup file", Icons.Rounded.Restore) {
            runCatching { pickBackup.launch(arrayOf("application/json", "application/octet-stream", "text/*")) }
                .onFailure { nav.showSnackbar("Restore failed: ${it.message}") }
        }
        divider("data")

        // ---------------------------------------------------------------- About
        section("About")
        switch("Check for updates", "Check GitHub releases on launch", Icons.Rounded.SystemUpdate, s.checkUpdates, ctrl::setCheckUpdates)
        tile("Check now", icon = Icons.Rounded.Update, onClick = launch { checkUpdatesNow() })
        tile(
            "Open reddit links in Ilay",
            "Already supported via the Android \"open with\" chooser. To make Ilay the verified default, " +
                "enable it under system app settings › Open by default.",
            Icons.Rounded.Link,
        )
        tile("Content & conduct policy", icon = Icons.Rounded.Gavel) { nav.push(Route.Policy) }
        tile("Open-source licenses", "Fonts: Plus Jakarta Sans, Unbounded (SIL OFL 1.1)", Icons.Rounded.Description, onClick = launch {
            val text = withContext(Dispatchers.IO) {
                runCatching { context.assets.open("OFL.txt").bufferedReader().use { it.readText() } }.getOrDefault("")
            }
            infoDialog("Licenses", text)
        })
        tile("Version", RedditConstants.APP_VERSION, Icons.Rounded.Info)
        divider("about")

        // ---------------------------------------------------------------- Account
        section("Account")
        tile(
            "Login method",
            if (web) "Website session (no API key) — unofficial" else "Reddit API key (recommended)",
            if (web) Icons.Rounded.Public else Icons.Rounded.Api,
            onClick = launch { showLoginMethodInfo(web) },
        )
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
        add(Entry("bottom", null) { Spacer(Modifier.height(24.dp)) })
    }

    val q = query.trim().lowercase()
    val shown = if (q.isEmpty()) all else all.filter { it.search?.lowercase()?.contains(q) == true }

    val searchField = @Composable {
        TextField(
            value = query,
            onValueChange = { query = it },
            singleLine = true,
            placeholder = { Text("Search settings") },
            leadingIcon = { Icon(Icons.Rounded.Search, null) },
            shape = RoundedCornerShape(24.dp),
            colors = TextFieldDefaults.colors(
                focusedContainerColor = cs.surfaceContainerHigh,
                unfocusedContainerColor = cs.surfaceContainerHigh,
                focusedIndicatorColor = Color.Transparent,
                unfocusedIndicatorColor = Color.Transparent,
            ),
            modifier = Modifier.fillMaxWidth().padding(start = 16.dp, top = 12.dp, end = 16.dp, bottom = 4.dp),
        )
    }
    val noResults = @Composable {
        Box(Modifier.fillMaxWidth().padding(40.dp), contentAlignment = Alignment.Center) { Text("No settings found") }
    }

    if (embedded) {
        Column(modifier) {
            searchField()
            shown.forEach { it.content() }
            if (q.isNotEmpty() && shown.isEmpty()) noResults()
        }
    } else {
        LazyColumn(modifier.fillMaxSize(), contentPadding = contentPadding) {
            item(key = "search") { searchField() }
            items(shown, key = { it.key }) { it.content() }
            if (q.isNotEmpty() && shown.isEmpty()) item(key = "none") { noResults() }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun AccentPicker(s: Settings) {
    val cs = MaterialTheme.colorScheme
    Column(
        Modifier
            .alpha(if (s.useDynamicColor) 0.4f else 1f)
            .padding(start = 16.dp, top = 8.dp, end = 16.dp, bottom = 16.dp),
    ) {
        Text("Accent color", style = MaterialTheme.typography.bodyMedium)
        Spacer(Modifier.height(10.dp))
        FlowRow(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            for (c in ACCENT_SWATCHES) {
                val selected = s.seedColor == c
                Box(
                    Modifier
                        .size(40.dp)
                        .background(Color(c), CircleShape)
                        .border(BorderStroke(3.dp, if (selected) cs.onSurface else Color.Transparent), CircleShape)
                        .clickable(enabled = !s.useDynamicColor) { app.settings.setSeedColor(c) },
                    contentAlignment = Alignment.Center,
                ) {
                    if (selected) Icon(Icons.Rounded.Check, null, tint = Color.White)
                }
            }
        }
    }
}

@Composable
private fun RateLimitTile() {
    val rl by app.rateLimit.collectAsStateWithLifecycle()
    SettingTile(
        "API usage",
        rl?.let { "${it.used}/${it.total} used this window · resets in ${it.resetSeconds}s" }
            ?: "Reddit allows roughly 100 requests/minute. No data yet.",
        Icons.Rounded.Speed,
    )
}

/** "Save media to" sheet: true = gallery, false = choose a folder, null = dismissed. */

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
                val options = SwipeAction.entries.filter { it != (if (forPosts) SwipeAction.COLLAPSE else SwipeAction.HIDE) }
                var open by remember { mutableStateOf(false) }
                SettingTile(label, trailing = {
                    Box {
                        TextButton(onClick = { open = true }) {
                            Icon(value.icon, null, Modifier.size(18.dp))
                            Spacer(Modifier.width(8.dp))
                            Text(value.label)
                            Icon(Icons.Rounded.ExpandMore, null)
                        }
                        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
                            for (a in options) {
                                DropdownMenuItem(
                                    text = { Text(a.label) },
                                    leadingIcon = { Icon(a.icon, null, Modifier.size(18.dp)) },
                                    onClick = {
                                        open = false
                                        app.settings.setSwipeAction(key, a)
                                    },
                                )
                            }
                        }
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

/** The risk warning for the experimental Reddit Home feed. True if accepted. */
private suspend fun confirmRedditHome(): Boolean = Overlays.show<Boolean> { done ->
    val cs = MaterialTheme.colorScheme
    var accepted by remember { mutableStateOf(false) } // the checkbox must be ticked before enabling
    AlertDialog(
        onDismissRequest = { done(false) },
        containerColor = cs.errorContainer,
        icon = { Icon(Icons.Rounded.WarningAmber, null, Modifier.size(56.dp), tint = cs.error) },
        title = {
            Text(
                "Your Reddit account is at risk",
                textAlign = TextAlign.Center,
                color = cs.onErrorContainer,
                fontWeight = FontWeight.Black,
            )
        },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState())) {
                val body = MaterialTheme.typography.bodyMedium.copy(color = cs.onErrorContainer, lineHeight = 20.sp)
                Text(
                    "Reddit can SUSPEND OR BAN your account for this. Use it only if you accept that risk.",
                    color = cs.onError,
                    fontWeight = FontWeight.ExtraBold,
                    fontSize = 15.sp,
                    modifier = Modifier.fillMaxWidth().background(cs.error, RoundedCornerShape(12.dp)).padding(12.dp),
                )
                Spacer(Modifier.height(14.dp))
                Text(
                    "Reddit Home shows your real reddit.com Home feed by loading reddit.com in a hidden browser " +
                        "with your website sign-in and reading which posts it shows.",
                    style = body,
                )
                Spacer(Modifier.height(10.dp))
                Text("• It is NOT an official API. Reddit's User Agreement prohibits automated access to its site.", style = body)
                Spacer(Modifier.height(6.dp))
                Text("• It can stop working whenever Reddit changes its site. Ilay then shows For You instead.", style = body)
                Spacer(Modifier.height(6.dp))
                Text("• Website sign-in only. It talks only to reddit.com.", style = body)
                Spacer(Modifier.height(8.dp))
                Row(
                    Modifier.fillMaxWidth().clickable { accepted = !accepted }.padding(vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Checkbox(
                        checked = accepted,
                        onCheckedChange = { accepted = it },
                        colors = CheckboxDefaults.colors(checkedColor = cs.error, checkmarkColor = cs.onError),
                    )
                    Spacer(Modifier.width(8.dp))
                    Text(
                        "I understand Reddit may suspend my account",
                        color = cs.onErrorContainer,
                        fontWeight = FontWeight.Bold,
                    )
                }
            }
        },
        dismissButton = { FilledTonalButton(onClick = { done(false) }) { Text("Cancel") } },
        confirmButton = {
            Button(
                onClick = { done(true) },
                enabled = accepted,
                colors = ButtonDefaults.buttonColors(containerColor = cs.error, contentColor = cs.onError),
            ) { Text("Enable anyway") }
        },
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

/** Shares the prefs backup as `ilay-backup.json` (FileProvider, from the cache dir). */
private suspend fun backupData(context: Context) {
    try {
        val json = Backup.export(app.prefs)
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

private suspend fun restoreData(context: Context, uri: Uri) {
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
    val user = app.session.username
    listOf(
        app.postOverrides, app.hiddenPosts, app.history, app.threadVisits, app.contentFilters,
        app.offline, app.feed, app.post, app.forYou, app.inbox, app.media,
    ).forEach { it.onUserChanged(user) }
    app.session.reload()
}
