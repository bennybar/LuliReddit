package com.bennybar.luli_for_reddit.feature.web

import android.annotation.SuppressLint
import android.graphics.Bitmap
import android.net.Uri
import android.webkit.CookieManager
import android.webkit.RenderProcessGoneDetail
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.OpenInNew
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.core.RedditConstants
import com.bennybar.luli_for_reddit.core.net.loadWebSessionCookies
import com.bennybar.luli_for_reddit.core.routeForRedditUrl
import com.bennybar.luli_for_reddit.feature.feed.BloomTopBar
import com.bennybar.luli_for_reddit.nav.LocalNavigator

/** Reddit pages Ilay opens signed in (website sign-in only). */
object RedditWeb {
    const val CHAT = "https://chat.reddit.com/"
    const val SETTINGS = "https://www.reddit.com/settings"
}

/** Whether the active account signed in with the website session (signed-in Reddit pages work). */
@Composable
fun rememberWebSignIn(): Boolean {
    val session by app.session.state.collectAsStateWithLifecycle()
    return produceState(false, session) { value = runCatching { app.secureStore.authMode() == "web" }.getOrDefault(false) }.value
}

/**
 * A reddit.com page signed in as you (website sign-in): notifications, chat,
 * a poll, Reddit's settings. Links to posts, profiles and communities open
 * in Ilay instead; other sites open in the browser. Its own WebView, so
 * Home's hidden page (and its place) is left alone.
 */
@SuppressLint("SetJavaScriptEnabled")
@Composable
fun RedditWebScreen(url: String, title: String) {
    val nav = LocalNavigator.current
    // null while loading the session into the cookie jar; false = not signed in on the web.
    val ready by produceState<Boolean?>(null) {
        val cookie = runCatching {
            if (app.secureStore.authMode() == "web") app.secureStore.webCookie() else null
        }.getOrNull()
        if (cookie.isNullOrEmpty()) value = false
        else {
            loadWebSessionCookies(cookie)
            value = true
        }
    }
    var view by remember { mutableStateOf<WebView?>(null) }
    var progress by remember { mutableIntStateOf(0) }
    var canGoBack by remember { mutableStateOf(false) }
    var crashed by remember { mutableStateOf(false) }
    val startRoute = remember(url) { routeForRedditUrl(Uri.parse(url)) }
    val navigator by rememberUpdatedState(nav)

    BackHandler(enabled = canGoBack) { view?.goBack() }
    DisposableEffect(Unit) { onDispose { view?.destroy() } }

    // A post / profile / community link opens natively (not the page you came for).
    fun openNatively(uri: Uri): Boolean {
        val route = routeForRedditUrl(uri) ?: return false
        if (route == startRoute) return false
        navigator.push(route)
        return true
    }

    fun isReddit(uri: Uri): Boolean {
        val host = uri.host?.lowercase() ?: return true
        return host == "reddit.com" || host.endsWith(".reddit.com") || host.endsWith(".redditmedia.com") ||
            host.endsWith(".redditstatic.com") || host == "redd.it"
    }

    Scaffold(
        topBar = {
            BloomTopBar(title, actions = {
                IconButton(onClick = { view?.reload() }) { Icon(Icons.Rounded.Refresh, "Reload") }
                IconButton(onClick = { nav.openInBrowser(view?.url ?: url) }) { Icon(Icons.AutoMirrored.Rounded.OpenInNew, "Open in browser") }
            })
        },
        containerColor = MaterialTheme.colorScheme.surface,
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            when {
                ready == null -> CircularProgressIndicator(Modifier.align(Alignment.Center))
                ready == false || crashed -> Column(
                    Modifier.align(Alignment.Center).padding(32.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text(
                        if (crashed) "The page stopped working."
                        else "This page needs the website sign-in (Settings → Login method).",
                        textAlign = TextAlign.Center,
                    )
                    Spacer(Modifier.height(12.dp))
                    Button(onClick = { nav.openInBrowser(url) }) { Text("Open in browser") }
                }
                else -> AndroidView(
                    factory = { ctx ->
                        WebView(ctx).apply {
                            settings.javaScriptEnabled = true
                            settings.domStorageEnabled = true
                            CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)
                            settings.userAgentString = RedditConstants.WEB_USER_AGENT
                            webChromeClient = object : WebChromeClient() {
                                override fun onProgressChanged(view: WebView, newProgress: Int) {
                                    progress = newProgress
                                }
                            }
                            webViewClient = object : WebViewClient() {
                                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                                    val u = request.url
                                    if (!request.isForMainFrame) return false
                                    if (openNatively(u)) return true
                                    if (u.scheme == "http" || u.scheme == "https") {
                                        if (isReddit(u)) return false
                                        navigator.openInBrowser(u)
                                    }
                                    return true // intent:, mailto: and other app links
                                }

                                // Reddit sizes Chat to 100dvh, which this WebView reports as 0 (a blank
                                // page); and its "Skip to …" links show up as a stuck pill.
                                override fun onPageFinished(view: WebView, url: String?) {
                                    view.evaluateJavascript(FIX_CSS, null)
                                }

                                override fun onPageStarted(view: WebView, url: String?, favicon: Bitmap?) {
                                    canGoBack = view.canGoBack()
                                }

                                // Reddit's pages switch "pages" in-place (no load to intercept):
                                // catch a move to a post the same way, and step back.
                                override fun doUpdateVisitedHistory(view: WebView, url: String?, isReload: Boolean) {
                                    canGoBack = view.canGoBack()
                                    if (isReload || url == null) return
                                    if (openNatively(Uri.parse(url)) && view.canGoBack()) view.goBack()
                                }

                                // The renderer died: drop the page rather than take Ilay down with it.
                                override fun onRenderProcessGone(v: WebView, detail: RenderProcessGoneDetail): Boolean {
                                    if (view === v) view = null
                                    crashed = true
                                    v.destroy()
                                    return true
                                }
                            }
                            loadUrl(url)
                            view = this
                        }
                    },
                    modifier = Modifier.fillMaxSize(),
                )
            }
            if (ready == true && !crashed && progress in 1..99) {
                LinearProgressIndicator(progress = { progress / 100f }, modifier = Modifier.fillMaxWidth().align(Alignment.TopCenter))
            }
        }
    }
}

private const val FIX_CSS = """(function(){if(document.getElementById('ilay-fix'))return;var s=document.createElement('style');s.id='ilay-fix';s.textContent='reddit-chat-fullscreen{height:auto!important}a[href="#main-content"],a[href="#main-right-content"]{display:none!important}';document.head.appendChild(s)})()"""
