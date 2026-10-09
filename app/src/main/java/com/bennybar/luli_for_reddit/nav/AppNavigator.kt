package com.bennybar.luli_for_reddit.nav

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.navigation.NavHostController
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.core.isImageUrl
import com.bennybar.luli_for_reddit.core.isVideoUrl
import com.bennybar.luli_for_reddit.core.resolveVideoUrl
import com.bennybar.luli_for_reddit.core.routeForRedditUrl
import com.bennybar.luli_for_reddit.core.externalViewIntent
import com.bennybar.luli_for_reddit.core.resolveShareLink
import com.bennybar.luli_for_reddit.core.isShareLink
import com.bennybar.luli_for_reddit.feature.media.openPostVideo
import com.bennybar.luli_for_reddit.model.GalleryImage
import com.bennybar.luli_for_reddit.model.Post
import com.bennybar.luli_for_reddit.ui.friendlyError
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

val LocalNavigator = staticCompositionLocalOf<AppNavigator> { error("No navigator") }

/**
 * App-wide navigation + feedback: routes, links (media in the viewer,
 * reddit.com in the app, everything else in the browser), sharing and
 * snackbars. Available as [LocalNavigator] in composables and as
 * `app.navigator` elsewhere.
 */
class AppNavigator(
    val context: Context,
    val controller: NavHostController,
    val scope: CoroutineScope,
    /** Full-screen media viewers, drawn over the current screen (see IlayActivity). */
    val viewers: ViewerStack = ViewerStack(),
) {
    val snackbar = SnackbarHostState()

    /** Extra bottom padding for snackbars (the home shell's floating nav sets it). */
    var snackbarBottomPadding: Dp by mutableStateOf(0.dp)

    /** Opens a screen; an open media viewer would hide it, so it's closed first. */
    fun push(route: Route) {
        viewers.clear()
        controller.navigate(route) { launchSingleTop = route is Route.Home }
    }

    fun pop(): Boolean = controller.popBackStack()

    /** Clears the back stack and shows [route] (login ↔ home). */
    fun resetTo(route: Route) {
        viewers.clear()
        controller.navigate(route) {
            popUpTo(0) { inclusive = true }
            launchSingleTop = true
        }
    }

    /** Closes the top media viewer (fading out over the screen beneath). */
    fun closeViewer(): Boolean = viewers.closeTop()

    /** Opens a post's thread; the already-loaded [post] paints instantly. */
    fun openPost(post: Post, focusCommentId: String? = null) {
        NavCache.put(post.id, post)
        push(Route.Post(post.subreddit.ifEmpty { "_" }, post.id, focusCommentId))
    }

    fun openSubreddit(name: String) = push(Route.Subreddit(name))
    fun openUser(username: String) = push(Route.User(username))

    fun openImage(url: String, title: String? = null) = viewers.open(MediaViewer.Image(url, title))

    fun openGallery(images: List<GalleryImage>, title: String? = null, initialIndex: Int = 0) {
        if (images.isEmpty()) return
        viewers.open(
            MediaViewer.Gallery(
                urls = images.map { it.url },
                widths = images.map { it.width ?: 0 },
                heights = images.map { it.height ?: 0 },
                title = title,
                initialIndex = initialIndex,
            ),
        )
    }

    fun openVideo(url: String, title: String? = null, downloadUrl: String? = null, externalUrl: String? = null) =
        viewers.open(MediaViewer.Video(url, title, downloadUrl, externalUrl))

    /** Opens a video post full-screen (resolving RedGifs to its HD file first). */
    fun openPostVideo(post: Post) {
        scope.launch { openPostVideo(this@AppNavigator, post) }
    }

    /**
     * Opens a link from Reddit content the way a Reddit client should: media
     * in the viewer, reddit.com links in the app, anything else in the browser.
     * Relative links (`/r/foo`, `/u/bar`, plain `r/foo`) resolve to reddit.com.
     */
    fun openLink(href: String?) {
        if (href.isNullOrBlank()) return
        var raw = href.trim()
        if (raw.startsWith("/")) raw = "https://www.reddit.com$raw"
        else if (Regex("^(r|u|user)/").containsMatchIn(raw)) raw = "https://www.reddit.com/$raw"
        val uri = runCatching { Uri.parse(raw) }.getOrNull() ?: return
        if (isShareLink(uri)) {
            scope.launch { resolveShareLink(uri)?.let { openLink(it.toString()) } ?: openInBrowser(uri) }
            return
        }
        when {
            isVideoUrl(uri) -> openVideo(resolveVideoUrl(raw), externalUrl = raw)
            isImageUrl(uri) -> openImage(raw)
            else -> routeForRedditUrl(uri)?.let(::push) ?: openInBrowser(uri)
        }
    }

    /** A browser: an in-app Custom Tab when enabled in Settings, else the default browser app. */
    fun openInBrowser(uri: Uri) {
        try {
            if (app.settings.value.inAppBrowser) {
                val tab = CustomTabsIntent.Builder().setShowTitle(true).build()
                // Same loop guard as below: pin the tab to the browser for reddit links.
                externalViewIntent(context, uri).`package`?.let(tab.intent::setPackage)
                tab.launchUrl(context, uri)
            } else {
                context.startActivity(externalViewIntent(context, uri))
            }
        } catch (_: ActivityNotFoundException) {
            showSnackbar("No app can open this link.")
        }
    }

    fun openInBrowser(url: String) = openInBrowser(Uri.parse(url))

    /** The system share sheet for [text] (a URL, or "Title\nURL"). */
    fun share(text: String, subject: String? = null) {
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, text)
            if (subject != null) putExtra(Intent.EXTRA_SUBJECT, subject)
        }
        context.startActivity(Intent.createChooser(send, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    /** Shares a post as `Title` followed by the link, so recipients see what it is. */
    fun shareWithTitle(url: String, title: String) =
        share(if (title.isBlank()) url else "${title.trim()}\n$url", subject = title)

    fun showSnackbar(
        message: String,
        actionLabel: String? = null,
        duration: SnackbarDuration = SnackbarDuration.Short,
        onAction: (() -> Unit)? = null,
    ) {
        scope.launch {
            snackbar.currentSnackbarData?.dismiss()
            val r = snackbar.showSnackbar(message, actionLabel, withDismissAction = false, duration = duration)
            if (r == SnackbarResult.ActionPerformed) onAction?.invoke()
        }
    }

    /** A quick action (vote, save, subscribe…) didn't go through; its optimistic UI was rolled back. */
    fun showActionError(action: String, error: Throwable) {
        val anonymous = app.session.session?.anonymous == true
        showSnackbar(
            if (anonymous) "Sign in to $action — you're browsing without an account."
            else "Couldn't $action: ${friendlyError(error)}",
        )
    }
}
