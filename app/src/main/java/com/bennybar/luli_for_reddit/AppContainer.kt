package com.bennybar.luli_for_reddit

import android.content.Context
import com.bennybar.luli_for_reddit.auth.AuthRepository
import com.bennybar.luli_for_reddit.auth.SessionManager
import com.bennybar.luli_for_reddit.auth.SessionState
import com.bennybar.luli_for_reddit.core.net.RateLimit
import com.bennybar.luli_for_reddit.core.net.RedditClient
import com.bennybar.luli_for_reddit.core.net.ResponseCache
import com.bennybar.luli_for_reddit.core.storage.Prefs
import com.bennybar.luli_for_reddit.core.storage.SecureStore
import com.bennybar.luli_for_reddit.data.RedditRepository
import com.bennybar.luli_for_reddit.feature.feed.FeedModule
import com.bennybar.luli_for_reddit.feature.foryou.ForYouModule
import com.bennybar.luli_for_reddit.feature.inbox.InboxModule
import com.bennybar.luli_for_reddit.feature.media.MediaModule
import com.bennybar.luli_for_reddit.feature.post.PostModule
import com.bennybar.luli_for_reddit.nav.AppNavigator
import com.bennybar.luli_for_reddit.settings.SettingsStore
import com.bennybar.luli_for_reddit.state.ContentFiltersStore
import com.bennybar.luli_for_reddit.state.Drafts
import com.bennybar.luli_for_reddit.state.ExpiringIds
import com.bennybar.luli_for_reddit.state.SummaryStore
import com.bennybar.luli_for_reddit.state.HistoryStore
import com.bennybar.luli_for_reddit.state.OfflineStore
import com.bennybar.luli_for_reddit.state.PostOverrides
import com.bennybar.luli_for_reddit.state.ThreadVisits
import com.bennybar.luli_for_reddit.state.UserScoped
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

/** The app's singletons (manual DI). Reach it with the global [app]. */
class AppContainer(val context: Context) {
    /** Lives as long as the process (background work, stores). */
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    /**
     * This process was started to restore the app after Android killed it in
     * the background (not a fresh launch): feeds show their saved page if it's
     * still fresh rather than loading anew.
     */
    @Volatile var restoredProcess = false

    val prefs = Prefs(context)
    val secureStore = SecureStore(context)
    val settings = SettingsStore(prefs)
    val authRepository = AuthRepository(secureStore)
    val session = SessionManager(secureStore, authRepository, prefs, scope)

    /** Latest Reddit API rate-limit snapshot. */
    val rateLimit = MutableStateFlow<RateLimit?>(null)

    val client = RedditClient(
        store = secureStore,
        auth = authRepository,
        cache = ResponseCache(context.cacheDir),
        onRateLimit = { rateLimit.value = it },
        cacheEnabled = { settings.value.offlineCache },
    )
    val repository = RedditRepository(client)

    // Shared, per-account local state.
    val postOverrides = PostOverrides()
    /**
     * Posts hidden with Hide (also hidden on Reddit). Kept on the device too —
     * Home's id-fetched posts and saved first pages don't honour Reddit's
     * hidden flag, so a session-only set let them reappear after a restart.
     */
    val hiddenPosts = ExpiringIds(prefs, "hiddenPostIds") { settings.value.hiddenPostDays * 24L * 60 * 60_000L }
    /** Posts swiped away from Home / For You ("Dismiss"), for a day. */
    val dismissedPosts = ExpiringIds(prefs, "dismissedPosts") { 24 * 60 * 60_000L }
    /** Subreddits hidden from Home / For You for a week (lowercase names). */
    val hiddenHomeSubs = ExpiringIds(prefs, "hiddenHomeSubs") { 7 * 24 * 60 * 60_000L }
    val summaries = SummaryStore(context)
    val history = HistoryStore(prefs)
    val threadVisits = ThreadVisits(prefs, settings)
    val contentFilters = ContentFiltersStore(prefs)
    val offline = OfflineStore(context, prefs, repository)
    val drafts = Drafts(prefs)

    // Feature modules (each owns its feature's singletons).
    val feed by lazy { FeedModule(this) }
    val post by lazy { PostModule(this) }
    val forYou by lazy { ForYouModule(this) }
    val inbox by lazy { InboxModule(this) }
    val media by lazy { MediaModule(this) }

    /** The identity whose per-account stores are loaded (after a login/switch settles). */
    val loadedIdentity = MutableStateFlow<String?>(null)

    /** Set by IlayActivity while it's alive. */
    @Volatile var navigatorOrNull: AppNavigator? = null
    val navigator: AppNavigator get() = navigatorOrNull ?: error("No activity")

    private val userScoped: List<UserScoped>
        get() = listOf(postOverrides, hiddenPosts, dismissedPosts, hiddenHomeSubs, summaries, history, threadVisits, contentFilters, offline, feed, post, forYou, inbox, media)

    /** Called once by [IlayApp] after [app] is assigned (modules may use it). */
    fun start() {
        // Load per-account stores for the logged-out identity right away, so
        // they're usable before the session finishes loading.
        userScoped.forEach { it.onUserChanged("") }
        settings.state.map { it.subsCacheEnabled to it.subsCacheMinutes }.distinctUntilChanged().let { flow ->
            scope.launch {
                flow.collect { (on, minutes) ->
                    repository.subsCacheEnabled = on
                    repository.subsCacheTtlMillis = minutes * 60_000L
                }
            }
        }
        // A new "Hide posts for" time applies at once (a shorter one un-hides now).
        scope.launch { settings.state.map { it.hiddenPostDays }.distinctUntilChanged().drop(1).collect { hiddenPosts.refresh() } }
                // On any account change (switch, or logout then login as someone else):
        // re-read auth config and reload everything that belongs to an account.
        scope.launch {
            var previous: String? = null
            session.state.collect { s ->
                client.invalidateAuthConfig()
                // A full logout drops back to the logged-out identity (bare keys),
                // so the previous account's stores don't stay loaded.
                val identity = when (s) {
                    is SessionState.LoggedIn -> s.session.identity
                    // Only a real logout (has_account cleared) — not a transient
                    // keystore read failure, which must keep everything loaded.
                    SessionState.LoggedOut -> if (session.hasAccount) return@collect else ""
                    SessionState.Loading -> return@collect
                }
                if (identity != previous) {
                    if (previous != null) repository.clearSubsCache()
                    val first = previous == null
                    previous = identity
                    val username = (s as? SessionState.LoggedIn)?.session?.username ?: ""
                    // start() already loaded the logged-out identity.
                    if (!(first && identity.isEmpty())) userScoped.forEach { it.onUserChanged(username) }
                }
                loadedIdentity.value = identity
            }
        }
    }
}

lateinit var appInstance: AppContainer

/** The app's singletons. */
val app: AppContainer get() = appInstance
