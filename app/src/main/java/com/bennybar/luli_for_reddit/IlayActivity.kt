package com.bennybar.luli_for_reddit

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.toRoute
import com.bennybar.luli_for_reddit.auth.OAuthFlow
import com.bennybar.luli_for_reddit.auth.SessionState
import com.bennybar.luli_for_reddit.core.isRedditHost
import com.bennybar.luli_for_reddit.core.routeForRedditUrl
import com.bennybar.luli_for_reddit.feature.auth.LoginScreen
import com.bennybar.luli_for_reddit.feature.auth.WebLoginScreen
import com.bennybar.luli_for_reddit.feature.compose.SubmitScreen
import com.bennybar.luli_for_reddit.feature.feed.HistoryScreen
import com.bennybar.luli_for_reddit.feature.feed.ManageMultiredditScreen
import com.bennybar.luli_for_reddit.feature.feed.MultiredditScreen
import com.bennybar.luli_for_reddit.feature.feed.OfflineScreen
import com.bennybar.luli_for_reddit.feature.feed.SavedScreen
import com.bennybar.luli_for_reddit.feature.feed.SearchScreen
import com.bennybar.luli_for_reddit.feature.feed.SubredditScreen
import com.bennybar.luli_for_reddit.feature.feed.UserScreen
import com.bennybar.luli_for_reddit.feature.home.HomeScreen
import com.bennybar.luli_for_reddit.feature.inbox.ComposeMessageScreen
import com.bennybar.luli_for_reddit.feature.inbox.MessageThreadScreen
import com.bennybar.luli_for_reddit.feature.media.MediaViewerHost
import com.bennybar.luli_for_reddit.feature.post.PostDetailScreen
import com.bennybar.luli_for_reddit.feature.settings.ContentFiltersScreen
import com.bennybar.luli_for_reddit.feature.settings.ManageForYouScreen
import com.bennybar.luli_for_reddit.feature.settings.PolicyScreen
import com.bennybar.luli_for_reddit.feature.settings.SettingsScreen
import com.bennybar.luli_for_reddit.nav.AppNavigator
import com.bennybar.luli_for_reddit.nav.LocalNavigator
import com.bennybar.luli_for_reddit.nav.Route
import com.bennybar.luli_for_reddit.nav.ViewerStack
import com.bennybar.luli_for_reddit.ui.OverlayHost
import com.bennybar.luli_for_reddit.ui.theme.IlayTheme
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import com.bennybar.luli_for_reddit.core.Analytics
import androidx.compose.animation.AnimatedContentScope
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.ui.unit.dp
import androidx.navigation.NavBackStackEntry
import androidx.navigation.NavGraphBuilder

/** Once per process (the activity can be recreated). */
private var appStartTracked = false

class IlayActivity : ComponentActivity() {
    /** The latest incoming deep link (VIEW intent), consumed by the UI. */
    private val pendingLink = MutableStateFlow<Uri?>(null)
    private var lastLink: String? = null
    private var lastInboxSync = System.currentTimeMillis()

    override fun onCreate(savedInstanceState: Bundle?) {
        val splash = installSplashScreen()
        super.onCreate(savedInstanceState)
        // Keep the splash up until the stored session is read (one keystore read).
        splash.setKeepOnScreenCondition { app.session.state.value == SessionState.Loading }
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.auto(android.graphics.Color.TRANSPARENT, android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.auto(android.graphics.Color.TRANSPARENT, android.graphics.Color.TRANSPARENT),
        )
        // Restored after Android killed the app in the background (a swipe
        // away from Recents starts fresh, with no saved state).
        if (savedInstanceState != null) app.restoredProcess = true
        if (savedInstanceState == null) {
            prestartFrontpage()
            trackAppStarted()
            // Reopened from Recents after the process died: the launch intent is
            // the old one (e.g. a notification tap) — don't replay it.
            if (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY == 0) handleIntent(intent)
        }
        setContent {
            val settings by app.settings.state.collectAsStateWithLifecycle()
            IlayTheme(settings) { AppRoot(pendingLink) }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    /**
     * Anonymous: which login method this install uses. Sent from the activity,
     * not Application.onCreate — that also runs for the background inbox poll,
     * which would count as a launch every 15 minutes.
     */
    private fun trackAppStarted() {
        if (appStartTracked) return
        appStartTracked = true
        app.scope.launch {
            val username = app.secureStore.username()
            val method = when {
                username.isNullOrEmpty() -> "logged_out"
                app.secureStore.authMode() == "web" -> "website"
                else -> "api"
            }
            Analytics.track("app_started", mapOf("login_method" to method))
        }
    }

    /**
     * Starts loading the frontpage (For You's sources, or Reddit Home's hidden
     * browser) as soon as the stored session is read, while the splash and
     * first frame are still being set up, instead of when Home first composes.
     * Not in Application.onCreate: that also runs for the background inbox poll.
     */
    private fun prestartFrontpage() {
        app.scope.launch {
            val s = app.session.state.first { it != SessionState.Loading } as? SessionState.LoggedIn ?: return@launch
            // After the account's stores are loaded: that also resets the feeds.
            app.loadedIdentity.first { it == s.session.identity }
            app.feed.controller("").start()
        }
    }

    private fun handleIntent(intent: Intent?) {
        intent ?: return
        if (app.inbox.handleLaunchIntent(intent)) return
        val uri = intent.data ?: return
        if (intent.action != Intent.ACTION_VIEW || !isRedditHost(uri.host)) return
        // Dedupe: the same link can arrive twice (cold start + resume).
        if (uri.toString() == lastLink) return
        lastLink = uri.toString()
        pendingLink.value = uri
    }

    override fun onPause() {
        super.onPause()
        OAuthFlow.onAppPaused()
    }

    override fun onResume() {
        super.onResume()
        OAuthFlow.onAppResumed()
        // Re-read the keystore to restore auth after background/resume.
        app.session.reload()
        // Re-sync the inbox (items read elsewhere show as read), at most every 2 minutes.
        val now = System.currentTimeMillis()
        if (now - lastInboxSync > 2 * 60_000) {
            lastInboxSync = now
            app.inbox.onAppResumed()
        }
    }
}

@Composable
private fun AppRoot(pendingLink: MutableStateFlow<Uri?>) {
    val context = LocalContext.current
    val controller = rememberNavController()
    val scope = rememberCoroutineScope()
    val viewers = rememberSaveable(saver = ViewerStack.Saver) { ViewerStack() }
    val navigator = remember(controller) { AppNavigator(context, controller, scope, viewers) }
    DisposableEffect(navigator) {
        app.navigatorOrNull = navigator
        onDispose { if (app.navigatorOrNull === navigator) app.navigatorOrNull = null }
    }
    val session by app.session.state.collectAsStateWithLifecycle()
    val link by pendingLink.collectAsStateWithLifecycle()

    if (session == SessionState.Loading) {
        Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surface))
        return
    }
    val loggedIn = session is SessionState.LoggedIn
    // A transient keystore read failure can momentarily read as logged out;
    // don't bounce a known account to the login screen.
    val showHome = loggedIn || app.session.hasAccount
    val start: Route = remember { if (showHome) Route.Home else Route.Login }

    LaunchedEffect(showHome) {
        val atLogin = controller.currentDestination?.route?.contains("Login") == true
        if (showHome && atLogin) navigator.resetTo(Route.Home)
        if (!showHome && !atLogin) navigator.resetTo(Route.Login)
    }
    LaunchedEffect(link, showHome) {
        val uri = link ?: return@LaunchedEffect
        if (!showHome) return@LaunchedEffect
        pendingLink.value = null
        // An unsupported reddit.com link goes Home (as the Flutter router did).
        routeForRedditUrl(uri)?.let(navigator::push) ?: navigator.resetTo(Route.Home)
    }

    CompositionLocalProvider(LocalNavigator provides navigator) {
        // A Surface (not a plain background) so content colour = onSurface everywhere.
        Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.surface) { Box(Modifier.fillMaxSize()) {
            NavHost(
                navController = controller,
                startDestination = start,
                // A fast full-width slide: the new page slides in from the
                // right over a slight parallax of the old one. The back gesture
                // scrubs the reverse (linear, so the page stays under the finger).
                enterTransition = { slideInHorizontally(tween(300, easing = Emphasized)) { it } },
                exitTransition = { slideOutHorizontally(tween(300, easing = Emphasized)) { -it / 4 } },
                popEnterTransition = { slideInHorizontally(tween(300, easing = Emphasized)) { -it / 4 } },
                popExitTransition = { slideOutHorizontally(tween(300, easing = Emphasized)) { it } },
                predictivePopEnterTransition = { slideInHorizontally(tween(300, easing = LinearEasing)) { -it / 4 } },
                predictivePopExitTransition = { slideOutHorizontally(tween(300, easing = LinearEasing)) { it } },
            ) {
                screen<Route.Login> { LoginScreen() }
                screen<Route.WebLogin> { WebLoginScreen(it.toRoute<Route.WebLogin>().clearFirst) }
                screen<Route.Home> { HomeScreen() }
                screen<Route.Settings> { SettingsScreen() }
                screen<Route.ManageForYou> { ManageForYouScreen() }
                screen<Route.ContentFilters> { ContentFiltersScreen() }
                screen<Route.Policy> { PolicyScreen() }
                screen<Route.History> { HistoryScreen() }
                screen<Route.Saved> { SavedScreen() }
                screen<Route.Offline> { OfflineScreen() }
                screen<Route.Search> { val r = it.toRoute<Route.Search>(); SearchScreen(r.subreddit, r.query) }
                screen<Route.Submit> { SubmitScreen(it.toRoute<Route.Submit>().subreddit) }
                screen<Route.MessageThread> { MessageThreadScreen(it.toRoute<Route.MessageThread>().fullname) }
                screen<Route.ComposeMessage> { ComposeMessageScreen(it.toRoute<Route.ComposeMessage>().to) }
                screen<Route.Subreddit> { SubredditScreen(it.toRoute<Route.Subreddit>().name) }
                screen<Route.User> { UserScreen(it.toRoute<Route.User>().username) }
                screen<Route.Multireddit> { val r = it.toRoute<Route.Multireddit>(); MultiredditScreen(r.username, r.name) }
                screen<Route.ManageMultireddit> {
                    val r = it.toRoute<Route.ManageMultireddit>(); ManageMultiredditScreen(r.username, r.name)
                }
                screen<Route.Post> {
                    val r = it.toRoute<Route.Post>(); PostDetailScreen(r.subreddit, r.postId, r.focusCommentId)
                }
            }
            // Media viewers: a transparent overlay above the current screen.
            MediaViewerHost(viewers)
            OverlayHost()
            SnackbarHost(
                navigator.snackbar,
                Modifier.align(Alignment.BottomCenter).navigationBarsPadding().padding(bottom = navigator.snackbarBottomPadding),
            )
        } }
    }
}


private val Emphasized = CubicBezierEasing(0.2f, 0f, 0f, 1f)

/** A destination drawn on an opaque surface, so sliding pages never show through. */
private inline fun <reified T : Any> NavGraphBuilder.screen(
    noinline content: @Composable AnimatedContentScope.(NavBackStackEntry) -> Unit,
) = composable<T> { entry ->
    Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surface)) {
        content(entry)
    }
}
