package com.bennybar.luli_for_reddit.feature.reminders

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Schedule
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import com.bennybar.luli_for_reddit.IlayActivity
import com.bennybar.luli_for_reddit.R
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.feature.feed.Tile
import com.bennybar.luli_for_reddit.feature.inbox.InboxNotifications
import com.bennybar.luli_for_reddit.model.Post
import com.bennybar.luli_for_reddit.ui.Overlays
import kotlinx.coroutines.launch
import java.util.concurrent.TimeUnit

/**
 * "Remind me about this post": offered (a snackbar action) when you save a
 * post, then a local notification at the time you pick. WorkManager runs it
 * on the phone, no push service (F-Droid safe); the time is approximate
 * (Android may run it a little late to save battery). Unsaving cancels it.
 */
object PostReminders {
    private const val CHANNEL_ID = "reminders"
    // Read back by InboxModule.handleLaunchIntent.
    const val TARGET = "reminder"

    private class Choice(val label: String, val hours: Long)

    private val choices = listOf(
        Choice("In 1 hour", 1),
        Choice("In 3 hours", 3),
        Choice("Tomorrow", 24),
        Choice("In 3 days", 72),
        Choice("In a week", 24 * 7),
    )

    /** Just saved [post]: a quiet "Remind me" next to "Saved". */
    fun offer(post: Post) {
        val nav = app.navigatorOrNull ?: return
        nav.showSnackbar("Saved", actionLabel = "Remind me") { app.scope.launch { pick(post) } }
    }

    @OptIn(ExperimentalMaterial3Api::class)
    private suspend fun pick(post: Post) {
        val choice = Overlays.show<Choice> { done ->
            ModalBottomSheet(onDismissRequest = { done(null) }) {
                Column(Modifier.navigationBarsPadding().padding(bottom = 8.dp)) {
                    Text(
                        "Remind me about this post",
                        Modifier.padding(start = 20.dp, top = 4.dp, end = 20.dp, bottom = 8.dp),
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Bold,
                    )
                    for (c in choices) {
                        Tile(
                            title = { Text(c.label) },
                            leading = { Icon(Icons.Rounded.Schedule, null) },
                            onClick = { done(c) },
                        )
                    }
                }
            }
        } ?: return
        // Reminders need notifications allowed.
        if (!app.inbox.requestPermission()) {
            app.navigatorOrNull?.showSnackbar("Allow Ilay's notifications to get reminders")
            return
        }
        schedule(post, TimeUnit.HOURS.toMillis(choice.hours))
        app.navigatorOrNull?.showSnackbar("I'll remind you ${choice.label.replaceFirstChar { it.lowercase() }}")
    }

    private fun schedule(post: Post, delayMillis: Long) {
        val request = OneTimeWorkRequestBuilder<PostReminderWorker>()
            .setInitialDelay(delayMillis, TimeUnit.MILLISECONDS)
            .setInputData(
                workDataOf(
                    "sub" to post.subreddit,
                    "post" to post.id,
                    "title" to post.title,
                ),
            )
            .build()
        WorkManager.getInstance(app.context).enqueueUniqueWork(workName(post.id), ExistingWorkPolicy.REPLACE, request)
    }

    /** Unsaved: drop its reminder, if any. */
    fun cancel(postId: String) {
        WorkManager.getInstance(app.context).cancelUniqueWork(workName(postId))
    }

    private fun workName(postId: String) = "reminder_$postId"

    internal fun show(context: Context, sub: String, postId: String, title: String) {
        val nm = NotificationManagerCompat.from(context)
        context.getSystemService(NotificationManager::class.java)?.let { m ->
            if (m.getNotificationChannel(CHANNEL_ID) == null) {
                m.createNotificationChannel(
                    NotificationChannel(CHANNEL_ID, "Post reminders", NotificationManager.IMPORTANCE_DEFAULT).apply {
                        description = "Posts you asked Ilay to remind you about."
                    },
                )
            }
        }
        if (!InboxNotifications.canPost(nm, CHANNEL_ID)) return
        val id = ("reminder_$postId").hashCode() and 0x7fffffff
        val intent = Intent(context, IlayActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(InboxNotifications.EXTRA_TARGET, TARGET)
            putExtra(InboxNotifications.EXTRA_SUBREDDIT, sub)
            putExtra(InboxNotifications.EXTRA_POST_ID, postId)
        }
        val tap = PendingIntent.getActivity(context, id, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val n = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_icon_mono)
            .setContentTitle("Reminder · r/$sub")
            .setContentText(title)
            .setStyle(NotificationCompat.BigTextStyle().bigText(title))
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setAutoCancel(true)
            .setContentIntent(tap)
            .build()
        try {
            nm.notify(id, n)
        } catch (_: SecurityException) { /* permission revoked meanwhile */ }
    }
}

class PostReminderWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val sub = inputData.getString("sub") ?: return Result.success()
        val post = inputData.getString("post") ?: return Result.success()
        PostReminders.show(applicationContext, sub, post, inputData.getString("title").orEmpty())
        return Result.success()
    }
}
