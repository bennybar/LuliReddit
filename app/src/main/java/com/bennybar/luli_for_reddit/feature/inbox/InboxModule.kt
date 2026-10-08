package com.bennybar.luli_for_reddit.feature.inbox

import android.content.Intent
import com.bennybar.luli_for_reddit.AppContainer
import com.bennybar.luli_for_reddit.state.UserScoped
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/** [Agent D] Inbox state, unread badge, background polling + notifications. */
class InboxModule(private val c: AppContainer) : UserScoped {
    /** Unread inbox count for the nav badge. */
    val unreadCount: StateFlow<Int> = MutableStateFlow(0)
    fun refreshUnread() {}
    /** App start: schedule background polling if notifications are on. */
    fun onAppStart() {}
    /** App resumed (>=2 min since last): re-sync inbox + unread. */
    fun onAppResumed() {}
    /** Handles a notification-tap intent; true if consumed (navigates itself). */
    fun handleLaunchIntent(intent: Intent): Boolean = false
    /** POST_NOTIFICATIONS permission (call from UI). */
    suspend fun requestPermission(): Boolean = false
    /** Polls once; [notify] = false primes the "seen" set without notifying. */
    suspend fun pollInbox(notify: Boolean) {}
    fun registerPolling() {}
    fun cancelPolling() {}
    override fun onUserChanged(username: String) {}
}
