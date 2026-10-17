package com.bennybar.luli_for_reddit.feature.inbox

import android.annotation.SuppressLint
import android.webkit.RenderProcessGoneDetail
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.runtime.Immutable
import com.bennybar.luli_for_reddit.AppContainer
import com.bennybar.luli_for_reddit.core.AppJson
import com.bennybar.luli_for_reddit.core.RedditConstants
import com.bennybar.luli_for_reddit.core.arr
import com.bennybar.luli_for_reddit.core.get
import com.bennybar.luli_for_reddit.core.isTrue
import com.bennybar.luli_for_reddit.core.net.loadWebSessionCookies
import com.bennybar.luli_for_reddit.core.str
import com.bennybar.luli_for_reddit.feature.foryou.RedditHomeLoader
import com.bennybar.luli_for_reddit.state.UserScoped
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.io.ByteArrayInputStream
import java.time.Instant
import kotlin.coroutines.resume

/** One entry of Reddit's own notification list (reddit.com/notifications). */
@Immutable
data class RedditNotification(
    val id: String,
    /** Reddit's message type, e.g. POST_REPLY, COMMENT_REPLY, UPVOTE_POST, USERNAME_MENTION. */
    val type: String,
    val title: String,
    val body: String,
    /** Where it goes (a post or comment link), opened in Ilay. */
    val link: String?,
    val at: Long,
    val avatar: String?,
)

/**
 * Reddit's own notifications (website sign-in), shown natively in the Inbox.
 * Like Home, read from reddit.com in a hidden page: it opens, the list is
 * read, and it closes again. Loaded only when you look at it, and kept for a
 * few minutes, so it costs one page load now and then (no background checks).
 */
class RedditNotifications(private val c: AppContainer) : UserScoped {
    sealed interface State {
        data object Loading : State
        data class Data(val items: List<RedditNotification>, val at: Long) : State
        data class Failed(val signedOut: Boolean) : State
    }

    private val _state = MutableStateFlow<State?>(null)
    val state: StateFlow<State?> = _state
    private val lock = Mutex()
    @Volatile private var user = ""

    /** Loads the list unless a recent copy is showing ([force]: pull to refresh). */
    fun refresh(force: Boolean = false) {
        val s = _state.value
        if (lock.isLocked) return
        if (!force && s is State.Data && System.currentTimeMillis() - s.at < FRESH_FOR) return
        c.scope.launch {
            lock.withLock {
                val forUser = c.session.username
                if (_state.value !is State.Data) _state.value = State.Loading
                val result = try {
                    if (c.secureStore.authMode() != "web") null
                    else c.secureStore.webCookie()?.takeIf { it.isNotEmpty() }?.let { read(it) }
                } catch (e: CancellationException) {
                    throw e
                } catch (_: Exception) {
                    PageResult(emptyList(), signedOut = false, ok = false)
                }
                if (forUser != c.session.username) return@withLock // account changed meanwhile
                _state.value = when {
                    result == null -> State.Failed(signedOut = true)
                    result.ok -> State.Data(result.items, System.currentTimeMillis())
                    // A failed refresh keeps the list you had.
                    _state.value is State.Data -> _state.value
                    else -> State.Failed(result.signedOut)
                }
            }
        }
    }

    private class PageResult(val items: List<RedditNotification>, val signedOut: Boolean, val ok: Boolean)

    @SuppressLint("SetJavaScriptEnabled")
    private suspend fun read(cookie: String): PageResult = withContext(Dispatchers.Main) {
        loadWebSessionCookies(cookie)
        val v = WebView(c.context.applicationContext)
        var gone = false
        try {
            v.settings.javaScriptEnabled = true
            v.settings.domStorageEnabled = true
            v.settings.userAgentString = RedditConstants.WEB_USER_AGENT
            // Only the list's text and links are read: no images, video or fonts.
            v.settings.blockNetworkImage = true
            v.webViewClient = object : WebViewClient() {
                override fun shouldInterceptRequest(view: WebView?, request: WebResourceRequest?): WebResourceResponse? {
                    val url = request?.url ?: return null
                    return if (RedditHomeLoader.isSkippable(url)) {
                        WebResourceResponse("text/plain", "utf-8", 204, "No Content", emptyMap(), ByteArrayInputStream(ByteArray(0)))
                    } else null
                }

                override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
                    gone = true
                    return true
                }
            }
            v.layout(0, 0, 1080, 2400)
            v.loadUrl(URL)
            val deadline = System.currentTimeMillis() + TIMEOUT
            var emptySince = 0L
            while (System.currentTimeMillis() < deadline && !gone) {
                delay(500)
                val raw = withTimeoutOrNull(2_000) {
                    suspendCancellableCoroutine<String?> { cont -> v.evaluateJavascript(READ) { if (cont.isActive) cont.resume(it) } }
                } ?: continue
                val json = runCatching { AppJson.parseToJsonElement(AppJson.parseToJsonElement(raw).str() ?: "null") }.getOrNull() ?: continue
                if (json["login"].isTrue()) return@withContext PageResult(emptyList(), signedOut = true, ok = false)
                val items = parse(json)
                if (items.isNotEmpty()) return@withContext PageResult(items, signedOut = false, ok = true)
                // The page is up but lists nothing: give it a moment, then it's really empty.
                if (json["ready"].isTrue()) {
                    if (emptySince == 0L) emptySince = System.currentTimeMillis()
                    else if (System.currentTimeMillis() - emptySince > 3_000) return@withContext PageResult(emptyList(), false, ok = true)
                }
            }
            PageResult(emptyList(), signedOut = false, ok = false)
        } finally {
            v.stopLoading()
            v.destroy()
        }
    }

    override fun onUserChanged(username: String) {
        if (username == user) return
        user = username
        _state.value = null
    }

    companion object {
        const val URL = "https://www.reddit.com/notifications"
        private const val FRESH_FOR = 3 * 60_000L
        private const val TIMEOUT = 25_000L

        internal fun parse(json: kotlinx.serialization.json.JsonElement): List<RedditNotification> =
            json["items"].arr().orEmpty().mapNotNull { e ->
                val id = e["id"].str() ?: return@mapNotNull null
                val title = e["title"].str().orEmpty()
                if (title.isEmpty()) return@mapNotNull null
                RedditNotification(
                    id = id,
                    type = e["type"].str().orEmpty(),
                    title = title,
                    body = e["body"].str().orEmpty(),
                    link = e["link"].str()?.takeIf { it.startsWith("http") },
                    at = e["ts"].str()?.let { runCatching { Instant.parse(it).toEpochMilli() }.getOrNull() } ?: 0L,
                    avatar = e["avatar"].str()?.takeIf { it.startsWith("http") },
                )
            }.distinctBy { it.id }

        // Each <notification-item>: its link, title, body, time and avatar.
        private const val READ = """(function(){
var out=[];
document.querySelectorAll('notification-item').forEach(function(e){
  var a=e.querySelector('a[href]');
  var t=e.querySelector('[data-testid=title]');
  var b=e.querySelector('[data-testid=body] > .line-clamp-2');
  var ts=e.querySelector('faceplate-timeago');
  var img=e.querySelector('img');
  out.push({id:e.getAttribute('notification-id'),type:e.getAttribute('message-type'),
    link:a?a.href:null,title:t?t.textContent.trim():'',body:b?b.textContent.trim():'',
    ts:ts?ts.getAttribute('ts'):null,avatar:img?img.getAttribute('src'):null});
});
return JSON.stringify({login:location.pathname.indexOf('/login')===0||location.hostname.indexOf('accounts.')===0,
  ready:!!document.querySelector('mark-all-messages-read,mark-all-notifications-seen'),items:out});
})()"""
    }
}
