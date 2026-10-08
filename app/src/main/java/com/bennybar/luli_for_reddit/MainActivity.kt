package com.bennybar.luli_for_reddit

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SnackbarHost
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
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
import com.bennybar.luli_for_reddit.feature.media.GalleryViewerScreen
import com.bennybar.luli_for_reddit.feature.media.ImageViewerScreen
import com.bennybar.luli_for_reddit.feature.media.VideoViewerScreen
import com.bennybar.luli_for_reddit.feature.post.PostDetailScreen
import com.bennybar.luli_for_reddit.feature.settings.ContentFiltersScreen
import com.bennybar.luli_for_reddit.feature.settings.ManageForYouScreen
import com.bennybar.luli_for_reddit.feature.settings.PolicyScreen
import com.bennybar.luli_for_reddit.feature.settings.SettingsScreen
import com.bennybar.luli_for_reddit.nav.AppNavigator
import com.bennybar.luli_for_reddit.nav.LocalNavigator
import com.bennybar.luli_for_reddit.nav.Route
import com.bennybar.luli_for_reddit.ui.OverlayHost
import com.bennybar.luli_for_reddit.ui.theme.IlayTheme
import kotlinx.coroutines.flow.MutableStateFlow

class MainActivity : ComponentActivity() {
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
        if (savedInstanceState == null) handleIntent(intent)
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
    val navigator = remember(controller) { AppNavigator(context, controller, scope) }
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
        routeForRedditUrl(uri)?.let(navigator::push)
    }

    CompositionLocalProvider(LocalNavigator provides navigator) {
        Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surface)) {
            NavHost(
                navController = controller,
                startDestination = start,
                enterTransition = { fadeIn() },
                exitTransition = { fadeOut() },
            ) {
                composable<Route.Login> { LoginScreen() }
                composable<Route.WebLogin> { WebLoginScreen() }
                composable<Route.Home> { HomeScreen() }
                composable<Route.Settings> { SettingsScreen() }
                composable<Route.ManageForYou> { ManageForYouScreen() }
                composable<Route.ContentFilters> { ContentFiltersScreen() }
                composable<Route.Policy> { PolicyScreen() }
                composable<Route.History> { HistoryScreen() }
                composable<Route.Saved> { SavedScreen() }
                composable<Route.Offline> { OfflineScreen() }
                composable<Route.Search> { val r = it.toRoute<Route.Search>(); SearchScreen(r.subreddit, r.query) }
                composable<Route.Submit> { SubmitScreen(it.toRoute<Route.Submit>().subreddit) }
                composable<Route.MessageThread> { MessageThreadScreen(it.toRoute<Route.MessageThread>().fullname) }
                composable<Route.ComposeMessage> { ComposeMessageScreen(it.toRoute<Route.ComposeMessage>().to) }
                composable<Route.Subreddit> { SubredditScreen(it.toRoute<Route.Subreddit>().name) }
                composable<Route.User> { UserScreen(it.toRoute<Route.User>().username) }
                composable<Route.Multireddit> { val r = it.toRoute<Route.Multireddit>(); MultiredditScreen(r.username, r.name) }
                composable<Route.ManageMultireddit> {
                    val r = it.toRoute<Route.ManageMultireddit>(); ManageMultiredditScreen(r.username, r.name)
                }
                composable<Route.Post> {
                    val r = it.toRoute<Route.Post>(); PostDetailScreen(r.subreddit, r.postId, r.focusCommentId)
                }
                composable<Route.ImageViewer> { val r = it.toRoute<Route.ImageViewer>(); ImageViewerScreen(r.url, r.title) }
                composable<Route.GalleryViewer> { GalleryViewerScreen(it.toRoute<Route.GalleryViewer>()) }
                composable<Route.VideoViewer> { VideoViewerScreen(it.toRoute<Route.VideoViewer>()) }
            }
            OverlayHost()
            SnackbarHost(
                navigator.snackbar,
                Modifier.align(Alignment.BottomCenter).navigationBarsPadding().padding(bottom = navigator.snackbarBottomPadding),
            )
        }
    }
}
