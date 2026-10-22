package com.bennybar.luli_for_reddit.feature.inbox

import com.bennybar.luli_for_reddit.feature.reminders.PostReminders
import com.bennybar.luli_for_reddit.state.userScopedKey
import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import com.bennybar.luli_for_reddit.AppContainer
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.auth.SessionState
import com.bennybar.luli_for_reddit.core.arr
import com.bennybar.luli_for_reddit.core.get
import com.bennybar.luli_for_reddit.core.isTrue
import com.bennybar.luli_for_reddit.core.str
import com.bennybar.luli_for_reddit.feature.media.launchForResult
import com.bennybar.luli_for_reddit.model.InboxItem
import com.bennybar.luli_for_reddit.nav.Route
import com.bennybar.luli_for_reddit.ui.Overlays
import com.bennybar.luli_for_reddit.state.UserScoped
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** One inbox tab's list (`where` = inbox | unread | messages | sent). */
data class InboxTabState(
    val items: List<InboxItem> = emptyList(),
    val after: String? = null,
    /** True until the first page arrives (or fails). */
    val loading: Boolean = true,
    val loadingMore: Boolean = false,
    val error: Throwable? = null,
) {
    val hasMore: Boolean get() = !after.isNullOrEmpty()
}

/**
 * Inbox state (the four tabs), the unread badge, and background polling +
 * notifications (the Kotlin counterpart of inbox_controller.dart,
 * inbox_poller.dart and notification_service.dart).
 */
class InboxModule(private val c: AppContainer) : UserScoped {
    private val tabs: Map<String, MutableStateFlow<InboxTabState>> =
        TABS.associate { it.second to MutableStateFlow(InboxTabState()) }
    private val loadJobs = mutableMapOf<String, Job>()

    /** Bumped on account change, so a stale in-flight load can't land in the new account's tabs. */
    @Volatile private var generation = 0
    private val pollLock = Mutex()

    fun tab(where: String): StateFlow<InboxTabState> = tabs.getValue(where)

    private val _unread = MutableStateFlow(0)

    /** Unread inbox count for the nav badge. */
    val unreadCount: StateFlow<Int> = _unread
    private var unreadJob: Job? = null

    private val anonymous: Boolean get() = c.session.session?.anonymous == true

    /** Re-reads the unread count (no inbox while browsing without an account). */
    fun refreshUnread() {
        if (anonymous || c.session.state.value !is SessionState.LoggedIn) {
            _unread.value = 0
            return
        }
        unreadJob?.cancel()
        unreadJob = c.scope.launch {
            try {
                // Coalesce bursts (marking several items quickly) into one request.
                delay(700)
                _unread.value = c.repository.getUnreadCount()
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) { /* keep the last count */ }
        }
    }

    // --- Tabs ---

    /** Loads [where] the first time a tab is shown. */
    fun ensureLoaded(where: String) {
        val s = tabs.getValue(where).value
        if (s.items.isEmpty() && s.error == null && loadJobs[where]?.isActive != true) refresh(where)
    }

    /** Reloads one tab from the first page (and the badge). */
    fun refresh(where: String): Job {
        loadJobs[where]?.cancel()
        val flow = tabs.getValue(where)
        val gen = generation
        val job = c.scope.launch {
            try {
                val listing = c.repository.getInbox(where = where)
                if (gen != generation) return@launch
                flow.value = InboxTabState(listing.items, listing.after, loading = false)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (gen != generation) return@launch
                flow.update { it.copy(loading = false, loadingMore = false, error = e) }
            }
        }
        loadJobs[where] = job
        refreshUnread()
        return job
    }

    /**
     * Pull-to-refresh: suspends until the reload finishes. The current list
     * (or error) stays up meanwhile — clearing the error here flashed
     * "Nothing here" — and is replaced by the result, as in Flutter.
     */
    suspend fun refreshAndWait(where: String) {
        refresh(where).join()
    }

    fun loadMore(where: String) {
        val flow = tabs.getValue(where)
        val current = flow.value
        if (!current.hasMore || current.loadingMore || current.loading) return
        flow.value = current.copy(loadingMore = true)
        val gen = generation
        c.scope.launch {
            try {
                val listing = c.repository.getInbox(where = where, after = current.after)
                if (gen != generation) return@launch
                flow.update { s ->
                    val seen = s.items.mapTo(HashSet()) { it.fullname }
                    s.copy(items = s.items + listing.items.filter { it.fullname !in seen }, after = listing.after, loadingMore = false)
                }
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                flow.update { it.copy(loadingMore = false) }
            }
        }
    }

    /** Applies [change] to [fullname] in every tab (an item can show in several). */
    private fun mapItem(fullname: String, change: (InboxItem) -> InboxItem?) {
        for (flow in tabs.values) {
            flow.update { s ->
                if (s.items.none { it.fullname == fullname }) s
                else s.copy(items = s.items.mapNotNull { if (it.fullname == fullname) change(it) else it })
            }
        }
    }

    /** Whether the loaded item is unread (null if it isn't loaded). */
    private fun isNew(fullname: String): Boolean? =
        tabs.values.firstNotNullOfOrNull { f -> f.value.items.firstOrNull { it.fullname == fullname }?.isNew }

    /**
     * Replies / mentions (comment ids) Reddit's notification list says you
     * opened elsewhere: mark the loaded unread ones read here and in Reddit's
     * inbox (not back on the notification list, where they already are).
     */
    fun markReadFromReddit(commentIds: List<String>) {
        for (id in commentIds) {
            val fullname = "t1_$id"
            if (isNew(fullname) == true) markRead(fullname, notifications = false)
        }
    }

    /** Optimistically marks one item read locally and on the server ([notifications]: Reddit's notification list too). */
    fun markRead(fullname: String, notifications: Boolean = true) {
        // Already read: nothing to send (a repeated swipe used to fire again and
        // again, hitting Reddit's rate limit).
        if (isNew(fullname) == false) return
        mapItem(fullname) { it.copy(isNew = false) }
        c.scope.launch {
            try {
                c.repository.markRead(fullname)
                refreshUnread()
            } catch (_: Exception) { /* keep optimistic state */ }
        }
        // Replies and mentions also sit in Reddit's notification list (website sign-in).
        if (notifications && fullname.startsWith("t1_")) c.redditNotifications.markReadOnReddit(fullname.removePrefix("t1_"))
    }

    /** Optimistically marks one item unread locally and on the server. */
    fun markUnread(fullname: String) {
        if (isNew(fullname) == true) return
        mapItem(fullname) { it.copy(isNew = true) }
        c.scope.launch {
            try {
                c.repository.markUnread(fullname)
                refreshUnread()
            } catch (_: Exception) { /* keep optimistic state */ }
        }
    }

    /** Deletes a private message (t4_). Optimistically removes it from the list. */
    fun deleteMessage(fullname: String) {
        mapItem(fullname) { null }
        c.scope.launch {
            try {
                c.repository.deleteMessage(fullname)
                refreshUnread()
            } catch (_: Exception) { /* keep optimistic removal */ }
        }
    }

    /**
     * Marks *everything* read — Reddit's read_all_messages has no per-tab
     * variant — so every tab is refreshed afterwards, not just this one.
     * Throws on failure (after restoring this tab) so the caller can say so.
     */
    suspend fun markAllRead(where: String) {
        val flow = tabs.getValue(where)
        val before = flow.value
        flow.value = before.copy(items = before.items.map { it.copy(isNew = false) })
        try {
            c.repository.markAllRead()
        } catch (e: Exception) {
            flow.value = before
            throw e
        }
        c.redditNotifications.markAllReadOnReddit()
        refreshLoadedTabs()
    }

    private fun refreshLoadedTabs() {
        for ((where, flow) in tabs) {
            val s = flow.value
            if (s.items.isNotEmpty() || s.error != null || loadJobs[where] != null) refresh(where)
        }
        refreshUnread()
    }

    // --- App lifecycle ---

    /** App start: schedule background polling if notifications are on. */
    fun onAppStart() {
        InboxNotifications.createChannel(c.context)
        if (c.prefs.getBool(NOTIFY_INBOX_PREF) == true) registerPolling()
    }

    /**
     * App resumed (>= 2 min since last): re-sync every inbox tab so items
     * read on the official app show as read here, and the badge.
     */
    fun onAppResumed() {
        if (anonymous) return
        refreshLoadedTabs()
    }

    // --- Notifications ---

    /**
     * Handles a notification-tap intent; true if consumed (navigates itself
     * once the navigator and session are ready — on a cold start the intent
     * arrives before the UI exists).
     */
    fun handleLaunchIntent(intent: Intent): Boolean {
        val target = intent.getStringExtra(InboxNotifications.EXTRA_TARGET) ?: return false
        // Consumed: don't route it again if the activity re-delivers this intent.
        intent.removeExtra(InboxNotifications.EXTRA_TARGET)
        when (target) {
            InboxNotifications.TARGET_POST -> {
                val sub = intent.getStringExtra(InboxNotifications.EXTRA_SUBREDDIT)
                val post = intent.getStringExtra(InboxNotifications.EXTRA_POST_ID)
                openFromNotification(if (sub != null && post != null) Route.Post(sub, post, intent.getStringExtra(InboxNotifications.EXTRA_COMMENT_ID)) else null, inbox = true)
            }
            // A post reminder: open the post where you are (not the Inbox).
            PostReminders.TARGET -> {
                val sub = intent.getStringExtra(InboxNotifications.EXTRA_SUBREDDIT)
                val post = intent.getStringExtra(InboxNotifications.EXTRA_POST_ID)
                openFromNotification(if (sub != null && post != null) Route.Post(sub, post) else null, inbox = false)
            }
            InboxNotifications.TARGET_MESSAGE ->
                openFromNotification(intent.getStringExtra(InboxNotifications.EXTRA_MESSAGE)?.let { Route.MessageThread(it) }, inbox = true)
            // A Reddit app notification Ilay took over: find its post / comment first.
            RedditAppNotifications.TARGET -> {
                val title = intent.getStringExtra(RedditAppNotifications.EXTRA_TITLE).orEmpty()
                val text = intent.getStringExtra(RedditAppNotifications.EXTRA_TEXT).orEmpty()
                val inbox = RedditAppNotifications.isInbox(title)
                c.scope.launch {
                    openFromNotification(runCatching { RedditAppNotifications.resolve(title, text) }.getOrNull()?.route, inbox)
                }
            }
            else -> openFromNotification(null, inbox = true)
        }
        return true
    }

    /**
     * A notification was tapped: back to the home shell (screens opened by
     * earlier notifications are closed, so Back doesn't walk through them), on
     * the Inbox tab for inbox items, then [route] on top.
     */
    private fun openFromNotification(route: Route?, inbox: Boolean) {
        c.scope.launch {
            repeat(200) { // up to ~10 s for a cold start
                val nav = app.navigatorOrNull
                val state = c.session.state.value
                val hasGraph = nav != null && runCatching { nav.controller.graph }.isSuccess
                if (nav != null && hasGraph && state != SessionState.Loading) {
                    if (state is SessionState.LoggedIn) {
                        // The app may be anywhere: close a full-screen viewer or open
                        // sheet first, or the screen opens hidden underneath it.
                        nav.viewers.clear()
                        Overlays.dismissAll()
                        nav.controller.popBackStack<Route.Home>(inclusive = false)
                        if (inbox) app.feed.openTab.value = 2
                        route?.let(nav::push)
                    }
                    return@launch
                }
                delay(50)
            }
        }
    }

    /** POST_NOTIFICATIONS permission (call from UI). True if granted. */
    suspend fun requestPermission(): Boolean {
        InboxNotifications.createChannel(c.context)
        val granted = { ContextCompat.checkSelfPermission(c.context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED }
        if (granted()) return true
        return launchForResult(ActivityResultContracts.RequestPermission(), Manifest.permission.POST_NOTIFICATIONS)
            ?: granted()
    }

    /**
     * Fetches unread inbox items and, when [notify] is true, fires a
     * notification for each one not already seen. When [notify] is false it
     * only "primes" the seen set (used when the user first turns the feature
     * on, so we don't dump a notification for every pre-existing unread item).
     * Returns how many notifications it posted.
     */
    /** Checks the inbox; returns the items it showed a notification for. */
    internal suspend fun pollInbox(notify: Boolean): List<UnreadItem> = pollLock.withLock {
        // One poll at a time (the worker and the Reddit-notification listener
        // can both start one), and for one account: the account is read before
        // the request, and a switch while it runs drops the result rather than
        // notifying or recording one account's items as the other's.
        val gen = generation
        val user = runCatching { c.secureStore.username() }.getOrNull().orEmpty()
        // Per account: the polled inbox is the active account's, so one shared
        // list made every switch notify for all of the other account's unread.
        // An account's first poll only primes its list (no burst of old items).
        val key = userScopedKey(c.prefs, user, SEEN_IDS_PREF)
        val primed = c.prefs.contains(key)
        val seen = (c.prefs.getStringList(key) ?: emptyList()).toSet()
        val items = fetchUnread(seen)
        if (items == null) { // not logged in / network error
            c.notificationLog.checked("Couldn't check: offline, or not signed in")
            return@withLock emptyList()
        }
        if (gen != generation || runCatching { c.secureStore.username() }.getOrNull().orEmpty() != user) return@withLock emptyList()
        val fresh = items.filter { it.fullname !in seen }
        val shown = if (notify && primed) {
            fresh.filter { item ->
                InboxNotifications.show(c.context, item).also { ok ->
                    c.notificationLog.add(
                        NotificationEvent(
                            at = System.currentTimeMillis(), account = user, source = NotificationEvent.SOURCE_INBOX,
                            title = item.title, text = item.body,
                            outcome = if (ok) NotificationEvent.Outcome.SHOWN else NotificationEvent.Outcome.NOT_SHOWN,
                            subreddit = item.post?.first, postId = item.post?.second, commentId = item.post?.third,
                            messageFullname = item.messageFullname,
                        ),
                    )
                }
            }
        } else emptyList()
        c.notificationLog.checked(
            when {
                !primed -> "First check for u/$user: ${items.size} unread (not notified)"
                fresh.isEmpty() -> "${items.size} unread, nothing new"
                !notify -> "${fresh.size} new (not notified: checked from the app)"
                else -> "${fresh.size} new, ${shown.size} notified"
            },
        )
        // Remember everything currently unread so we never re-notify, capped so
        // the list can't grow without bound.
        val current = items.mapTo(HashSet()) { it.fullname }
        val updated = items.map { it.fullname } + seen.filter { it !in current }
        c.prefs.setStringList(key, updated.take(200))
        if (fresh.isNotEmpty()) c.scope.launch { refreshUnread() }
        shown
    }

    /**
     * The current unread items, or null if we can't authenticate / reach Reddit.
     * Reads past the first 25 while every item on a page is new (a burst
     * between checks), up to 100: older new ones would otherwise never notify.
     */
    private suspend fun fetchUnread(seen: Set<String>): List<UnreadItem>? {
        return try {
            if (c.secureStore.authMode() == "anon" || c.secureStore.username().isNullOrEmpty()) return null
            val out = ArrayList<UnreadItem>()
            var after: String? = null
            repeat(4) { page ->
                val res = c.client.getResult("/message/unread", mapOf("limit" to 25, "after" to after))
                if (res.fromCache) return if (page == 0) null else out // offline: never notify from a stale copy
                val items = res.json["data"]["children"].arr().orEmpty().mapNotNull { parseUnread(it["data"]) }
                out += items
                after = res.json["data"]["after"].str()
                if (after.isNullOrEmpty() || items.size < 25 || items.any { it.fullname in seen }) return out
            }
            out
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            null
        }
    }

    fun registerPolling() = InboxNotifications.registerPolling(c.context, c.prefs)
    fun cancelPolling() = InboxNotifications.cancelPolling(c.context)

    override fun onUserChanged(username: String) {
        generation++
        loadJobs.values.forEach { it.cancel() }
        loadJobs.clear()
        tabs.values.forEach { it.value = InboxTabState() }
        _unread.value = 0
        refreshUnread()
    }

    companion object {
        val TABS = listOf("All" to "inbox", "Unread" to "unread", "Messages" to "messages", "Sent" to "sent")

        /** Mirrors the Settings flag (same prefs key as the Flutter build). */
        const val NOTIFY_INBOX_PREF = "notifyInbox"
        private const val SEEN_IDS_PREF = "notif_seen_ids"

        /** One unread item parsed from Reddit's raw inbox listing (pure, unit-testable). */
        internal fun parseUnread(d: kotlinx.serialization.json.JsonElement?): UnreadItem? {
            val fullname = d["name"].str() ?: return null
            val author = d["author"].str() ?: "Reddit"
            val wasComment = d["was_comment"].isTrue()
            val subject = d["subject"].str() ?: ""
            val linkTitle = d["link_title"].str()
            val rawBody = (d["body"].str() ?: "").replace('\n', ' ').trim()

            val linkSuffix = if (linkTitle != null) " · $linkTitle" else ""
            val title = if (wasComment) "u/$author replied$linkSuffix"
            else subject.ifEmpty { "Message from u/$author" }
            val snippet = when {
                rawBody.length > 140 -> rawBody.take(140) + "…"
                rawBody.isEmpty() -> "Open Ilay to read"
                else -> rawBody
            }
            // Deep-link target for comment replies/mentions (t1_): jump to the comment.
            val sub = d["subreddit"].str()
            val linkId = d["link_id"].str() // t3_<postId>
            val post = if (wasComment && fullname.startsWith("t1_") && !sub.isNullOrEmpty() && linkId?.startsWith("t3_") == true) {
                Triple(sub, linkId.removePrefix("t3_"), fullname.removePrefix("t1_"))
            } else null
            // Messages open their conversation (by its first message when known).
            val message = if (!wasComment && fullname.startsWith("t4_")) (d["first_message_name"].str() ?: fullname) else null
            return UnreadItem(fullname, title, snippet, post, message)
        }
    }
}

/** One unread inbox item, ready for a notification. */
internal data class UnreadItem(
    val fullname: String,
    val title: String,
    val body: String,
    /** (subreddit, postId, commentId) for comment replies / mentions. */
    val post: Triple<String, String, String>?,
    /** Thread to open for private messages. */
    val messageFullname: String?,
)
