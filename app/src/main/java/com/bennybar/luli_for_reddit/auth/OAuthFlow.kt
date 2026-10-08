package com.bennybar.luli_for_reddit.auth

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.browser.customtabs.CustomTabsIntent
import com.bennybar.luli_for_reddit.MainActivity
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CancellationException

/**
 * Browser-based OAuth: opens Reddit's authorize page in a Custom Tab and
 * suspends until [OAuthRedirectActivity] receives the `luli://` (or
 * `redreader://`) redirect. Returning to the app without a redirect (the user
 * closed the tab) cancels the login, like flutter_web_auth_2 did.
 */
object OAuthFlow {
    @Volatile private var pending: CompletableDeferred<Uri>? = null
    @Volatile private var launchedAt = 0L

    suspend fun authenticate(context: Context, url: Uri, ephemeral: Boolean): Uri {
        pending?.cancel()
        val deferred = CompletableDeferred<Uri>()
        pending = deferred
        launchedAt = System.currentTimeMillis()
        val tab = CustomTabsIntent.Builder()
            .setShowTitle(true)
            // Ephemeral = don't reuse the browser's Reddit cookies, so adding
            // a second account can sign into a *different* account.
            .apply { if (ephemeral) setEphemeralBrowsingEnabled(true) }
            .build()
        if (context !is Activity) tab.intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        tab.launchUrl(context, url)
        return try {
            deferred.await()
        } finally {
            if (pending === deferred) pending = null
        }
    }

    /** Called by [OAuthRedirectActivity]. */
    fun complete(uri: Uri) {
        pending?.complete(uri)
    }

    /**
     * Called when the main activity resumes. If a login is still waiting a
     * moment later, the user came back without finishing it.
     */
    fun onAppResumed() {
        val p = pending ?: return
        if (System.currentTimeMillis() - launchedAt < 1000) return
        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
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
            Intent(this, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP),
        )
        finish()
    }
}
