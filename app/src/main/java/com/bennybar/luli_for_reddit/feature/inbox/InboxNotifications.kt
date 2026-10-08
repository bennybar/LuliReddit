package com.bennybar.luli_for_reddit.feature.inbox

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.bennybar.luli_for_reddit.IlayActivity
import com.bennybar.luli_for_reddit.R
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.core.storage.Prefs
import java.util.concurrent.TimeUnit

/**
 * Background polling of the Reddit inbox + local notifications.
 *
 * We can't use push (that would mean Firebase, which would disqualify the app
 * from F-Droid/IzzyOnDroid), so instead WorkManager wakes us roughly every 15
 * minutes, we fetch `/message/unread`, and fire a local notification for any
 * item we haven't already told the user about. Works for both auth modes
 * (OAuth and the website-session fallback) through the app's RedditClient.
 */
object InboxNotifications {
    // Same unique work name as the Flutter build.
    private const val TASK_UNIQUE = "luli.inbox.poll"

    /** Set once this build has replaced the Flutter plugin's periodic work. */
    private const val NATIVE_WORK_PREF = "inboxPollNative"

    // Same channel as the Flutter build, so the user's channel settings carry over.
    private const val CHANNEL_ID = "inbox"
    private const val CHANNEL_NAME = "Inbox replies & messages"
    private const val CHANNEL_DESC = "New replies, mentions and private messages on Reddit."

    // Notification-tap extras, read back by InboxModule.handleLaunchIntent.
    const val EXTRA_TARGET = "ilay.inbox.target"
    const val EXTRA_SUBREDDIT = "ilay.inbox.subreddit"
    const val EXTRA_POST_ID = "ilay.inbox.postId"
    const val EXTRA_COMMENT_ID = "ilay.inbox.commentId"
    const val EXTRA_MESSAGE = "ilay.inbox.message"
    const val TARGET_POST = "post"
    const val TARGET_MESSAGE = "message"
    const val TARGET_APP = "app"

    /** Pre-creates the channel so importance is right. Safe to call repeatedly. */
    fun createChannel(context: Context) {
        val nm = context.getSystemService(NotificationManager::class.java) ?: return
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_HIGH).apply {
                description = CHANNEL_DESC
            },
        )
    }

    internal fun show(context: Context, item: UnreadItem) {
        val nm = NotificationManagerCompat.from(context)
        if (!nm.areNotificationsEnabled()) return
        createChannel(context)
        val id = item.fullname.hashCode() and 0x7fffffff
        val intent = Intent(context, IlayActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            when {
                item.post != null -> {
                    putExtra(EXTRA_TARGET, TARGET_POST)
                    putExtra(EXTRA_SUBREDDIT, item.post.first)
                    putExtra(EXTRA_POST_ID, item.post.second)
                    putExtra(EXTRA_COMMENT_ID, item.post.third)
                }
                item.messageFullname != null -> {
                    putExtra(EXTRA_TARGET, TARGET_MESSAGE)
                    putExtra(EXTRA_MESSAGE, item.messageFullname)
                }
                else -> putExtra(EXTRA_TARGET, TARGET_APP)
            }
        }
        val tap = PendingIntent.getActivity(
            context,
            id,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_icon_mono)
            .setContentTitle(item.title)
            .setContentText(item.body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(item.body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setAutoCancel(true)
            .setContentIntent(tap)
            .build()
        try {
            nm.notify(id, notification)
        } catch (_: SecurityException) { /* permission revoked meanwhile */ }
    }

    /** Registers the ~15-minute periodic poll (network required). */
    fun registerPolling(context: Context, prefs: Prefs) {
        val request = PeriodicWorkRequestBuilder<InboxPollWorker>(15, TimeUnit.MINUTES)
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .build()
        // The Flutter build registered this unique work with its plugin's worker
        // class, which no longer exists: replace it once, then keep the schedule.
        val replaced = prefs.getBool(NATIVE_WORK_PREF) == true
        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            TASK_UNIQUE,
            if (replaced) ExistingPeriodicWorkPolicy.KEEP else ExistingPeriodicWorkPolicy.CANCEL_AND_REENQUEUE,
            request,
        )
        if (!replaced) prefs.setBool(NATIVE_WORK_PREF, true)
    }

    fun cancelPolling(context: Context) {
        WorkManager.getInstance(context).cancelUniqueWork(TASK_UNIQUE)
    }
}

/** The WorkManager entry point: one poll per run. */
class InboxPollWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        // Turned off but the work survived (e.g. restored backup): stop polling.
        if (app.prefs.getBool(InboxModule.NOTIFY_INBOX_PREF) != true) {
            InboxNotifications.cancelPolling(applicationContext)
            return Result.success()
        }
        try {
            app.inbox.pollInbox(notify = true)
        } catch (_: Exception) {
            // Success anyway avoids WorkManager backoff storms; we retry next tick.
        }
        return Result.success()
    }
}
