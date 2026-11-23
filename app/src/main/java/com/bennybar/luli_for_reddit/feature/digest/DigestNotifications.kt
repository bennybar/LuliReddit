package com.bennybar.luli_for_reddit.feature.digest

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.text.format.DateFormat
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.ui.platform.LocalContext
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.bennybar.luli_for_reddit.IlayActivity
import com.bennybar.luli_for_reddit.R
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.auth.SessionState
import com.bennybar.luli_for_reddit.feature.inbox.InboxNotifications
import com.bennybar.luli_for_reddit.ui.Overlays
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withTimeoutOrNull
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneId
import java.util.concurrent.TimeUnit

/**
 * The Digest's daily notification (Settings › Digest › Daily notification): at
 * `digestTime` a background job builds today's digest and posts one notification;
 * tapping it opens the Digest. One job at a time, each scheduling the next, so the
 * time stays exact (a 24-hour periodic job drifts).
 */
object DigestNotifications {
    const val TARGET = "digest" // InboxNotifications.EXTRA_TARGET value
    private const val CHANNEL_ID = "digest"
    private const val WORK = "digest_daily"
    private const val NOTIFICATION_ID = 0x0d16e57

    /** Schedules the next run at [minutes] after midnight, or cancels when the notification is off. */
    fun reschedule(context: Context) {
        val s = app.settings.value
        val wm = WorkManager.getInstance(context)
        if (!s.digestEnabled || !s.digestNotify) {
            wm.cancelUniqueWork(WORK)
            return
        }
        val request = OneTimeWorkRequestBuilder<DigestWorker>()
            .setInitialDelay(delayUntil(s.digestTime), TimeUnit.MILLISECONDS)
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .build()
        wm.enqueueUniqueWork(WORK, ExistingWorkPolicy.REPLACE, request)
    }

    /** Milliseconds until the next [minutes] after midnight (tomorrow's when today's has passed). */
    internal fun delayUntil(minutes: Int, now: LocalDateTime = LocalDateTime.now()): Long {
        var next = now.toLocalDate().atTime(LocalTime.of(minutes / 60, minutes % 60))
        if (!next.isAfter(now.plusSeconds(30))) next = next.plusDays(1)
        val zone = ZoneId.systemDefault()
        return next.atZone(zone).toInstant().toEpochMilli() - now.atZone(zone).toInstant().toEpochMilli()
    }

    /** "08:00" / "8:00 AM", as the phone shows times. */
    fun timeLabel(context: Context, minutes: Int): String {
        val t = LocalTime.of(minutes / 60, minutes % 60)
        val pattern = if (DateFormat.is24HourFormat(context)) "HH:mm" else "h:mm a"
        return t.format(java.time.format.DateTimeFormatter.ofPattern(pattern))
    }

    /** The time picker; null when cancelled. */
    @OptIn(ExperimentalMaterial3Api::class)
    suspend fun pickTime(current: Int): Int? = Overlays.show<Int> { done ->
        val state = rememberTimePickerState(current / 60, current % 60, DateFormat.is24HourFormat(LocalContext.current))
        AlertDialog(
            onDismissRequest = { done(null) },
            title = { Text("Digest time") },
            text = { TimePicker(state) },
            dismissButton = { TextButton(onClick = { done(null) }) { Text("Cancel") } },
            confirmButton = { Button(onClick = { done(state.hour * 60 + state.minute) }) { Text("Set") } },
        )
    }

    /** "Your digest: 9 posts from 5 communities"; nothing when the digest is empty or Ilay can't post. */
    internal fun show(context: Context, day: DigestDay) {
        val unread = day.items.filter { it.post.id !in app.history.ids.value }
        if (unread.isEmpty()) return
        val nm = NotificationManagerCompat.from(context)
        context.getSystemService(NotificationManager::class.java)?.let { m ->
            if (m.getNotificationChannel(CHANNEL_ID) == null) {
                m.createNotificationChannel(
                    NotificationChannel(CHANNEL_ID, "Digest", NotificationManager.IMPORTANCE_DEFAULT).apply {
                        description = "Your daily digest, at the time you set."
                    },
                )
            }
        }
        if (!InboxNotifications.canPost(nm, CHANNEL_ID)) return
        val communities = unread.map { it.post.subreddit.lowercase() }.distinct().size
        val title = "Your digest: ${unread.size} post${if (unread.size == 1) "" else "s"} from $communities communit${if (communities == 1) "y" else "ies"}"
        val text = unread.take(3).joinToString("\n") { it.post.title }
        val intent = Intent(context, IlayActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(InboxNotifications.EXTRA_TARGET, TARGET)
        }
        val tap = PendingIntent.getActivity(context, NOTIFICATION_ID, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val n = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_ilay)
            .setContentTitle(title)
            .setContentText(unread.first().post.title)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setAutoCancel(true)
            .setContentIntent(tap)
            .build()
        try {
            nm.notify(NOTIFICATION_ID, n)
        } catch (_: SecurityException) { /* permission revoked meanwhile */ }
    }
}

/** The daily run: build today's digest, notify, schedule tomorrow's. */
class DigestWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val s = app.settings.value
        if (!s.digestEnabled || !s.digestNotify) return Result.success()
        try {
            // A cold start in the background: the account loads first.
            withTimeoutOrNull(20_000) { app.session.state.first { it !is SessionState.Loading } }
            app.digest.refresh(manual = false)
            app.digest.store.today(app.digest.today())?.let { DigestNotifications.show(applicationContext, it) }
        } catch (_: Exception) {
            // Tomorrow's still comes.
        } finally {
            DigestNotifications.reschedule(applicationContext)
        }
        return Result.success()
    }
}
