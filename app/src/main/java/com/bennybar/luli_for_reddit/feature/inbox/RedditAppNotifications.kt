package com.bennybar.luli_for_reddit.feature.inbox

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.drawable.Icon
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.graphics.drawable.toBitmap
import com.bennybar.luli_for_reddit.IlayActivity
import com.bennybar.luli_for_reddit.R
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.core.arr
import com.bennybar.luli_for_reddit.core.get
import com.bennybar.luli_for_reddit.core.str
import com.bennybar.luli_for_reddit.nav.Route
import kotlinx.coroutines.launch

/**
 * Takes over the official Reddit app's notifications, so they open in Ilay
 * (opt-in: Settings → Notifications, plus Android's notification access).
 *
 * Replies, mentions and messages: Ilay checks its inbox at once and posts its
 * own notification, which opens the exact comment (when Ilay's inbox
 * notifications are on). Everything else — or a reply Ilay couldn't find — is
 * copied into an Ilay notification with the same text and picture; tapping it
 * works out the post / subreddit from that text, and "Open in Reddit" fires
 * the original. Either way Reddit's own notification is removed.
 */
class RedditNotificationListener : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (sbn.packageName != RedditAppNotifications.REDDIT_PACKAGE || !app.settings.value.redditAppNotifications) return
        val n = sbn.notification
        val key = sbn.key
        // The bundle header Reddit posts above its notifications.
        if (n.flags and Notification.FLAG_GROUP_SUMMARY != 0) {
            runCatching { cancelNotification(key) }
            return
        }
        val extras = n.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty().trim()
        val text = (extras.getCharSequence(Notification.EXTRA_BIG_TEXT) ?: extras.getCharSequence(Notification.EXTRA_TEXT))
            ?.toString().orEmpty().trim()
        if (title.isEmpty() && text.isEmpty()) return
        val picture = extras.getParcelable(Notification.EXTRA_PICTURE, Bitmap::class.java)
            ?: extras.getParcelable(Notification.EXTRA_PICTURE_ICON, Icon::class.java)
                ?.let { runCatching { it.loadDrawable(this)?.toBitmap() }.getOrNull() }
        val context = applicationContext
        app.scope.launch {
            fun log(outcome: NotificationEvent.Outcome) = app.notificationLog.add(
                NotificationEvent(System.currentTimeMillis(), app.session.username, NotificationEvent.SOURCE_REDDIT, title, text, outcome),
            )
            // Ilay can't post notifications (permission off): keep Reddit's own.
            if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return@launch log(NotificationEvent.Outcome.KEPT)
            // A reply / message: Ilay's own notification knows exactly where it goes,
            // but only if it's this one (not another fresh item, another account's…).
            val shown = if (RedditAppNotifications.isInbox(title) && app.settings.value.notifyInbox) {
                runCatching { app.inbox.pollInbox(notify = true) }.getOrNull().orEmpty()
            } else emptyList()
            // Exactly one of them, by text and author: two "Thank you!" replies
            // can't be told apart, so then Reddit's is copied instead.
            val handled = shown.count { RedditAppNotifications.sameItem(it.title, it.body, title, text) } == 1
            if (!handled && !RedditAppNotifications.mirror(context, key, title, text, picture, n.contentIntent)) {
                return@launch log(NotificationEvent.Outcome.KEPT)
            }
            log(if (handled) NotificationEvent.Outcome.REPLACED else NotificationEvent.Outcome.COPIED)
            runCatching { cancelNotification(key) }
        }
    }
}

internal object RedditAppNotifications {
    const val REDDIT_PACKAGE = "com.reddit.frontpage"
    const val TARGET = "redditApp"
    const val EXTRA_TITLE = "ilay.redditApp.title"
    const val EXTRA_TEXT = "ilay.redditApp.text"
    const val CHANNEL_ID = "reddit_app"

    private val INBOX = Regex("replied to your|replied to you|mentioned you|sent you|new message|commented on your", RegexOption.IGNORE_CASE)

    /** "u/x replied to your comment in r/y", "u/x sent you a message"… */
    fun isInbox(title: String) = INBOX.containsMatchIn(title)

    /** Whether Ilay may read notifications (the user granted it in Android's settings). */
    fun hasAccess(context: Context) = context.packageName in NotificationManagerCompat.getEnabledListenerPackages(context)

    /** Android's notification-access screen, on Ilay's entry. */
    fun accessSettingsIntent(context: Context): Intent =
        Intent(android.provider.Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS)
            .putExtra(
                android.provider.Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME,
                ComponentName(context, RedditNotificationListener::class.java).flattenToString(),
            )
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

    /** Copies a Reddit notification into Ilay's; false if it couldn't be posted. */
    fun mirror(context: Context, key: String, title: String, text: String, picture: Bitmap?, original: PendingIntent?): Boolean {
        val nm = NotificationManagerCompat.from(context)
        if (!nm.areNotificationsEnabled()) return false
        context.getSystemService(NotificationManager::class.java)?.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Reddit app notifications", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "The Reddit app's notifications, opened in Ilay."
            },
        )
        // This channel turned off by the user: Reddit's own notification stays.
        if (!InboxNotifications.canPost(nm, CHANNEL_ID)) return false
        val id = key.hashCode() and 0x7fffffff
        val tap = PendingIntent.getActivity(
            context,
            id,
            Intent(context, IlayActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                .putExtra(InboxNotifications.EXTRA_TARGET, TARGET)
                .putExtra(EXTRA_TITLE, title)
                .putExtra(EXTRA_TEXT, text),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val b = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_icon_mono)
            .setContentTitle(title)
            .setContentText(text)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(tap)
        if (picture != null) {
            b.setLargeIcon(picture).setStyle(NotificationCompat.BigPictureStyle().bigPicture(picture).setSummaryText(text))
        } else {
            b.setStyle(NotificationCompat.BigTextStyle().bigText(text))
        }
        if (original != null) b.addAction(0, "Open in Reddit", original)
        return try {
            nm.notify(id, b.build())
            true
        } catch (_: SecurityException) { false /* permission revoked meanwhile */ }
    }

    private fun norm(s: String?) = s.orEmpty().lowercase().filter { it.isLetterOrDigit() }

    /** Whether an inbox item's [body] is the text Reddit's notification shows (Reddit cuts it short). */
    fun sameText(body: String, text: String): Boolean {
        val a = norm(body)
        val b = norm(text).take(60)
        return b.length >= 8 && a.startsWith(b)
    }

    private val AUTHOR = Regex("""\bu/([A-Za-z0-9_-]{3,20})""")

    /** The u/name a Reddit notification title starts with ("u/x and 1 other replied…"), if any. */
    fun author(title: String): String? = AUTHOR.find(title)?.groupValues?.get(1)

    /**
     * Whether an inbox item (Ilay's [itemTitle] "u/x replied…" and [itemBody])
     * is the one Reddit notified about: the same text and, when Reddit names
     * one, the same author.
     */
    fun sameItem(itemTitle: String, itemBody: String, redditTitle: String, redditText: String): Boolean {
        if (!sameText(itemBody, redditText)) return false
        val who = author(redditTitle) ?: return true
        return author(itemTitle).equals(who, ignoreCase = true)
    }

    /**
     * Where a copied Reddit notification should go: a reply / message found in
     * the inbox by its text; a post found in its subreddit by title; else the
     * subreddit it names; else null (just open the app).
     */
    suspend fun resolve(title: String, text: String): Route? {
        val sub = Regex("""\br/([A-Za-z0-9_]{2,21})""").find("$title $text")?.groupValues?.get(1)
        if (isInbox(title)) {
            val wanted = norm(text).take(60)
            if (wanted.length >= 8) {
                val json = app.client.get("/message/inbox", mapOf("limit" to 50))
                val who = author(title)
                // The one item with this text (and author, when Reddit names one);
                // none or several: fall back to the subreddit below.
                val hit = json["data"]["children"].arr().orEmpty().map { it["data"] }
                    .filter { norm(it["body"].str()).startsWith(wanted) && (who == null || it["author"].str().equals(who, ignoreCase = true)) }
                    .singleOrNull()
                val item = InboxModule.parseUnread(hit)
                item?.post?.let { (s, post, comment) -> return Route.Post(s, post, comment) }
                item?.messageFullname?.let { return Route.MessageThread(it) }
            }
        }
        if (sub == null) return null
        // A post notification ("Trending in r/x" + its title): find it by title.
        val q = listOf(text, title).map { it.replace(Regex("""\br/\w+"""), "").trim() }.firstOrNull { norm(it).length >= 8 }
        if (q != null) {
            val posts = runCatching { app.repository.searchPosts(q.take(200), sub, sort = "relevance", time = "month").items }.getOrNull().orEmpty()
            posts.firstOrNull { norm(it.title) == norm(q) || (norm(it.title).length >= 12 && norm(q).contains(norm(it.title))) }
                ?.let { return Route.Post(it.subreddit, it.id) }
        }
        return Route.Subreddit(sub)
    }
}
