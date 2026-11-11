package com.bennybar.luli_for_reddit.feature.home

import androidx.compose.material.icons.rounded.Star
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material.icons.rounded.Bookmark
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.EditNote
import androidx.compose.material.icons.outlined.OfflinePin
import androidx.compose.material.icons.outlined.DynamicFeed
import com.bennybar.luli_for_reddit.ui.subredditName
import com.bennybar.luli_for_reddit.model.Subreddit
import com.bennybar.luli_for_reddit.feature.feed.SectionHeader
import com.bennybar.luli_for_reddit.feature.feed.LetterAvatar
import com.bennybar.luli_for_reddit.feature.feed.Async
import com.bennybar.luli_for_reddit.core.compactNumber
import androidx.compose.ui.text.style.TextOverflow
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.compose.ui.semantics.Role
import androidx.compose.foundation.selection.selectable
import androidx.compose.material.icons.rounded.DynamicFeed
import kotlinx.coroutines.launch
import com.bennybar.luli_for_reddit.auth.SessionState
import androidx.compose.material.icons.rounded.EditNote
import androidx.compose.material.icons.rounded.OfflinePin
import androidx.compose.material.icons.rounded.History
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.rememberDrawerState
import androidx.compose.material3.NavigationDrawerItem
import androidx.compose.material3.ModalNavigationDrawer
import androidx.compose.material3.ModalDrawerSheet
import androidx.compose.material3.DrawerValue
import androidx.compose.material3.DrawerState
import androidx.compose.material.icons.rounded.Schedule
import androidx.compose.material.icons.outlined.StarBorder
import com.bennybar.luli_for_reddit.settings.SideBarItem
import androidx.compose.material3.MotionScheme
import com.bennybar.luli_for_reddit.feature.about.maybeShowWhatsNew
import androidx.activity.compose.BackHandler
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.layout.positionInParent
import androidx.compose.ui.layout.onPlaced
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.Brush
import androidx.compose.foundation.BorderStroke
import androidx.compose.animation.animateContentSize
import android.content.Intent
import android.net.Uri
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AccountCircle
import androidx.compose.material.icons.outlined.Explore
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.NotificationsActive
import androidx.compose.material.icons.rounded.AccountCircle
import androidx.compose.material.icons.rounded.Explore
import androidx.compose.material.icons.rounded.Home
import androidx.compose.material.icons.rounded.Mail
import androidx.compose.material.icons.rounded.MailOutline
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Velocity
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.core.UpdateChecker
import com.bennybar.luli_for_reddit.feature.inbox.InboxScreen
import com.bennybar.luli_for_reddit.nav.LocalNavigator
import com.bennybar.luli_for_reddit.nav.Route
import com.bennybar.luli_for_reddit.ui.Overlays

/** Prefs flag: have we shown the one-time notifications suggestion? */
private const val NOTIF_PROMPTED_PREF = "notifyInboxPrompted"

private class NavItem(val off: ImageVector, val on: ImageVector, val label: String)

private val navItems = listOf(
    NavItem(Icons.Outlined.Home, Icons.Rounded.Home, "Posts"),
    NavItem(Icons.Outlined.Explore, Icons.Rounded.Explore, "Explore"),
    NavItem(Icons.Rounded.MailOutline, Icons.Rounded.Mail, "Inbox"),
    NavItem(Icons.Outlined.AccountCircle, Icons.Rounded.AccountCircle, "Profile"),
)

/** The home shell: Posts / Explore / Inbox / Profile tabs with the floating "Pop" pill nav. */
@Composable
fun HomeScreen() {
    val nav = LocalNavigator.current
    val context = LocalContext.current
    var index by rememberSaveable { mutableIntStateOf(0) }
    var chrome by rememberSaveable { mutableStateOf(true) }
    var lastExploreTap by remember { mutableLongStateOf(0L) }
    val unread by app.inbox.unreadCount.collectAsStateWithLifecycle()
    val settings by app.settings.state.collectAsStateWithLifecycle()
    val inboxReselect by app.feed.tabReselect(2).collectAsStateWithLifecycle()

    // Each time the home shell is created (app start, after signing in
    // again): GitHub update check, then the one-time notifications
    // suggestion. Saveable, so returning from a pushed screen or rotating
    // doesn't re-run it.
    var startupChecksDone by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        if (startupChecksDone) return@LaunchedEffect
        startupChecksDone = true
        maybeCheckUpdates(context)
        maybeShowWhatsNew()
        maybeSuggestNotifications()
    }

    // A notification tap asks for a tab (Inbox).
    val openTab by app.feed.openTab.collectAsStateWithLifecycle()
    LaunchedEffect(openTab) {
        openTab?.let {
            index = it
            chrome = true
            app.feed.openTab.value = null
        }
    }

    // Settings › Navigation: the bottom bar, the side bar, or both.
    val bottomBar = settings.navStyle != 1
    val sideBar = settings.navStyle != 0
    // Not saved with the back stack: a side-bar page opens with no transition (#118),
    // so Home leaves before the side bar finishes closing, and a saved state brought
    // it back open on the next tab picked (#136).
    val drawer = remember { DrawerState(DrawerValue.Closed) }
    val shellScope = rememberCoroutineScope()

    // Snackbars float above the floating nav while the shell is showing.
    DisposableEffect(nav, bottomBar) {
        nav.snackbarBottomPadding = if (bottomBar) 86.dp else 0.dp
        onDispose { nav.snackbarBottomPadding = 0.dp }
    }

    // Hide the nav while scrolling down, reveal on
    // scrolling up or reaching the top — any tab's main list. Mirrors
    // Flutter's UserScrollNotification handling: decide when the user's
    // drag direction changes and when scrolling settles (a fling landing);
    // near the top (≤ 4px) or overscrolling, always show.
    val scrollConnection = remember {
        object : NestedScrollConnection {
            // How far each tab's list is from its top, tracked from the
            // scroll deltas (lists start at the top; null = unknown).
            val fromTop = arrayOfNulls<Float>(4).apply { fill(0f) }
            var direction = 0 // last user direction: -1 down the list, 1 up, 0 idle

            fun nearTop() = (fromTop[index] ?: Float.MAX_VALUE) <= 4f

            fun update(dir: Int) {
                chrome = when {
                    nearTop() -> true
                    dir < 0 -> false
                    dir > 0 -> true
                    else -> chrome
                }
            }

            override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
                if (source == NestedScrollSource.UserInput) {
                    val dir = if (available.y < -1f) -1 else if (available.y > 1f) 1 else 0
                    if (dir != 0 && dir != direction) {
                        direction = dir
                        update(dir)
                    }
                }
                return Offset.Zero
            }

            override fun onPostScroll(consumed: Offset, available: Offset, source: NestedScrollSource): Offset {
                if (available.y > 0f) {
                    // Overscrolling at the top: keep the chrome shown.
                    fromTop[index] = 0f
                    chrome = true
                } else {
                    fromTop[index] = fromTop[index]?.let { (it - consumed.y).coerceAtLeast(0f) }
                    // A drag that starts at the top is still "near top" when
                    // its direction is first seen: leaving the top decides (#55).
                    if (direction != 0) update(direction)
                }
                return Offset.Zero
            }

            override suspend fun onPostFling(consumed: Velocity, available: Velocity): Velocity {
                // The scroll settled (drag released / fling landed).
                direction = 0
                if (available.y > 0f) fromTop[index] = 0f
                update(0)
                return Velocity.Zero
            }
        }
    }

    // Back never leaves the app from here. With the side bar on: to the top of
    // the page, then to Posts (#70), then it opens the side bar (so the edge
    // swipe that gesture navigation keeps for Back still brings it out; Back
    // again closes it). Otherwise,
    // on another tab it returns to Posts, on Posts it scrolls the feed to top
    // (a setting, on by default) or does nothing (the Home button / recents
    // leave instead).
    // Sheets, viewers and pushed screens register their own, later handlers,
    // which take precedence.
    BackHandler {
        if (drawer.isOpen) {
            shellScope.launch { drawer.close() }
        } else if (sideBar) {
            if (!scrollConnection.nearTop() && (index != 0 || app.settings.value.backScrollsToTop)) {
                if (index == 0) app.feed.frontpageBackSignal.value++ else app.feed.tabReselect(index).value++
                scrollConnection.fromTop[index] = 0f // that scroll isn't seen by the connection
                chrome = true
            } else if (index != 0) {
                index = 0
                chrome = true
            } else {
                shellScope.launch { drawer.open() }
            }
        } else if (index != 0) {
            index = 0
            chrome = true
        } else if (app.settings.value.backScrollsToTop) {
            app.feed.frontpageBackSignal.value++
            chrome = true
        }
    }

    // Compose the other tabs one frame after the first paint (the Posts tab
    // shows first); they then stay alive like Flutter's IndexedStack.
    var allTabs by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        withFrameNanos { }
        allTabs = true
    }

    val navOffset by animateFloatAsState(if (chrome) 0f else 1.4f, tween(220, easing = FastOutSlowInEasing), label = "nav")
    // For the tabs' floating buttons (LocalNavHidden): past 1 the nav only clears its shadow.
    val navHidden = remember { { navOffset.coerceIn(0f, 1f) } }

    fun selectTab(i: Int) {
        // Double-tapping Explore opens search, keyboard up.
        val now = System.currentTimeMillis()
        if (i == 1 && now - lastExploreTap < 400) {
            lastExploreTap = 0L
            nav.push(Route.Search())
            return
        }
        if (i == 1) lastExploreTap = now
        // Re-tapping the active tab scrolls it to top (Posts also refreshes).
        if (i == index) {
            if (i == 0) app.feed.frontpageScrollSignal.value++ else app.feed.tabReselect(i).value++
            scrollConnection.fromTop[i] = 0f // that scroll isn't seen by the connection
        } else {
            index = i
            chrome = true // always reveal chrome when switching tabs
        }
    }

    SideBarDrawer(drawer, sideBar, selected = index, current = null, unread = unread, onTab = ::selectTab) {
    // The tabs' floating buttons follow the nav down as it hides (aboveFloatingNav).
    CompositionLocalProvider(LocalNavHidden provides navHidden.takeIf { bottomBar }) {
    Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surface)) {
        KeepAliveTabs(
            selected = index,
            count = 4,
            composeAll = allTabs,
            modifier = Modifier.fillMaxSize().nestedScroll(scrollConnection),
        ) { i ->
            when (i) {
                // Its feed runs under the status bar; it pads its own top bar.
                0 -> FrontpageTab(selected = index == 0)
                1 -> ExploreTab() // runs under the status bar, with its own fade (#127)
                2 -> Box(Modifier.statusBarsPadding()) { InboxScreen(reselect = inboxReselect, selected = index == 2) }
                else -> Box(Modifier.statusBarsPadding()) { ProfileTab() }
            }
        }
        // Content fades out just below the status bar, rather than being cut off (#74).
        // (Posts and Explore have their own, softer one.)
        val fade = MaterialTheme.colorScheme.surface
        if (index >= 2) Box(
            Modifier
                .fillMaxWidth()
                .statusBarsPadding()
                .height(8.dp)
                .background(Brush.verticalGradient(listOf(fade, fade.copy(alpha = 0f)))),
        )
        if (bottomBar) {
        // A fade from the page colour behind the nav, so the pill never sits
        // directly on a post of the same tone; it hides with the nav.
        val scrim = MaterialTheme.colorScheme.surface
        Box(
            Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .graphicsLayer { alpha = (1f - navOffset).coerceIn(0f, 1f) }
                .background(Brush.verticalGradient(listOf(scrim.copy(alpha = 0f), scrim.copy(alpha = 0.92f))))
                .navigationBarsPadding()
                .height(130.dp),
        )
        FloatingNav(
            selected = index,
            unread = unread,
            showLabels = settings.navLabels,
            outline = settings.navOutline,
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .graphicsLayer { translationY = size.height * navOffset },
            onSelected = ::selectTab,
        )
        }
    }
    }
    }
}

/**
 * A page the side bar opened (#111), e.g. Settings or a subreddit: one of its
 * destinations rather than a page pushed on top. Its top bar shows ☰ (via
 * [LocalSideBar]), the side bar swipes out over it and marks it, and Back
 * returns to Posts. With the side bar turned off (say, in the Settings it
 * opened) it's a plain page again.
 */
@Composable
fun SideBarPage(route: Route, content: @Composable () -> Unit) {
    val nav = LocalNavigator.current
    val settings by app.settings.state.collectAsStateWithLifecycle()
    val unread by app.inbox.unreadCount.collectAsStateWithLifecycle()
    val drawer = rememberDrawerState(DrawerValue.Closed)
    SideBarDrawer(drawer, settings.navStyle != 0, selected = -1, current = route, unread = unread, onTab = nav::openTabFromSideBar, content = content)
}

/**
 * The side bar over [content] when [enabled], for the home shell and for the
 * pages it opens: [selected] is the current tab (-1: none), [current] the
 * current page it opened (null: the home shell).
 */
@Composable
private fun SideBarDrawer(
    drawer: DrawerState,
    enabled: Boolean,
    selected: Int,
    current: Route?,
    unread: Int,
    onTab: (Int) -> Unit,
    content: @Composable () -> Unit,
) {
    val scope = rememberCoroutineScope()
    // The drawer opens with the theme's spatial spring: Expressive's bounce
    // carries it past the screen's edge and shows the page behind it (#41).
    // Standard (no bounce) for the drawer, Expressive again inside it.
    val motion = MaterialTheme.motionScheme
    MaterialTheme(motionScheme = MotionScheme.standard()) {
        ModalNavigationDrawer(
            drawerState = drawer,
            gesturesEnabled = enabled,
            drawerContent = {
                if (enabled) {
                    // Composed after the page, so Back closes the side bar before
                    // the page's own Back handlers run.
                    BackHandler(drawer.isOpen) { scope.launch { drawer.close() } }
                    MaterialTheme(motionScheme = motion) {
                        // A tab on the home shell switches in place, under the closing bar.
                        // Anything that opens another page waits for the bar to finish
                        // closing: those pages appear with no transition (#118), which
                        // would cut its slide short (#140).
                        SideBar(
                            selected, current, unread, open = drawer.targetValue == DrawerValue.Open,
                            onTab = { i ->
                                if (current == null) {
                                    scope.launch { drawer.close() }
                                    onTab(i)
                                } else {
                                    scope.launch { drawer.close(); onTab(i) }
                                }
                            },
                        ) { pick -> scope.launch { drawer.close(); pick() } }
                    }
                }
            },
        ) {
            MaterialTheme(motionScheme = motion) {
                CompositionLocalProvider(LocalSideBar provides if (enabled) ({ scope.launch { drawer.open() } }) else null, content = content)
            }
        }
    }
}

/** An entry's icon, in the side bar and in Settings › Side bar entries: outlined, like an unselected tab's. */
internal val SideBarItem.icon: ImageVector
    get() = when (this) {
        SideBarItem.SAVED -> Icons.Outlined.BookmarkBorder
        SideBarItem.CUSTOM_FEEDS -> Icons.Outlined.DynamicFeed
        SideBarItem.HISTORY -> Icons.Rounded.History
        SideBarItem.OFFLINE -> Icons.Outlined.OfflinePin
        SideBarItem.DRAFTS -> Icons.Outlined.EditNote
        SideBarItem.SETTINGS -> Icons.Outlined.Settings
        SideBarItem.RECENTLY_VISITED -> Icons.Outlined.Schedule
        SideBarItem.FAVORITES -> Icons.Outlined.StarBorder
    }

/** Its page open: filled, as the selected tab's is (#129). History has no filled form. */
internal val SideBarItem.selectedIcon: ImageVector
    get() = when (this) {
        SideBarItem.SAVED -> Icons.Rounded.Bookmark
        SideBarItem.CUSTOM_FEEDS -> Icons.Rounded.DynamicFeed
        SideBarItem.HISTORY -> Icons.Rounded.History
        SideBarItem.OFFLINE -> Icons.Rounded.OfflinePin
        SideBarItem.DRAFTS -> Icons.Rounded.EditNote
        SideBarItem.SETTINGS -> Icons.Rounded.Settings
        SideBarItem.RECENTLY_VISITED -> Icons.Rounded.Schedule
        SideBarItem.FAVORITES -> Icons.Rounded.Star
    }

/**
 * The side bar (Settings › Navigation): the four tabs, then your stuff,
 * Settings and subreddits, as Settings › Side bar entries orders them (#109).
 * [onTab] and [onPick] close it and run the choice.
 */
@Composable
private fun SideBar(selected: Int, current: Route?, unread: Int, open: Boolean, onTab: (Int) -> Unit, onPick: (() -> Unit) -> Unit) {
    val nav = LocalNavigator.current
    val cs = MaterialTheme.colorScheme
    val session by app.session.state.collectAsStateWithLifecycle()
    val s = (session as? SessionState.LoggedIn)?.session
    val anonymous = s?.anonymous != false
    val username = s?.username.takeUnless { anonymous }
    // Your avatar and karma: one request, the first time something shows them.
    val me by app.feed.me.collectAsStateWithLifecycle()
    LaunchedEffect(open) { if (open) app.feed.loadMe() }
    // The Explore tab's list, so these cost no requests of their own.
    val subs by viewModel { SubscriptionsViewModel() }.subs.collectAsStateWithLifecycle()
    val visited by app.recentSubreddits.state.collectAsStateWithLifecycle()
    val settings by app.settings.state.collectAsStateWithLifecycle()
    val list = (subs as? Async.Data)?.value ?: emptyList()
    val favorites = remember(list) { list.filter { it.userHasFavorited } }
    val recent = remember(visited) { visited.map { it.asSubreddit() } }
    ModalDrawerSheet(Modifier.width(300.dp)) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 12.dp)) {
            if (username == null) {
                Text("Ilay", Modifier.padding(start = 16.dp, top = 20.dp), style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.ExtraBold)
                Text(
                    "Browsing without an account",
                    Modifier.padding(start = 16.dp, top = 2.dp, bottom = 16.dp),
                    color = cs.onSurfaceVariant,
                )
            } else {
                // Your name and karma beside your picture, a size up (#167).
                Row(
                    Modifier
                        .padding(top = 8.dp, bottom = 8.dp)
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(28.dp))
                        .background(if (selected == 3) cs.secondaryContainer else Color.Transparent)
                        // Stands in for the Profile row (#64).
                        .clickable { onTab(3) }
                        .padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    LetterAvatar(username, 64.dp, cs.primaryContainer, cs.onPrimaryContainer, imageUrl = me?.iconUrl, fontSize = 26.sp)
                    Spacer(Modifier.width(14.dp))
                    Column(Modifier.weight(1f)) {
                        Text(
                            if (settings.sideBarUserPrefix) "u/$username" else username,
                            style = MaterialTheme.typography.titleLarge,
                            fontWeight = FontWeight.Bold,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                        me?.let {
                            Text(
                                "${compactNumber(it.linkKarma + it.commentKarma)} karma",
                                style = MaterialTheme.typography.bodyLarge,
                                color = cs.onSurfaceVariant,
                            )
                        }
                    }
                }
            }
            navItems.forEachIndexed { i, item ->
                if (i == 3 && username != null) return@forEachIndexed
                NavigationDrawerItem(
                    label = { Text(item.label) },
                    icon = { Icon(if (i == selected) item.on else item.off, null) },
                    badge = if (i == 2 && unread > 0) ({ Text(if (unread > 99) "99+" else "$unread") }) else null,
                    selected = i == selected,
                    onClick = { onTab(i) },
                )
            }
            HorizontalDivider(Modifier.padding(vertical = 12.dp, horizontal = 16.dp))
            var afterList = false // the last thing shown was a subreddit list
            for ((item, shown) in settings.sideBarItems) {
                if (!shown) continue
                when (item) {
                    // Its switch in Data & storage hides it on Explore too.
                    SideBarItem.RECENTLY_VISITED -> if (settings.showRecentlyVisited) {
                        SideBarSubs("Recently visited", recent, current, onPick, empty = "Subreddits you open will show here".takeIf { settings.trackHistory }, visits = visited.map { it.visits })
                        afterList = recent.isNotEmpty() || settings.trackHistory
                    }
                    SideBarItem.FAVORITES -> {
                        SideBarSubs("Favorites", favorites, current, onPick)
                        afterList = favorites.isNotEmpty()
                    }
                    else -> {
                        val route = when (item) {
                            SideBarItem.SAVED -> if (anonymous) continue else Route.Saved
                            SideBarItem.CUSTOM_FEEDS -> if (anonymous) continue else Route.CustomFeeds
                            SideBarItem.HISTORY -> Route.History
                            SideBarItem.OFFLINE -> Route.Offline
                            SideBarItem.DRAFTS -> Route.Drafts
                            else -> Route.Settings
                        }
                        // Moved below a subreddit list: set apart from it.
                        if (afterList) HorizontalDivider(Modifier.padding(vertical = 12.dp, horizontal = 16.dp))
                        afterList = false
                        NavigationDrawerItem(
                            label = { Text(item.label) },
                            icon = { Icon(if (route == current) item.selectedIcon else item.icon, null) },
                            selected = route == current,
                            onClick = { onPick { if (route != current) nav.openFromSideBar(route) } },
                        )
                    }
                }
            }
            Spacer(Modifier.height(16.dp))
        }
    }
}

/** A titled list of subreddits in the side bar (#63); when it has none, [empty], or nothing. */
@Composable
private fun SideBarSubs(title: String, subs: List<Subreddit>, current: Route?, onPick: (() -> Unit) -> Unit, empty: String? = null, visits: List<Int>? = null) {
    if (subs.isEmpty() && empty == null) return
    val nav = LocalNavigator.current
    val cs = MaterialTheme.colorScheme
    SectionHeader(title, Modifier.padding(start = 16.dp, top = 16.dp, bottom = 4.dp))
    if (subs.isEmpty()) {
        Text(empty.orEmpty(), Modifier.padding(start = 16.dp, top = 4.dp, end = 16.dp, bottom = 8.dp), color = cs.onSurfaceVariant)
    }
    for ((i, sub) in subs.withIndex()) {
        // A followed user is a subscription to their profile, u_<name>.
        val route = if (sub.name.startsWith("u_")) Route.User(sub.name.removePrefix("u_")) else Route.Subreddit(sub.name)
        NavigationDrawerItem(
            label = { Text(subredditName(sub.namePrefixed), maxLines = 1, overflow = TextOverflow.Ellipsis) },
            icon = { LetterAvatar(sub.name, 28.dp, cs.secondaryContainer, cs.onSecondaryContainer, imageUrl = sub.iconUrl, fontSize = 13.sp) },
            // Recently visited: how often you opened it (#92).
            badge = visits?.getOrNull(i)?.let { { Text("$it", color = cs.onSurfaceVariant, style = MaterialTheme.typography.labelMedium) } },
            selected = route == current,
            onClick = { onPick { if (route != current) nav.openFromSideBar(route) } },
        )
    }
}

/**
 * IndexedStack: every tab stays composed (state, scroll position, running
 * effects), but only the selected one is measured, placed and drawn.
 */
@Composable
private fun KeepAliveTabs(
    selected: Int,
    count: Int,
    composeAll: Boolean,
    modifier: Modifier = Modifier,
    content: @Composable (Int) -> Unit,
) {
    Layout(
        content = {
            for (i in 0 until count) {
                Box(Modifier.fillMaxSize()) { if (composeAll || i == selected) content(i) }
            }
        },
        modifier = modifier,
    ) { measurables, constraints ->
        val p = measurables[selected].measure(constraints)
        layout(p.width, p.height) { p.place(0, 0) }
    }
}

/**
 * Compact floating nav: a centred pill of icon buttons; the current tab
 * expands into a filled primary pill with its label (when labels are on).
 * Outlined and lifted so it reads apart from the posts behind it. Dragging
 * a finger along it moves the selection from tab to tab.
 */
@Composable
private fun FloatingNav(
    selected: Int,
    unread: Int,
    showLabels: Boolean,
    outline: Boolean,
    onSelected: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    val cs = MaterialTheme.colorScheme
    val dark = cs.surface.luminance() < 0.5f
    val shape = RoundedCornerShape(32.dp)
    val haptic = LocalHapticFeedback.current
    // Each tab's horizontal span in the row, for drag hit-testing.
    val spans = remember { arrayOfNulls<ClosedFloatingPointRange<Float>>(navItems.size) }
    val current by rememberUpdatedState(selected)
    val select by rememberUpdatedState(onSelected)
    Box(modifier.navigationBarsPadding().padding(bottom = 20.dp)) {
        Surface(
            Modifier
                .height(64.dp)
                .shadow(14.dp, shape, ambientColor = Color.Black.copy(alpha = 0.25f), spotColor = Color.Black.copy(alpha = 0.25f)),
            shape = shape,
            // Fully solid so it stays legible over images.
            color = if (dark) cs.surfaceContainerHigh else cs.surfaceContainer,
            border = if (outline) BorderStroke(1.dp, cs.outlineVariant) else null,
        ) {
            Row(
                Modifier
                    .pointerInput(Unit) {
                        // Only switch once the finger is inside another tab, so a
                        // tab growing under it can't bounce the selection back.
                        fun pick(x: Float) {
                            val i = spans.indexOfFirst { it != null && x in it }
                            if (i >= 0 && i != current) {
                                haptic.performHapticFeedback(HapticFeedbackType.SegmentTick)
                                select(i)
                            }
                        }
                        detectHorizontalDragGestures(
                            onDragStart = { pick(it.x) },
                            onHorizontalDrag = { change, _ -> pick(change.position.x) },
                        )
                    }
                    .padding(horizontal = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                navItems.forEachIndexed { i, item ->
                    NavButton(
                        item = item,
                        selected = selected == i,
                        badge = if (i == 2) unread else 0,
                        showLabel = showLabels,
                        onClick = { onSelected(i) },
                        modifier = Modifier.onPlaced { c ->
                            val x = c.positionInParent().x
                            spans[i] = x..(x + c.size.width)
                        },
                    )
                }
            }
        }
    }
}

@Composable
private fun NavButton(
    item: NavItem,
    selected: Boolean,
    badge: Int,
    showLabel: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val cs = MaterialTheme.colorScheme
    val contentColor by animateColorAsState(if (selected) cs.onPrimary else cs.onSurfaceVariant, tween(250), label = "navFg")
    val pillColor by animateColorAsState(if (selected) cs.primary else cs.primary.copy(alpha = 0f), tween(250), label = "navBg")
    Row(
        modifier
            .height(48.dp)
            .clip(CircleShape)
            .background(pillColor)
            // A tab, for screen readers: "Inbox, tab, selected".
            .selectable(selected = selected, role = Role.Tab, onClick = onClick)
            // The selected pill grows to fit its label with a little bounce.
            .animateContentSize(spring(dampingRatio = Spring.DampingRatioLowBouncy, stiffness = Spring.StiffnessMediumLow))
            .padding(horizontal = if (selected && showLabel) 18.dp else 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        val icon: @Composable () -> Unit = {
            Icon(if (selected) item.on else item.off, item.label, Modifier.size(24.dp), tint = contentColor)
        }
        if (badge > 0) {
            BadgedBox(badge = { Badge { Text(if (badge > 99) "99+" else "$badge") } }) { icon() }
        } else {
            icon()
        }
        if (selected && showLabel) {
            Spacer(Modifier.width(8.dp))
            Text(item.label, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = contentColor, maxLines = 1)
        }
    }
}

private suspend fun maybeCheckUpdates(context: android.content.Context) {
    if (!app.settings.value.checkUpdates) return
    val info = UpdateChecker.check() ?: return
    val download = Overlays.show<Boolean> { done ->
        AlertDialog(
            onDismissRequest = { done(null) },
            title = { Text("Update available — v${info.version}") },
            text = { Text("A newer version of Ilay is available on GitHub.") },
            dismissButton = { TextButton(onClick = { done(false) }) { Text("Later") } },
            confirmButton = { Button(onClick = { done(true) }) { Text("Download") } },
        )
    }
    if (download == true) {
        runCatching {
            context.startActivity(
                Intent(Intent.ACTION_VIEW, Uri.parse(info.apkUrl ?: info.url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        }
    }
}

/**
 * One-time, opt-in suggestion to enable inbox notifications (shown on an
 * early app open). Declining or enabling both mark it as handled so we never
 * nag again — it stays fully controllable in Settings either way.
 */
private suspend fun maybeSuggestNotifications() {
    val prefs = app.prefs
    if (prefs.getBool(NOTIF_PROMPTED_PREF) == true) return
    if (app.settings.value.notifyInbox) return
    prefs.setBool(NOTIF_PROMPTED_PREF, true)
    val enable = Overlays.show<Boolean> { done ->
        AlertDialog(
            onDismissRequest = { done(null) },
            icon = { Icon(Icons.Outlined.NotificationsActive, null) },
            title = { Text("Get notified of replies?") },
            text = {
                Text(
                    "Ilay can check your Reddit inbox in the background (about every 15 " +
                        "minutes) and notify you of replies, mentions and messages.\n\n" +
                        "It uses simple polling — no Firebase or tracking. You can change " +
                        "this anytime in Settings.",
                )
            },
            dismissButton = { TextButton(onClick = { done(false) }) { Text("Not now") } },
            confirmButton = { Button(onClick = { done(true) }) { Text("Enable") } },
        )
    }
    if (enable != true) return
    val granted = app.inbox.requestPermission()
    if (!granted) return
    app.settings.setNotifyInbox(true)
    app.inbox.pollInbox(false) // prime, don't notify for existing unread
    app.inbox.registerPolling()
}
