package com.bennybar.luli_for_reddit.feature.home

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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.core.UpdateChecker
import com.bennybar.luli_for_reddit.feature.inbox.InboxScreen
import com.bennybar.luli_for_reddit.nav.LocalNavigator
import com.bennybar.luli_for_reddit.ui.Overlays

/** Prefs flag: have we shown the one-time notifications suggestion? */
private const val NOTIF_PROMPTED_PREF = "notifyInboxPrompted"

private class NavItem(val off: ImageVector, val on: ImageVector, val label: String)

private val navItems = listOf(
    NavItem(Icons.Outlined.Home, Icons.Rounded.Home, "Posts"),
    NavItem(Icons.Outlined.Explore, Icons.Rounded.Explore, "Explore"),
    NavItem(Icons.Rounded.MailOutline, Icons.Rounded.Mail, "Inbox"),
    NavItem(Icons.Outlined.AccountCircle, Icons.Rounded.AccountCircle, "Account"),
)

/** The home shell: Posts / Explore / Inbox / Account tabs with the floating "Pop" pill nav. */
@Composable
fun HomeScreen() {
    val nav = LocalNavigator.current
    val context = LocalContext.current
    var index by rememberSaveable { mutableIntStateOf(0) }
    var chrome by rememberSaveable { mutableStateOf(true) }
    val unread by app.inbox.unreadCount.collectAsStateWithLifecycle()
    val settings by app.settings.state.collectAsStateWithLifecycle()
    val inboxReselect by app.feed.tabReselect(2).collectAsStateWithLifecycle()

    // Once per app start: GitHub update check, then the one-time
    // notifications suggestion.
    LaunchedEffect(Unit) {
        if (app.feed.startupChecksDone) return@LaunchedEffect
        app.feed.startupChecksDone = true
        maybeCheckUpdates(context)
        maybeSuggestNotifications()
    }

    // Snackbars float above the floating nav while the shell is showing.
    DisposableEffect(nav) {
        nav.snackbarBottomPadding = 86.dp
        onDispose { nav.snackbarBottomPadding = 0.dp }
    }

    // Hide the nav (and the Full top bar) while scrolling down, reveal on
    // scrolling up or reaching the top — any tab's main list.
    val scrollConnection = remember {
        object : NestedScrollConnection {
            override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
                if (source == NestedScrollSource.UserInput) {
                    if (available.y < -1f && chrome) chrome = false
                    else if (available.y > 1f && !chrome) chrome = true
                }
                return Offset.Zero
            }

            override fun onPostScroll(consumed: Offset, available: Offset, source: NestedScrollSource): Offset {
                // Overscrolling at the top: keep the chrome shown.
                if (available.y > 0f && !chrome) chrome = true
                return Offset.Zero
            }
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

    Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surface)) {
        KeepAliveTabs(
            selected = index,
            count = 4,
            composeAll = allTabs,
            modifier = Modifier.fillMaxSize().statusBarsPadding().nestedScroll(scrollConnection),
        ) { i ->
            when (i) {
                0 -> FrontpageTab(chromeVisible = chrome)
                1 -> ExploreTab()
                2 -> InboxScreen(reselect = inboxReselect)
                else -> AccountTab()
            }
        }
        FloatingNav(
            selected = index,
            unread = unread,
            showLabels = settings.navLabels,
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .graphicsLayer { translationY = size.height * navOffset },
            onSelected = { i ->
                // Re-tapping the active tab scrolls it to top (Posts also refreshes).
                if (i == index) {
                    if (i == 0) app.feed.frontpageScrollSignal.value++ else app.feed.tabReselect(i).value++
                } else {
                    index = i
                    chrome = true // always reveal chrome when switching tabs
                }
            },
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

/** "Pop" floating pill navigation (Android: Material pills under the icons). */
@Composable
private fun FloatingNav(
    selected: Int,
    unread: Int,
    showLabels: Boolean,
    onSelected: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    val shape = RoundedCornerShape(40.dp)
    Box(modifier.navigationBarsPadding().padding(start = 18.dp, end = 18.dp, bottom = 16.dp)) {
        Surface(
            Modifier
                .fillMaxWidth()
                .height(70.dp)
                .shadow(16.dp, shape, ambientColor = Color.Black.copy(alpha = 0.22f), spotColor = Color.Black.copy(alpha = 0.22f)),
            shape = shape,
            // Nav sits over scrolling content (incl. dark images): fully solid
            // so labels are always legible.
            color = MaterialTheme.colorScheme.surfaceContainerHigh,
        ) {
            Row(Modifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically) {
                navItems.forEachIndexed { i, item ->
                    NavButton(
                        item = item,
                        selected = selected == i,
                        badge = if (i == 2) unread else 0,
                        showLabel = showLabels,
                        onClick = { onSelected(i) },
                        modifier = Modifier.weight(1f),
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
    val contentColor by animateColorAsState(if (selected) cs.onSecondaryContainer else cs.onSurfaceVariant, tween(300), label = "navFg")
    val pillColor by animateColorAsState(if (selected) cs.secondaryContainer else cs.secondaryContainer.copy(alpha = 0f), tween(300), label = "navBg")
    // The pill grows out from the icon with a little overshoot (easeOutBack).
    val pillWidth by animateDpAsState(
        if (selected) 56.dp else 32.dp,
        spring(dampingRatio = Spring.DampingRatioMediumBouncy, stiffness = Spring.StiffnessMediumLow),
        label = "navPill",
    )
    Column(
        modifier.fillMaxHeight().clip(CircleShape).clickable(onClick = onClick),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            Modifier.width(56.dp).height(30.dp),
            contentAlignment = Alignment.Center,
        ) {
            Box(Modifier.width(pillWidth).height(30.dp).background(pillColor, CircleShape))
            val icon: @Composable () -> Unit = {
                Icon(
                    if (selected) item.on else item.off,
                    item.label,
                    Modifier.size(if (showLabel) 24.dp else 28.dp),
                    tint = contentColor,
                )
            }
            if (badge > 0) {
                BadgedBox(badge = { Badge { Text(if (badge > 99) "99+" else "$badge") } }) { icon() }
            } else {
                icon()
            }
        }
        if (showLabel) {
            Spacer(Modifier.height(4.dp))
            Text(item.label, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = contentColor)
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
