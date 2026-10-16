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
import kotlinx.coroutines.delay

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
        val redditData = RedditAppNotifications.describe(extras)
        app.scope.launch {
            val account = app.session.username
            fun log(outcome: NotificationEvent.Outcome, r: RedditAppNotifications.Resolution? = null) {
                val route = r?.route
                app.notificationLog.add(
                    NotificationEvent(
                        System.currentTimeMillis(), account, NotificationEvent.SOURCE_REDDIT, title, text, outcome,
                        subreddit = (route as? Route.Post)?.subreddit, postId = (route as? Route.Post)?.postId,
                        commentId = (route as? Route.Post)?.focusCommentId, messageFullname = (route as? Route.MessageThread)?.fullname,
                        how = r?.how, redditData = redditData,
                    ),
                )
            }
            // Ilay can't post notifications (permission off): keep Reddit's own.
            if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return@launch log(NotificationEvent.Outcome.KEPT)
            val inbox = RedditAppNotifications.isInbox(title)
            // A reply / message: Ilay's own notification knows exactly where it goes,
            // but only if it's this one (not another fresh item, another account's…).
            suspend fun ilayShowedIt(): Boolean {
                if (!inbox || !app.settings.value.notifyInbox) return false
                val shown = runCatching { app.inbox.pollInbox(notify = true) }.getOrNull().orEmpty()
                // Exactly one of them, by text and author: two "Thank you!" replies
                // can't be told apart, so then Reddit's is copied instead.
                return shown.count { RedditAppNotifications.sameItem(it.title, it.body, title, text) } == 1
            }
            if (ilayShowedIt()) {
                log(NotificationEvent.Outcome.REPLACED)
                runCatching { cancelNotification(key) }
                return@launch
            }
            if (!RedditAppNotifications.mirror(context, key, title, text, picture, n.contentIntent)) {
                return@launch log(NotificationEvent.Outcome.KEPT)
            }
            runCatching { cancelNotification(key) }
            // Work out where it goes now, while it's fresh, so the tap opens that
            // exact post / comment instead of guessing later. Reddit's inbox often
            // lags its notification: a reply not there yet is looked for again.
            var r = runCatching { RedditAppNotifications.resolve(title, text) }.getOrNull()
            if (inbox && r?.exact != true) {
                for (wait in listOf(15_000L, 45_000L)) {
                    delay(wait)
                    if (ilayShowedIt()) { // Ilay's own (exact) notification is up: drop the copy
                        RedditAppNotifications.cancelCopy(context, key)
                        return@launch log(NotificationEvent.Outcome.REPLACED)
                    }
                    r = runCatching { RedditAppNotifications.resolve(title, text) }.getOrNull()
                    if (r?.exact == true) break
                }
            }
            if (r?.exact == true) RedditAppNotifications.mirror(context, key, title, text, picture, n.contentIntent, r.route)
            log(NotificationEvent.Outcome.COPIED, r)
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

    /**
     * Copies a Reddit notification into Ilay's; false if it couldn't be posted.
     * With [route] (found once it arrived) the tap opens exactly that; posting
     * again with it updates the copy quietly.
     */
    fun mirror(context: Context, key: String, title: String, text: String, picture: Bitmap?, original: PendingIntent?, route: Route? = null): Boolean {
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
                .apply {
                    when (route) {
                        is Route.Post -> {
                            putExtra(InboxNotifications.EXTRA_TARGET, InboxNotifications.TARGET_POST)
                            putExtra(InboxNotifications.EXTRA_SUBREDDIT, route.subreddit)
                            putExtra(InboxNotifications.EXTRA_POST_ID, route.postId)
                            putExtra(InboxNotifications.EXTRA_COMMENT_ID, route.focusCommentId)
                        }
                        is Route.MessageThread -> {
                            putExtra(InboxNotifications.EXTRA_TARGET, InboxNotifications.TARGET_MESSAGE)
                            putExtra(InboxNotifications.EXTRA_MESSAGE, route.fullname)
                        }
                        else -> putExtra(InboxNotifications.EXTRA_TARGET, TARGET).putExtra(EXTRA_TITLE, title).putExtra(EXTRA_TEXT, text)
                    }
                },
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val b = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_icon_mono)
            .setContentTitle(title)
            .setContentText(text)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setOnlyAlertOnce(true) // updated with its exact destination: no second buzz
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

    /**
     * Which of your [posts] a "your post" notification is about: the one whose
     * title appears in the notification (in its subreddit, when it names one),
     * the longest if several do — a short title can be part of a longer one.
     */
    internal fun pickOwnPost(posts: List<com.bennybar.luli_for_reddit.model.Post>, title: String, text: String): com.bennybar.luli_for_reddit.model.Post? {
        val sub = Regex("""\br/([A-Za-z0-9_]{2,21})""").find("$title $text")?.groupValues?.get(1)
        val both = norm("$title $text")
        return posts
            .filter { (sub == null || it.subreddit.equals(sub, ignoreCase = true)) && norm(it.title).length >= 6 && both.contains(norm(it.title)) }
            .maxByOrNull { norm(it.title).length }
    }

    /** Removes the copy of Reddit's notification [key] (Ilay's own replaced it). */
    fun cancelCopy(context: Context, key: String) = NotificationManagerCompat.from(context).cancel(key.hashCode() and 0x7fffffff)

    /**
     * The extra fields a Reddit notification carries — their names, and any
     * value that looks like a link or Reddit id — for Notification activity:
     * if Reddit ever sends an exact link, it shows up here.
     */
    fun describe(extras: android.os.Bundle): String? = runCatching {
        val keys = extras.keySet().sorted()
        val links = keys.mapNotNull { k ->
            @Suppress("DEPRECATION")
            val v = extras.get(k)?.toString() ?: return@mapNotNull null
            if (Regex("""https?://|reddit\.com|\bt[13]_[a-z0-9]+""").containsMatchIn(v)) "$k=${v.take(160)}" else null
        }
        (listOf(keys.joinToString(", ")) + links).joinToString("; ")
    }.getOrNull()

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

    /** Where a copied notification goes, and how that was found (shown in Notification activity). */
    class Resolution(val route: Route?, val how: String) {
        /** An exact post / comment / conversation, not a guess like a whole subreddit. */
        val exact: Boolean get() = route is Route.Post || route is Route.MessageThread
    }

    private val OWN = Regex("""\byour (post|comment)\b""", RegexOption.IGNORE_CASE)
    private val POST_ID = Regex("""/comments/([a-z0-9]+)/""")

    /**
     * Where a copied Reddit notification should go, from its text (Reddit's
     * notification carries no link Ilay can read):
     *  - about your own post or comment ("10 upvotes on your post"): found in
     *    your submitted posts / comments, by its title / text;
     *  - a reply / mention / message: the one inbox item with that text (and
     *    author) — never a post search, which found unrelated posts;
     *  - a recommended post ("Trending in r/x"): a post in r/x with exactly
     *    that title; else r/x itself.
     */
    suspend fun resolve(title: String, text: String): Resolution {
        val sub = Regex("""\br/([A-Za-z0-9_]{2,21})""").find("$title $text")?.groupValues?.get(1)
        val me = app.session.username
        val own = OWN.find("$title $text")?.groupValues?.get(1)?.lowercase()
        if (own != null && me.isNotEmpty()) {
            if (own == "post") {
                pickOwnPost(app.repository.getUserPosts(me, "submitted", limit = 100).items, title, text)
                    ?.let { return Resolution(Route.Post(it.subreddit, it.id), "your post, by its title") }
            } else {
                val hit = app.repository.getUserComments(me).items
                    .filter { (sub == null || it.subreddit.equals(sub, ignoreCase = true)) && (sameText(it.body, text) || sameText(it.body, title)) }
                    .singleOrNull()
                val postId = hit?.permalink?.let { POST_ID.find(it)?.groupValues?.get(1) }
                if (hit != null && postId != null) return Resolution(Route.Post(hit.subreddit, postId, hit.id), "your comment, by its text")
            }
            return Resolution(Route.User(me), "your ${own}: not found among your latest, opening your profile")
        }
        if (isInbox(title)) {
            val wanted = norm(text).take(60)
            if (wanted.length >= 8) {
                val json = app.client.get("/message/inbox", mapOf("limit" to 50))
                val who = author(title)
                // The one item with this text (and author, when Reddit names one).
                val hit = json["data"]["children"].arr().orEmpty().map { it["data"] }
                    .filter { norm(it["body"].str()).startsWith(wanted) && (who == null || it["author"].str().equals(who, ignoreCase = true)) }
                    .singleOrNull()
                val item = InboxModule.parseUnread(hit)
                item?.post?.let { (s, post, comment) -> return Resolution(Route.Post(s, post, comment), "inbox reply, by its text") }
                item?.messageFullname?.let { return Resolution(Route.MessageThread(it), "inbox message, by its text") }
            }
            return Resolution(null, "reply not found in your inbox yet")
        }
        if (sub == null) return Resolution(null, "no subreddit or post named")
        // A recommended post ("Trending in r/x" + its title): only a post with
        // exactly that title; a looser match opened unrelated posts.
        val q = listOf(text, title).map { it.replace(Regex("""\br/\w+"""), "").trim() }.firstOrNull { norm(it).length >= 8 }
        if (q != null) {
            val posts = runCatching { app.repository.searchPosts(q.take(200), sub, sort = "relevance", time = "month").items }.getOrNull().orEmpty()
            posts.firstOrNull { norm(it.title) == norm(q) }?.let { return Resolution(Route.Post(it.subreddit, it.id), "post in r/$sub, by its exact title") }
        }
        return Resolution(Route.Subreddit(sub), "post not found, opening r/$sub")
    }
}
