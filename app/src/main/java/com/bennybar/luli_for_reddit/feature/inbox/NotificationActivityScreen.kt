package com.bennybar.luli_for_reddit.feature.inbox

import android.content.Context
import android.content.Intent
import android.provider.Settings
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.NotificationsActive
import androidx.compose.material.icons.outlined.NotificationsOff
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.app.NotificationManagerCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.core.timeAgoPhrase
import com.bennybar.luli_for_reddit.feature.feed.BloomTopBar
import com.bennybar.luli_for_reddit.feature.feed.SectionHeader
import com.bennybar.luli_for_reddit.nav.LocalNavigator
import com.bennybar.luli_for_reddit.nav.Route
import kotlinx.coroutines.launch

/**
 * Settings → Notification activity: whether Ilay can notify you right now (and
 * what to fix if not), "Check now", and the last notifications it showed,
 * replaced or couldn't show — tap one to open it.
 */
@Composable
fun NotificationActivityScreen() {
    val cs = MaterialTheme.colorScheme
    val nav = LocalNavigator.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val events by app.notificationLog.events.collectAsStateWithLifecycle()
    val lastCheck by app.notificationLog.lastCheck.collectAsStateWithLifecycle()
    val settings by app.settings.state.collectAsStateWithLifecycle()
    // Permission / channel / listener state is the system's: re-read on return from its settings.
    var resumed by remember { mutableIntStateOf(0) }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { resumed++ }
    val nm = remember(resumed) { NotificationManagerCompat.from(context) }
    val canNotify = remember(resumed) { nm.areNotificationsEnabled() }
    val inboxChannel = remember(resumed) { InboxNotifications.canPost(nm, InboxNotifications.CHANNEL_ID) }
    val redditChannel = remember(resumed) { InboxNotifications.canPost(nm, RedditAppNotifications.CHANNEL_ID) }
    val redditAccess = remember(resumed) { RedditAppNotifications.hasAccess(context) }
    var checking by remember { mutableStateOf(false) }

    Scaffold(
        topBar = {
            BloomTopBar("Notification activity", actions = {
                if (events.isNotEmpty()) TextButton(onClick = { app.notificationLog.clear() }) { Text("Clear") }
            })
        },
        containerColor = cs.surface,
    ) { padding ->
        LazyColumn(
            Modifier.fillMaxSize().padding(top = padding.calculateTopPadding()),
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 130.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            item(key = "status") {
                Column(
                    Modifier.fillMaxWidth().background(cs.surfaceContainerLow, RoundedCornerShape(28.dp)).padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    StatusRow(
                        ok = canNotify,
                        text = if (canNotify) "Ilay can show notifications" else "Ilay's notifications are turned off",
                        fix = if (canNotify) null else "Allow" to { context.openNotificationSettings(null) },
                    )
                    StatusRow(
                        ok = settings.notifyInbox && inboxChannel,
                        text = when {
                            !settings.notifyInbox -> "Inbox notifications are off (Settings → Notifications)"
                            !inboxChannel -> "The \"Inbox\" notification category is blocked"
                            else -> "Checks your inbox about every 15 minutes"
                        },
                        fix = if (settings.notifyInbox && !inboxChannel) "Open" to { context.openNotificationSettings(InboxNotifications.CHANNEL_ID) } else null,
                    )
                    if (settings.redditAppNotifications) {
                        StatusRow(
                            ok = redditAccess && redditChannel,
                            text = when {
                                !redditAccess -> "Reddit app notifications need notification access"
                                !redditChannel -> "The \"Reddit app notifications\" category is blocked"
                                else -> "Reddit app notifications open in Ilay"
                            },
                            fix = when {
                                !redditAccess -> "Allow" to { context.startActivity(RedditAppNotifications.accessSettingsIntent(context)) }
                                !redditChannel -> "Open" to { context.openNotificationSettings(RedditAppNotifications.CHANNEL_ID) }
                                else -> null
                            },
                        )
                    }
                    Text(
                        lastCheck?.let { (at, result) -> "Last check ${timeAgoPhrase(at)}: $result" } ?: "No inbox check yet",
                        fontSize = 13.sp,
                        color = cs.onSurfaceVariant,
                    )
                    Button(
                        onClick = {
                            checking = true
                            scope.launch {
                                try {
                                    val shown = runCatching { app.inbox.pollInbox(notify = true) }.getOrNull()
                                    nav.showSnackbar(
                                        when {
                                            shown == null -> "Couldn't check the inbox"
                                            shown.isEmpty() -> "Checked: ${app.notificationLog.lastCheck.value?.second ?: "nothing new"}"
                                            else -> "${shown.size} new notification${if (shown.size == 1) "" else "s"}"
                                        },
                                    )
                                } finally {
                                    checking = false
                                }
                            }
                        },
                        enabled = !checking,
                    ) {
                        Icon(Icons.Rounded.Refresh, null, Modifier.size(18.dp))
                        Spacer(Modifier.width(8.dp))
                        Text(if (checking) "Checking…" else "Check now")
                    }
                }
            }
            item(key = "h") { SectionHeader("Recent", Modifier.padding(top = 8.dp, bottom = 2.dp)) }
            if (events.isEmpty()) {
                item(key = "empty") {
                    Text(
                        "Notifications Ilay shows, replaces or can't show will be listed here.",
                        Modifier.padding(vertical = 16.dp),
                        color = cs.onSurfaceVariant,
                    )
                }
            }
            items(events, key = { "${it.at}_${it.title.hashCode()}" }) { e -> EventRow(e) }
        }
    }
}

@Composable
private fun StatusRow(ok: Boolean, text: String, fix: Pair<String, () -> Unit>?) {
    val cs = MaterialTheme.colorScheme
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(
            if (ok) Icons.Rounded.CheckCircle else Icons.Outlined.ErrorOutline,
            null,
            Modifier.size(20.dp),
            tint = if (ok) cs.primary else cs.error,
        )
        Spacer(Modifier.width(10.dp))
        Text(text, Modifier.weight(1f), fontSize = 14.sp, color = cs.onSurface)
        fix?.let { (label, action) -> TextButton(onClick = action) { Text(label) } }
    }
}

@Composable
private fun EventRow(e: NotificationEvent) {
    val cs = MaterialTheme.colorScheme
    val nav = LocalNavigator.current
    val scope = rememberCoroutineScope()
    val icon: ImageVector = if (e.outcome.ok) Icons.Outlined.NotificationsActive else Icons.Outlined.NotificationsOff
    Row(
        Modifier
            .fillMaxWidth()
            .background(cs.surfaceContainerLow, RoundedCornerShape(18.dp))
            .padding(horizontal = 14.dp, vertical = 10.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Icon(icon, null, Modifier.padding(top = 2.dp).size(20.dp), tint = if (e.outcome.ok) cs.onSurfaceVariant else cs.error)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(e.title, fontWeight = FontWeight.SemiBold, fontSize = 14.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
            if (e.text.isNotEmpty()) {
                Text(e.text, fontSize = 13.sp, color = cs.onSurfaceVariant, maxLines = 2, overflow = TextOverflow.Ellipsis)
            }
            Spacer(Modifier.height(2.dp))
            Text(
                listOfNotNull(
                    e.account.takeIf { it.isNotEmpty() }?.let { "u/$it" },
                    timeAgoPhrase(e.at),
                    if (e.source == NotificationEvent.SOURCE_REDDIT) "from the Reddit app" else null,
                ).joinToString(" · ") + "\n" + e.outcome.label,
                fontSize = 12.sp,
                color = if (e.outcome.ok) cs.onSurfaceVariant else cs.error,
            )
        }
        TextButton(onClick = { scope.launch { open(e, nav) } }) { Text("Open") }
    }
}

/** Opens the event's reply / message; a Reddit-app one is found from its text, like tapping it. */
private suspend fun open(e: NotificationEvent, nav: com.bennybar.luli_for_reddit.nav.AppNavigator) {
    if (e.account.isNotEmpty() && !e.account.equals(app.session.username, ignoreCase = true)) {
        nav.showSnackbar("This was for u/${e.account}: switch to that account to open it")
        return
    }
    val route = when {
        e.subreddit != null && e.postId != null -> Route.Post(e.subreddit, e.postId, e.commentId)
        e.messageFullname != null -> Route.MessageThread(e.messageFullname)
        e.source == NotificationEvent.SOURCE_REDDIT -> runCatching { RedditAppNotifications.resolve(e.title, e.text) }.getOrNull()
        else -> null
    }
    if (route != null) nav.push(route) else nav.showSnackbar("Couldn't find it: try your Inbox")
}

/** The system screen for Ilay's notifications, or for one [channelId]. */
private fun Context.openNotificationSettings(channelId: String?) {
    val intent = if (channelId == null) {
        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
    } else {
        Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_CHANNEL_ID, channelId)
    }
    startActivity(intent.putExtra(Settings.EXTRA_APP_PACKAGE, packageName).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
}
