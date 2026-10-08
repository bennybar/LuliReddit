package com.bennybar.luli_for_reddit.feature.auth

import android.annotation.SuppressLint
import android.webkit.CookieManager
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.auth.SessionState
import com.bennybar.luli_for_reddit.core.RedditConstants
import com.bennybar.luli_for_reddit.nav.LocalNavigator
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume

/**
 * A WebView that signs the user into reddit.com, captures the resulting
 * session cookies and logs in with them. This is the no-API-key "website
 * session" login — see docs/hydra-fallback.md. The user's password is only
 * ever entered into Reddit's own page inside the WebView.
 *
 * When an account is already signed in (adding another account), existing
 * cookies are wiped first — otherwise the session check finds the *current*
 * account's reddit_session straight away and adds that account again.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WebLoginScreen() {
    val nav = LocalNavigator.current
    val scope = rememberCoroutineScope()
    val clearFirst = remember { app.session.state.value is SessionState.LoggedIn }
    var ready by remember { mutableStateOf(!clearFirst) }
    var done by remember { mutableStateOf(false) }
    var signingIn by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        if (!clearFirst) return@LaunchedEffect
        suspendCancellableCoroutine { cont -> CookieManager.getInstance().removeAllCookies { cont.resume(Unit) } }
        ready = true
    }

    fun check() {
        if (done) return
        val header = CookieManager.getInstance().getCookie(RedditConstants.WEB_API_BASE) ?: return
        val cookies = header.split(';').map { it.trim() }
        val hasSession = cookies.any { it.startsWith("reddit_session=") && it.length > "reddit_session=".length }
        if (!hasSession) return
        done = true
        signingIn = true
        scope.launch {
            try {
                app.session.loginWithWebSession(cookies.joinToString("; "))
                // Signed out before: the root moves to Home by itself. Adding an
                // account: just close this screen.
                if (clearFirst) nav.pop()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                nav.showSnackbar((e.message ?: e.toString()).removePrefix("Exception: "))
                nav.pop()
            }
        }
    }

    // The session cookie can appear without a page load finishing (XHR login).
    LaunchedEffect(ready) {
        if (!ready) return@LaunchedEffect
        while (!done) {
            check()
            delay(700)
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Sign in to Reddit") },
                navigationIcon = { IconButton(onClick = { nav.pop() }) { Icon(Icons.Rounded.Close, "Close") } },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.surface),
            )
        },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            if (ready) {
                AndroidView(
                    modifier = Modifier.fillMaxSize(),
                    factory = { ctx ->
                        @SuppressLint("SetJavaScriptEnabled")
                        val web = WebView(ctx).apply {
                            settings.javaScriptEnabled = true
                            settings.domStorageEnabled = true
                            settings.userAgentString = RedditConstants.WEB_USER_AGENT
                            if (clearFirst) {
                                clearCache(true)
                                settings.cacheMode = WebSettings.LOAD_NO_CACHE
                            }
                            CookieManager.getInstance().setAcceptCookie(true)
                            CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)
                            webViewClient = object : WebViewClient() {
                                override fun onPageFinished(view: WebView?, url: String?) = check()
                            }
                            loadUrl(RedditConstants.WEB_LOGIN_URL)
                        }
                        web
                    },
                    onRelease = { it.destroy() },
                )
            }
            if (!ready || signingIn) CircularProgressIndicator(Modifier.align(Alignment.Center))
        }
    }
}
