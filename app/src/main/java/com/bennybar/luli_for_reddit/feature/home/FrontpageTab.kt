package com.bennybar.luli_for_reddit.feature.home

import com.bennybar.luli_for_reddit.ui.SearchIcon
import androidx.compose.material.icons.outlined.VideoLibrary
import com.bennybar.luli_for_reddit.feature.feed.openMediaBrowser
import com.bennybar.luli_for_reddit.ui.switchThumb
import com.bennybar.luli_for_reddit.feature.feed.FabScroll
import com.bennybar.luli_for_reddit.feature.feed.FeedFab
import com.bennybar.luli_for_reddit.settings.HomeFab
import com.bennybar.luli_for_reddit.settings.postsTabKey
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalDensity
import com.bennybar.luli_for_reddit.feature.feed.FeedUi
import com.bennybar.luli_for_reddit.feature.feed.rememberFeedController
import com.bennybar.luli_for_reddit.feature.feed.rememberFeedListState
import com.bennybar.luli_for_reddit.feature.feed.rememberHidingBar
import com.bennybar.luli_for_reddit.feature.feed.HidingTopBar
import com.bennybar.luli_for_reddit.feature.feed.showTopPanel
import com.bennybar.luli_for_reddit.feature.feed.PanelButton
import com.bennybar.luli_for_reddit.feature.feed.PanelOuter
import com.bennybar.luli_for_reddit.feature.feed.PanelInner
import kotlinx.coroutines.launch
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.layout.offset
import androidx.compose.material.icons.outlined.PostAdd
import androidx.compose.material3.Switch
import androidx.compose.material3.Surface
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.PlayCircleOutline
import androidx.compose.material.icons.rounded.MoreHoriz
import androidx.compose.material.icons.rounded.Speed
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.HorizontalDivider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.auth.SessionState
import com.bennybar.luli_for_reddit.feature.feed.GlassSurface
import com.bennybar.luli_for_reddit.feature.feed.LetterAvatar
import com.bennybar.luli_for_reddit.feature.feed.PostListView
import com.bennybar.luli_for_reddit.feature.feed.SearchPill
import com.bennybar.luli_for_reddit.nav.AppNavigator
import com.bennybar.luli_for_reddit.nav.LocalNavigator
import com.bennybar.luli_for_reddit.nav.Route
import com.bennybar.luli_for_reddit.settings.PostDisplay
import com.bennybar.luli_for_reddit.settings.TopBarMode
import com.bennybar.luli_for_reddit.settings.TopBarMenuItem
import com.bennybar.luli_for_reddit.settings.topBarMenu

@Composable
internal fun currentUsername(): String {
    val session by app.session.state.collectAsStateWithLifecycle()
    return (session as? SessionState.LoggedIn)?.session?.username ?: ""
}

/** The Posts tab: the frontpage feed under its top bar (Full or Expandable mode). */
@Composable
internal fun FrontpageTab(selected: Boolean) {
    val cs = MaterialTheme.colorScheme
    val nav = LocalNavigator.current
    val username = currentUsername()
    val settings by app.settings.state.collectAsStateWithLifecycle()
    // Settings → "Posts tab shows r/all": plain r/all here, and Explore's All button opens the frontpage.
    val postsAll = settings.postsTabAll
    val feedKey = settings.postsTabKey
    val forYou = !postsAll && settings.forYouFeed
    val homeOn = !postsAll && settings.redditHomeAllowed && settings.redditHomeFeed
    val blend = forYou && settings.blendHome && settings.redditHomeAllowed
    val blendState by app.forYou.redditHome.blendState.collectAsStateWithLifecycle()
    val expandable = settings.topBarMode == TopBarMode.EXPANDABLE

    // The top bar floats over the feed and follows the finger, in and out (#55).
    val listState = rememberFeedListState()
    val scope = rememberCoroutineScope()
    val bar = rememberHidingBar(listState)

    val fab = remember { FabScroll() }
    var refreshRequests by remember { mutableIntStateOf(0) } // the Refresh floating button
    var hideReadRequests by remember { mutableIntStateOf(0) } // the Hide read posts floating button
    // Reloading starts a new list from the top; returning to the tab shows the bar too.
    val loaded = rememberFeedController(feedKey).ui.collectAsStateWithLifecycle().value is FeedUi.Data
    LaunchedEffect(loaded, selected) { if (!loaded || selected) bar.slide(0f) }

    // Full mode: Google-app style search bar with avatar.
    val actionRow: @Composable () -> Unit = {
            Row(
                // With the ☰ here: the same spot as on the other tabs (#34).
                Modifier.fillMaxWidth().padding(
                    start = if (LocalSideBar.current != null) 4.dp else 16.dp,
                    // In line with the search screen's bar.
                    top = 4.dp,
                    end = 16.dp,
                    bottom = 4.dp,
                ),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                SideBarButton()
                if (settings.showApiUsage) {
                    ApiUsagePill(Modifier.weight(1f))
                } else {
                    SearchPill("Search Reddit", onClick = { nav.push(Route.Search()) }, modifier = Modifier.weight(1f))
                }
                if (settings.fullBarNewPost) {
                    Spacer(Modifier.width(4.dp))
                    NewPostButton { nav.push(Route.Submit()) }
                }
                Spacer(Modifier.width(8.dp))
                // The menu, without what's already in this bar (#78).
                ProfileAvatar(username, 44.dp) { showFloatingToolbar(nav, username, { openMediaBrowser(nav, feedKey, listState) }, compact = true) }
            }
    }
    // The title row: the bar itself in Expandable mode; Full mode scrolls it with the feed.
    val titleRow: @Composable () -> Unit = {
        Row(
            Modifier.fillMaxWidth().padding(
                // With the ☰ there, line it up with the other tabs' (4dp + the button's own inset).
                // The feed (or, in Expandable mode, the bar) already insets it 7dp.
                start = if (expandable && LocalSideBar.current != null) 0.dp else 16.dp,
                top = if (expandable) (if (LocalSideBar.current != null) 8.dp else 10.dp) else 8.dp,
                end = if (expandable) 4.dp else 16.dp,
            ),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // Full mode has it in the action row above.
            if (expandable) SideBarButton(Modifier.offset(x = (-3).dp))
            Text(
                if (postsAll) "r/all" else if (homeOn) "Home" else if (blend) "Blend" else if (forYou) "For You" else "Frontpage",
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.ExtraBold,
            )
            if (!homeOn && forYou) {
                Spacer(Modifier.width(8.dp))
                Text(
                    if (blend) blendSubtitle(blendState) else "Personalized on your phone",
                    Modifier.weight(1f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    fontSize = 12.sp,
                    color = cs.onSurfaceVariant,
                )
            } else {
                Spacer(Modifier.weight(1f))
            }
            // Expandable mode: search right here, and one button that floats the toolbar in.
            if (expandable) {
                IconButton(onClick = { nav.push(Route.Search()) }) { Icon(SearchIcon, "Search") }
                IconButton(onClick = { showFloatingToolbar(nav, username, { openMediaBrowser(nav, feedKey, listState) }) }) {
                    Icon(Icons.Rounded.MoreHoriz, "Toolbar")
                }
            }
        }
    }
    Box(Modifier.fillMaxSize().clipToBounds().nestedScroll(bar).nestedScroll(fab)) {
        PostListView(
            feedKey = feedKey,
            postsTab = true,
            header = if (expandable) null else titleRow,
            topPadding = with(LocalDensity.current) { bar.height.toDp() },
            listState = listState,
            refreshRequests = refreshRequests,
            hideReadRequests = hideReadRequests,
            // Right under the bar when it's fully out, off the top when it's gone.
            floatingChipsY = if (!settings.floatingChips) null else bar::chipsY,
        )
        HidingTopBar(bar, Modifier.statusBarsPadding().padding(horizontal = if (expandable) 7.dp else 0.dp)) {
            if (expandable) titleRow() else actionRow()
        }
        FeedFab(
            // The Full bar's own New post button already does it: not two of them.
            if (!expandable && settings.fullBarNewPost && settings.homeFab == HomeFab.NEW_POST) HomeFab.OFF else settings.homeFab,
            fab.expanded,
            onNewPost = { nav.push(Route.Submit()) },
            onSearch = { nav.push(Route.Search()) },
            onTop = { scope.launch { listState.animateScrollToItem(0) } },
            onRefresh = { refreshRequests++ },
            onHideRead = { hideReadRequests++ },
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .navigationBarsPadding()
                .aboveFloatingNav()
                .padding(end = 16.dp, bottom = 16.dp),
        )
    }
}

@Composable
private fun NewPostButton(onClick: () -> Unit) {
    val cs = MaterialTheme.colorScheme
    FilledIconButton(
        onClick = onClick,
        colors = IconButtonDefaults.filledIconButtonColors(containerColor = cs.primary, contentColor = cs.onPrimary),
    ) { Icon(Icons.Outlined.PostAdd, "New post", Modifier.size(22.dp)) }
}

@Composable
private fun ProfileAvatar(username: String, size: Dp, onClick: () -> Unit) {
    val cs = MaterialTheme.colorScheme
    val me by app.feed.me.collectAsStateWithLifecycle()
    LaunchedEffect(username) { app.feed.loadMe() }
    LetterAvatar(
        username,
        size = size,
        container = cs.primaryContainer,
        content = cs.onPrimaryContainer,
        imageUrl = me?.iconUrl,
        fontSize = 16.sp,
        modifier = Modifier
            .semantics { contentDescription = "Your profile" }
            .clickable(role = Role.Button, onClick = onClick),
    )
}

/**
 * Shows live Reddit API rate-limit usage in place of the search bar
 * (power-user setting). Reddit allows ~100 requests/minute per OAuth client.
 */
@Composable
private fun ApiUsagePill(modifier: Modifier = Modifier) {
    val cs = MaterialTheme.colorScheme
    val rl by app.rateLimit.collectAsStateWithLifecycle()
    val r = rl
    val label = if (r == null) "API usage · no calls yet" else "API ${r.used}/${r.total} · resets ${r.secondsLeft()}s"
    GlassSurface(modifier) {
        Row(Modifier.padding(horizontal = 18.dp, vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Rounded.Speed, null, tint = cs.onSurfaceVariant)
            Spacer(Modifier.width(12.dp))
            Text(label, Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis, color = cs.onSurfaceVariant)
        }
    }
}

/**
 * Expandable top-bar mode: floats the full toolbar (search, new post,
 * display, profile) in from the top as a dismissible overlay — it never
 * displaces the feed.
 */
private fun showFloatingToolbar(nav: AppNavigator, username: String, onBrowseMedia: () -> Unit, compact: Boolean = false) {
    showTopPanel { close ->
        ToolbarPanel(
            username,
            compact = compact,
            onSearch = { close { nav.push(Route.Search()) } },
            onNewPost = { close { nav.push(Route.Submit()) } },
            onProfile = { close { nav.push(Route.User(username)) } },
            onSettings = { close { nav.push(Route.Settings) } },
            onBrowseMedia = { close(onBrowseMedia) },
        )
    }
}

/**
 * The top bar's panel: connected segments 3dp apart — search (with the
 * profile avatar), New post / Settings, Browse media, the feed layout as one
 * connected button group, and the autoplay switch, in the order and with the
 * buttons picked in Settings → Top bar menu (#108). Layout and autoplay
 * apply at once and leave the panel open, so the change is visible behind it.
 */
@Composable
private fun ToolbarPanel(
    username: String,
    compact: Boolean,
    onSearch: () -> Unit,
    onNewPost: () -> Unit,
    onProfile: () -> Unit,
    onSettings: () -> Unit,
    onBrowseMedia: () -> Unit,
) {
    val cs = MaterialTheme.colorScheme
    val settings by app.settings.state.collectAsStateWithLifecycle()
    val seg = cs.surfaceContainerHigh
    // The panel's rows: Your profile needs an account, and two half-width buttons
    // next to each other share a row (New post / Settings, Your profile / Settings).
    val signedIn = app.session.session?.anonymous == false
    val rows = mutableListOf<MutableList<TopBarMenuItem>>()
    for (e in settings.topBarMenu(if (compact) TopBarMode.FULL else TopBarMode.EXPANDABLE)) {
        if (!e.shown || (e.item == TopBarMenuItem.PROFILE && !signedIn)) continue
        val last = rows.lastOrNull()
        if (e.item.half && last != null && last.size == 1 && last[0].half) last += e.item else rows += mutableListOf(e.item)
    }
    Surface(shape = RoundedCornerShape(32.dp), color = cs.surfaceContainer, shadowElevation = 8.dp) {
        Column(Modifier.padding(8.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            rows.forEachIndexed { r, row ->
                // The first and last rows round off the panel's outer corners.
                val top = if (r == 0) PanelOuter else PanelInner
                val bottom = if (r == rows.lastIndex) PanelOuter else PanelInner
                fun shape(j: Int) = RoundedCornerShape(
                    topStart = if (j == 0) top else PanelInner,
                    topEnd = if (j == row.lastIndex) top else PanelInner,
                    bottomStart = if (j == 0) bottom else PanelInner,
                    bottomEnd = if (j == row.lastIndex) bottom else PanelInner,
                )
                if (row[0].half) {
                    Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                        row.forEachIndexed { j, item ->
                            val onClick = when (item) {
                                TopBarMenuItem.PROFILE -> onProfile
                                TopBarMenuItem.NEW_POST -> onNewPost
                                else -> onSettings
                            }
                            PanelButton(item.icon, item.label, Modifier.weight(1f), onClick, shape(j))
                        }
                    }
                } else when (row[0]) {
                    TopBarMenuItem.SEARCH -> Row(
                        Modifier
                            .fillMaxWidth()
                            .clip(shape(0))
                            .background(seg)
                            .clickable(onClick = onSearch)
                            .padding(start = 16.dp, end = 8.dp)
                            .height(60.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(SearchIcon, null, tint = cs.onSurfaceVariant)
                        Spacer(Modifier.width(12.dp))
                        Text("Search Reddit", Modifier.weight(1f), color = cs.onSurfaceVariant, maxLines = 1, fontSize = 16.sp)
                        ProfileAvatar(username, 44.dp, onProfile)
                    }
                    // The feed's images and videos, full screen, one after another (#103).
                    TopBarMenuItem.BROWSE_MEDIA ->
                        PanelButton(Icons.Outlined.VideoLibrary, "Browse media", Modifier.fillMaxWidth(), onBrowseMedia, shape(0))
                    TopBarMenuItem.LAYOUT -> Column(
                        Modifier
                            .fillMaxWidth()
                            .background(seg, shape(0))
                            .padding(start = 8.dp, end = 8.dp, bottom = 8.dp),
                    ) {
                        Text(
                            "Layout",
                            Modifier.padding(start = 6.dp, top = 12.dp, bottom = 8.dp),
                            fontSize = 13.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = cs.primary,
                        )
                        Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                            val all = PostDisplay.entries
                            all.forEachIndexed { i, d ->
                                val start = if (i == 0) 20.dp else PanelInner
                                val end = if (i == all.lastIndex) 20.dp else PanelInner
                                val on = d == settings.postDisplay
                                Column(
                                    Modifier
                                        .weight(1f)
                                        .height(76.dp)
                                        .clip(RoundedCornerShape(topStart = start, bottomStart = start, topEnd = end, bottomEnd = end))
                                        .background(if (on) cs.primary else cs.surfaceContainerHighest)
                                        // Pick-one for screen readers: "Calm, selected".
                                        .selectable(selected = on, role = Role.RadioButton) { app.settings.setPostDisplay(d) }
                                        .padding(horizontal = 2.dp),
                                    horizontalAlignment = Alignment.CenterHorizontally,
                                    verticalArrangement = Arrangement.Center,
                                ) {
                                    val fg = if (on) cs.onPrimary else cs.onSurface
                                    Icon(d.icon, null, Modifier.size(22.dp), tint = fg)
                                    Spacer(Modifier.height(6.dp))
                                    Text(d.label, fontSize = 11.sp, fontWeight = FontWeight.Medium, color = fg, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                }
                            }
                        }
                    }
                    TopBarMenuItem.AUTOPLAY -> Row(
                        Modifier
                            .fillMaxWidth()
                            .clip(shape(0))
                            .background(seg)
                            .toggleable(value = settings.autoplayMedia, role = Role.Switch) { app.settings.setAutoplayMedia(it) }
                            .padding(horizontal = 16.dp)
                            .height(60.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(Icons.Outlined.PlayCircleOutline, null, tint = cs.onSurfaceVariant)
                        Spacer(Modifier.width(14.dp))
                        Text("Autoplay media", Modifier.weight(1f), fontSize = 16.sp)
                        Switch(thumbContent = switchThumb(settings.autoplayMedia), checked = settings.autoplayMedia, onCheckedChange = null)
                    }
                    else -> {}
                }
            }
        }
    }
}

/** Blend's header subtitle: what its Reddit Home source is contributing right now. */
private fun blendSubtitle(state: com.bennybar.luli_for_reddit.feature.foryou.RedditHomeEngine.BlendState?): String = when (state) {
    is com.bennybar.luli_for_reddit.feature.foryou.RedditHomeEngine.BlendState.Included ->
        if (state.count == 0) "Beta · no Reddit Home picks yet" else "Beta · ${state.count} Reddit Home pick${if (state.count == 1) "" else "s"}"
    com.bennybar.luli_for_reddit.feature.foryou.RedditHomeEngine.BlendState.Loading -> "Beta · Reddit Home loading…"
    is com.bennybar.luli_for_reddit.feature.foryou.RedditHomeEngine.BlendState.Unavailable ->
        if (state.signedOut) "Beta · Reddit Home signed out: showing For You" else "Beta · Reddit Home unavailable: showing For You"
    null -> "Your Reddit Home + For You · Beta"
}
