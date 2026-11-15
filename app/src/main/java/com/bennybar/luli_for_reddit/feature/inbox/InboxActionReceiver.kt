package com.bennybar.luli_for_reddit.feature.inbox

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.RemoteInput
import com.bennybar.luli_for_reddit.R
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.ui.friendlyError
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * An inbox notification's buttons (#178): Mark as read, and Reply typed into the
 * notification itself. Both act for the account the notification is for; after an
 * account switch they say so instead of acting as the other one. Done, the
 * notification goes; failed, it says what went wrong (and keeps a reply's text).
 */
class InboxActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val fullname = intent.getStringExtra(EXTRA_FULLNAME) ?: return
        val account = intent.getStringExtra(EXTRA_ACCOUNT).orEmpty()
        val id = intent.getIntExtra(EXTRA_NOTIFICATION_ID, InboxNotifications.notificationId(fullname))
        val open = intent.getParcelableExtra(EXTRA_OPEN, Intent::class.java)
        val reply = if (intent.action == ACTION_REPLY) {
            RemoteInput.getResultsFromIntent(intent)?.getCharSequence(KEY_REPLY)?.toString()?.trim().orEmpty()
        } else null
        val done = goAsync()
        scope.launch {
            try {
                if (runCatching { app.secureStore.username() }.getOrNull().orEmpty() != account) {
                    throw IllegalStateException("Switch to u/$account in Ilay first")
                }
                if (reply != null) {
                    if (reply.isEmpty()) throw IllegalStateException("The reply was empty")
                    // A comment reply, or a reply in a private message's conversation: same call.
                    app.repository.sendReply(fullname, reply)
                }
                app.repository.markRead(fullname)
                NotificationManagerCompat.from(context).cancel(id)
            } catch (e: Exception) {
                failed(context, id, open, if (reply != null) "Couldn't send your reply" else "Couldn't mark it as read", e, reply)
            } finally {
                done.finish()
            }
        }
    }

    /** Puts the failure where the notification was; tapping it opens the item. */
    private fun failed(context: Context, id: Int, open: Intent?, title: String, e: Exception, reply: String?) {
        val why = e.message?.takeIf { e is IllegalStateException } ?: friendlyError(e)
        val text = if (reply.isNullOrEmpty()) why else "$why. Your reply: $reply"
        val b = NotificationCompat.Builder(context, InboxNotifications.CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_ilay)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setOnlyAlertOnce(true)
            .setAutoCancel(true)
        if (open != null) {
            b.setContentIntent(PendingIntent.getActivity(context, id, open, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT))
        }
        try {
            NotificationManagerCompat.from(context).notify(id, b.build())
        } catch (_: SecurityException) { /* permission revoked meanwhile */ }
    }

    companion object {
        private const val ACTION_MARK_READ = "ilay.inbox.MARK_READ"
        private const val ACTION_REPLY = "ilay.inbox.REPLY"
        private const val EXTRA_FULLNAME = "ilay.inbox.action.fullname"
        private const val EXTRA_ACCOUNT = "ilay.inbox.action.account"
        private const val EXTRA_NOTIFICATION_ID = "ilay.inbox.action.notificationId"
        private const val EXTRA_OPEN = "ilay.inbox.action.open"
        private const val KEY_REPLY = "ilay.inbox.reply"

        private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

        private fun intent(context: Context, action: String, fullname: String, account: String, id: Int) =
            Intent(context, InboxActionReceiver::class.java).setAction(action)
                .putExtra(EXTRA_FULLNAME, fullname)
                .putExtra(EXTRA_ACCOUNT, account)
                .putExtra(EXTRA_NOTIFICATION_ID, id)

        fun markReadAction(context: Context, fullname: String, account: String, id: Int): NotificationCompat.Action {
            val pi = PendingIntent.getBroadcast(
                context, id * 2, intent(context, ACTION_MARK_READ, fullname, account, id),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            return NotificationCompat.Action.Builder(0, "Mark as read", pi)
                .setSemanticAction(NotificationCompat.Action.SEMANTIC_ACTION_MARK_AS_READ)
                .setShowsUserInterface(false)
                .build()
        }

        fun replyAction(context: Context, fullname: String, account: String, id: Int, open: Intent): NotificationCompat.Action {
            // Mutable: the system adds the typed text to it.
            val pi = PendingIntent.getBroadcast(
                context, id * 2 + 1, intent(context, ACTION_REPLY, fullname, account, id).putExtra(EXTRA_OPEN, open),
                PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            return NotificationCompat.Action.Builder(0, "Reply", pi)
                .addRemoteInput(RemoteInput.Builder(KEY_REPLY).setLabel("Reply").build())
                .setSemanticAction(NotificationCompat.Action.SEMANTIC_ACTION_REPLY)
                .setAllowGeneratedReplies(false)
                .setShowsUserInterface(false)
                .build()
        }
    }
}
