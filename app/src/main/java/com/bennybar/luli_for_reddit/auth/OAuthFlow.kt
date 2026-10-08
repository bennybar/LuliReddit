package com.bennybar.luli_for_reddit.auth

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.browser.auth.AuthTabIntent
import androidx.browser.customtabs.CustomTabsClient
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.runtime.LaunchedEffect
import com.bennybar.luli_for_reddit.IlayActivity
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.ui.Overlays
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Browser-based OAuth, like flutter_web_auth_2: opens Reddit's authorize page
 * in an Auth Tab when the browser supports it — the browser hands the
 * redirect straight back to us (no "open with" chooser for `redreader://`
 * when RedReader is installed) and reports a real cancel when the tab is
 * closed. Otherwise a Custom Tab, where [OAuthRedirectActivity] receives the
 * `luli://` (or `redreader://`) redirect and coming back to the app without
 * one (the user closed the tab) cancels the login.
 */
object OAuthFlow {
    @Volatile private var pending: CompletableDeferred<Uri>? = null

    /** Custom Tab fallback only: the app went to the background since the launch. */
    @Volatile private var leftApp = false
    @Volatile private var customTab = false

    suspend fun authenticate(context: Context, url: Uri, ephemeral: Boolean): Uri {
        pending?.cancel()
        val deferred = CompletableDeferred<Uri>()
        pending = deferred
        leftApp = false
        customTab = false
        val scheme = url.getQueryParameter("redirect_uri")?.let { Uri.parse(it).scheme } ?: "luli"
        return try {
            withContext(Dispatchers.Main) {
                val browser = CustomTabsClient.getPackageName(context, null)
                if (browser != null && CustomTabsClient.isAuthTabSupported(context, browser) &&
                    app.navigatorOrNull != null
                ) {
                    coroutineScope {
                        val tab = launch { launchAuthTab(url, scheme, ephemeral, deferred) }
                        try {
                            deferred.await()
                        } finally {
                            tab.cancel()
                        }
                    }
                } else {
                    val tab = CustomTabsIntent.Builder()
                        .setShowTitle(true)
                        // Ephemeral = don't reuse the browser's Reddit cookies, so adding
                        // a second account can sign into a *different* account.
                        .apply { if (ephemeral) setEphemeralBrowsingEnabled(true) }
                        .build()
                    if (context !is Activity) tab.intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    customTab = true
                    tab.launchUrl(context, url)
                    deferred.await()
                }
            }
        } finally {
            if (pending === deferred) pending = null
        }
    }

    /** Runs the Auth Tab through a launcher registered in the app's overlay host. */
    private suspend fun launchAuthTab(url: Uri, scheme: String, ephemeral: Boolean, deferred: CompletableDeferred<Uri>) {
        Overlays.show<Unit> { done ->
            val launcher = rememberLauncherForActivityResult(AuthTabIntent.AuthenticateUserResultContract()) { r ->
                val uri = r.resultUri
                when {
                    r.resultCode == AuthTabIntent.RESULT_OK && uri != null -> deferred.complete(uri)
                    r.resultCode == AuthTabIntent.RESULT_CANCELED ->
                        deferred.completeExceptionally(CancellationException("User canceled authentication"))
                    else -> deferred.completeExceptionally(
                        IllegalStateException("Authentication failed with code: ${r.resultCode}"),
                    )
                }
                done(null)
            }
            LaunchedEffect(Unit) {
                try {
                    AuthTabIntent.Builder()
                        .apply { if (ephemeral) setEphemeralBrowsingEnabled(true) }
                        .build()
                        .launch(launcher, url, scheme)
                } catch (e: ActivityNotFoundException) {
                    deferred.completeExceptionally(IllegalStateException("No valid browser available for authentication."))
                    done(null)
                }
            }
        }
    }

    /** Called by [OAuthRedirectActivity]. */
    fun complete(uri: Uri) {
        pending?.complete(uri)
    }

    /** Called when the main activity pauses (the Custom Tab covered it). */
    fun onAppPaused() {
        if (pending != null && customTab) leftApp = true
    }

    /**
     * Called when the main activity resumes. If the app was left for the
     * Custom Tab and a login is still waiting a moment later (the redirect
     * lands first), the user came back without finishing it. Auth Tab logins
     * get a real result instead, so they're never guessed at.
     */
    fun onAppResumed() {
        val p = pending ?: return
        if (!leftApp) return
        leftApp = false
        Handler(Looper.getMainLooper()).postDelayed({
            if (pending === p && !p.isCompleted) p.completeExceptionally(CancellationException("cancelled"))
        }, 600)
    }
}

/** Receives the OAuth redirect and hands it to [OAuthFlow], then returns to the app. */
class OAuthRedirectActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        intent?.data?.let(OAuthFlow::complete)
        startActivity(
            Intent(this, IlayActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP),
        )
        finish()
    }
}
