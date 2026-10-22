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
import com.bennybar.luli_for_reddit.core.bool
import com.bennybar.luli_for_reddit.core.get
import com.bennybar.luli_for_reddit.core.isTrue
import com.bennybar.luli_for_reddit.core.net.loadWebSessionCookies
import com.bennybar.luli_for_reddit.core.str
import com.bennybar.luli_for_reddit.feature.foryou.RedditHomeLoader
import com.bennybar.luli_for_reddit.state.UserScoped
import com.bennybar.luli_for_reddit.state.userScopedKey
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.JsonElement
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
    /** Reddit's "clicked" flag when the page shows it (null: not known). */
    val clicked: Boolean? = null,
    /** Not opened yet: new since you last looked or unread on Reddit, and not opened in Ilay. */
    val unread: Boolean = false,
)

/**
 * Reddit's own notifications (website sign-in), shown natively in the Inbox.
 * Like Home, read from reddit.com in a hidden page. The page opens when you
 * go to the tab and closes soon after you leave it; while open it also reads
 * older notifications (one small request a batch) and tells Reddit which one
 * you opened. Kept a few minutes, so coming back costs nothing; no
 * background checks.
 */
class RedditNotifications(private val c: AppContainer) : UserScoped {
    sealed interface State {
        data object Loading : State
        data class Data(
            val items: List<RedditNotification>,
            val at: Long,
            val hasMore: Boolean = false,
            val loadingMore: Boolean = false,
        ) : State
        data class Failed(val signedOut: Boolean) : State
    }

    private val _state = MutableStateFlow<State?>(null)
    val state: StateFlow<State?> = _state
    private val lock = Mutex()
    @Volatile private var user = ""

    // The hidden page (main thread only) and the link to the next batch.
    private var view: WebView? = null
    private var nextUrl: String? = null
    private var closeJob: Job? = null

    /** Loads the list unless a recent copy is showing ([force]: pull to refresh). */
    fun refresh(force: Boolean = false) {
        closeJob?.cancel()
        val s = _state.value
        if (lock.isLocked) return
        if (!force && s is State.Data && System.currentTimeMillis() - s.at < FRESH_FOR) return
        c.scope.launch {
            lock.withLock {
                val forUser = c.session.username
                if (_state.value !is State.Data) _state.value = State.Loading
                val result = try {
                    if (c.secureStore.authMode() != "web") null
                    else c.secureStore.webCookie()?.takeIf { it.isNotEmpty() }?.let { open(it) }
                } catch (e: CancellationException) {
                    throw e
                } catch (_: Exception) {
                    PageResult(emptyList(), null, signedOut = false, ok = false)
                }
                if (forUser != c.session.username) return@withLock // account changed meanwhile
                _state.value = when {
                    result == null -> State.Failed(signedOut = true)
                    result.ok -> {
                        nextUrl = result.next
                        State.Data(mark(result.items), System.currentTimeMillis(), hasMore = result.next != null)
                    }
                    // A failed refresh keeps the list you had.
                    _state.value is State.Data -> _state.value
                    else -> State.Failed(result.signedOut)
                }
            }
        }
    }

    /** The next batch of older notifications, read through the open page. */
    fun loadMore() {
        val s = _state.value as? State.Data ?: return
        if (!s.hasMore || s.loadingMore || lock.isLocked) return
        _state.value = s.copy(loadingMore = true)
        c.scope.launch {
            lock.withLock {
                val url = nextUrl
                val more = if (url == null) null else withContext(Dispatchers.Main) { fetchMore(url) }
                val known = (_state.value as? State.Data)?.items?.mapTo(HashSet()) { it.id }.orEmpty()
                val added = more?.items?.filter { it.id !in known }?.let(::mark).orEmpty()
                nextUrl = more?.next
                _state.update { cur ->
                    if (cur !is State.Data) cur
                    else cur.copy(items = cur.items + added, hasMore = more?.next != null && added.isNotEmpty(), loadingMore = false)
                }
            }
        }
    }

    /**
     * You opened [n]: it stops showing as unread here, and the open page
     * clicks it too, which is how Reddit learns it was opened (Reddit's page
     * then moves to the post, so it steps back to the list).
     */
    fun opened(n: RedditNotification) {
        remember(OPENED, listOf(n.id))
        _state.update { s -> if (s is State.Data) s.copy(items = s.items.map { if (it.id == n.id) it.copy(unread = false) else it }) else s }
        c.scope.launch(Dispatchers.Main) {
            val v = view ?: return@launch
            clickItem(v, n.id)
        }
    }

    // Inbox items marked read in Ilay, waiting to be marked on Reddit too.
    private val toMark = LinkedHashSet<String>()
    private var markAll = false
    private var markJob: Job? = null

    /**
     * A reply or mention (comment [commentId]) was read in Ilay's Inbox:
     * Reddit's notification for it is a separate list, so mark it there too
     * (website sign-in only). Batched: reads close together share one page load.
     */
    fun markReadOnReddit(commentId: String) = queueMark { toMark.add(commentId) }

    /** Inbox → Mark all read: Reddit's "Mark all as read" on its notification list too. */
    fun markAllReadOnReddit() = queueMark { markAll = true }

    private fun queueMark(add: () -> Unit) {
        synchronized(toMark) { add() }
        markJob?.cancel()
        markJob = c.scope.launch {
            delay(2_000)
            lock.withLock {
                val (ids, all) = synchronized(toMark) {
                    val r = toMark.toList() to markAll
                    toMark.clear(); markAll = false
                    r
                }
                if (ids.isEmpty() && !all) return@withLock
                if (c.secureStore.authMode() != "web") return@withLock
                val cookie = c.secureStore.webCookie()?.takeIf { it.isNotEmpty() } ?: return@withLock
                withContext(Dispatchers.Main) {
                    closeJob?.cancel()
                    if (view == null) {
                        val r = runCatching { open(cookie) }.getOrNull() ?: return@withContext
                        if (r.ok) {
                            nextUrl = r.next
                            _state.value = State.Data(mark(r.items), System.currentTimeMillis(), hasMore = r.next != null)
                        }
                    }
                    val v = view ?: return@withContext
                    if (all) {
                        eval(v, "(function(){var b=document.querySelector('mark-all-messages-read button');if(b)b.click();return !!b})()")
                        delay(1_500)
                        _state.update { s -> if (s is State.Data) s.copy(items = s.items.map { it.copy(unread = false) }) else s }
                    } else {
                        val opened = ArrayList<String>()
                        for (id in ids) {
                            val n = (_state.value as? State.Data)?.items?.firstOrNull { it.link?.contains("/$id/") == true } ?: continue
                            opened += n.id
                            clickItem(v, n.id)
                        }
                        if (opened.isNotEmpty()) {
                            remember(OPENED, opened)
                            _state.update { s -> if (s is State.Data) s.copy(items = s.items.map { if (it.id in opened) it.copy(unread = false) else it }) else s }
                        }
                    }
                }
            }
            // Reading replies one after another: the next one reuses the page.
            release(after = 60_000)
        }
    }

    // Clicks one notification in the page (how Reddit records it as opened),
    // then steps back to the list, which Reddit's page moved away from.
    private suspend fun clickItem(v: WebView, notificationId: String) {
        val id = notificationId.filter { it.isLetterOrDigit() || it == '-' }
        val clicked = eval(v, "(function(){var e=document.querySelector('notification-item[notification-id=\"$id\"]');var a=e&&e.querySelector('a[href]');if(a)a.click();return !!a})()")
        if (clicked != "true") return
        delay(2_000)
        if (view === v && v.canGoBack()) v.goBack()
        // Wait for the list to be back before the next click.
        repeat(10) {
            delay(500)
            if (eval(v, "document.querySelectorAll('notification-item').length") ?.toIntOrNull()?.let { it > 0 } == true) return
        }
    }

    /** Leaving the tab: the page closes shortly after (coming straight back keeps it). */
    fun release(after: Long = 10_000) {
        closeJob?.cancel()
        closeJob = c.scope.launch(Dispatchers.Main) {
            delay(after)
            closeView()
        }
    }

    private fun closeView() {
        view?.let { it.stopLoading(); it.destroy() }
        view = null
        nextUrl = null
        // No page, no next batch: "Older notifications on reddit.com" stands in.
        _state.update { s -> if (s is State.Data) s.copy(hasMore = false, loadingMore = false) else s }
    }

    // Unread: new since last time (not among the stored "seen" ids), or
    // Reddit says it wasn't clicked; either way, not once opened in Ilay.
    private fun mark(items: List<RedditNotification>): List<RedditNotification> {
        val seen = recall(SEEN)
        val opened = recall(OPENED)
        val firstLook = seen.isEmpty()
        val out = items.map { n -> n.copy(unread = n.id !in opened && ((!firstLook && n.id !in seen) || n.clicked == false)) }
        remember(SEEN, items.map { it.id })
        return out
    }

    private fun recall(base: String): Set<String> =
        c.prefs.getString(userScopedKey(c.prefs, c.session.username, base))?.split(',')?.filter { it.isNotEmpty() }?.toSet().orEmpty()

    private fun remember(base: String, ids: List<String>) {
        val key = userScopedKey(c.prefs, c.session.username, base)
        val all = (ids + c.prefs.getString(key)?.split(',').orEmpty()).filter { it.isNotEmpty() }.distinct().take(MAX_IDS)
        c.prefs.setString(key, all.joinToString(","))
    }

    private class PageResult(val items: List<RedditNotification>, val next: String?, val signedOut: Boolean, val ok: Boolean)

    private suspend fun eval(v: WebView, js: String): String? = withTimeoutOrNull(2_000) {
        suspendCancellableCoroutine<String?> { cont -> v.evaluateJavascript(js) { if (cont.isActive) cont.resume(it) } }
    }

    // evaluateJavascript returns the script's string result JSON-quoted.
    private fun unquote(raw: String?): JsonElement? =
        runCatching { AppJson.parseToJsonElement(AppJson.parseToJsonElement(raw ?: return null).str() ?: return null) }.getOrNull()

    @SuppressLint("SetJavaScriptEnabled")
    private suspend fun open(cookie: String): PageResult = withContext(Dispatchers.Main) {
        closeView()
        loadWebSessionCookies(cookie)
        val v = WebView(c.context.applicationContext)
        view = v
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

            // Stay on the list: no full page loads elsewhere.
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean = true

            override fun onRenderProcessGone(gone: WebView, detail: RenderProcessGoneDetail): Boolean {
                if (view === gone) view = null
                gone.destroy()
                return true
            }
        }
        v.layout(0, 0, 1080, 2400)
        v.loadUrl(URL)
        val deadline = System.currentTimeMillis() + TIMEOUT
        var emptySince = 0L
        while (System.currentTimeMillis() < deadline && view === v) {
            delay(500)
            val json = unquote(eval(v, READ)) ?: continue
            if (json["login"].isTrue()) {
                closeView()
                return@withContext PageResult(emptyList(), null, signedOut = true, ok = false)
            }
            val items = parse(json)
            if (items.isNotEmpty()) {
                // Reddit's read flags appear once the page has drawn its menus.
                delay(1_200)
                val again = unquote(eval(v, READ))?.let { parse(it) }?.takeIf { it.size >= items.size } ?: items
                return@withContext PageResult(again, json["next"].str(), signedOut = false, ok = true)
            }
            // The page is up but lists nothing: give it a moment, then it's really empty.
            if (json["ready"].isTrue()) {
                if (emptySince == 0L) emptySince = System.currentTimeMillis()
                else if (System.currentTimeMillis() - emptySince > 3_000) return@withContext PageResult(emptyList(), null, false, ok = true)
            }
        }
        closeView()
        PageResult(emptyList(), null, signedOut = false, ok = false)
    }

    private class More(val items: List<RedditNotification>, val next: String?)

    // Reddit's page loads older notifications from this link as you scroll;
    // fetched from inside the page (its sign-in) and read the same way.
    private suspend fun fetchMore(url: String): More? {
        val v = view ?: return null
        val safe = url.replace("\\", "").replace("'", "%27")
        eval(v, "window.__ilayMore=null;fetch('$safe',{credentials:'include'}).then(function(r){return r.text()}).then(function(t){var d=new DOMParser().parseFromString(t,'text/html');window.__ilayMore=JSON.stringify({items:ilayRead(d),next:ilayNext(d)})}).catch(function(){window.__ilayMore='{}'});true")
        repeat(30) {
            delay(400)
            if (view !== v) return null
            val json = unquote(eval(v, "window.__ilayMore")) ?: return@repeat
            return More(parse(json), json["next"].str())
        }
        return null
    }

    override fun onUserChanged(username: String) {
        if (username == user) return
        user = username
        _state.value = null
        c.scope.launch(Dispatchers.Main) { closeView() }
    }

    companion object {
        const val URL = "https://www.reddit.com/notifications"
        private const val FRESH_FOR = 3 * 60_000L
        private const val TIMEOUT = 25_000L
        private const val MAX_IDS = 400
        private const val SEEN = "redditNotifSeen"
        private const val OPENED = "redditNotifOpened"

        internal fun parse(json: JsonElement): List<RedditNotification> =
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
                    clicked = e["clicked"].bool(),
                )
            }.distinctBy { it.id }

        // Each <notification-item>: its link, title, body, time, avatar, and
        // Reddit's clicked flag (in the tracking data of its ⋯ menu, once the
        // page has drawn it); plus the link to the next, older batch.
        // Defines ilayRead / ilayNext on the page for fetchMore to reuse.
        private const val READ = """(function(){
window.ilayRead=function(root){var out=[];
root.querySelectorAll('notification-item').forEach(function(e){
  var a=e.querySelector('a[href]');
  var t=e.querySelector('[data-testid=title]');
  var b=e.querySelector('[data-testid=body] > .line-clamp-2');
  var ts=e.querySelector('faceplate-timeago');
  var img=e.querySelector('img');
  var clicked=null;
  try{var m=e.querySelector('notification-context-menu');var tr=m&&m.shadowRoot&&m.shadowRoot.querySelector('faceplate-tracker');
    var ctx=tr&&JSON.parse(tr.getAttribute('data-faceplate-tracking-context'));if(ctx&&ctx.inbox&&typeof ctx.inbox.is_clicked==='boolean')clicked=ctx.inbox.is_clicked;}catch(x){}
  out.push({id:e.getAttribute('notification-id'),type:e.getAttribute('message-type'),
    link:a?a.href:null,title:t?t.textContent.trim():'',body:b?b.textContent.trim():'',
    ts:ts?ts.getAttribute('ts'):null,avatar:img?img.getAttribute('src'):null,clicked:clicked});
});return out;};
window.ilayNext=function(root){var p=root.querySelector('faceplate-partial[src*="notifications-inbox-content"]');return p?p.getAttribute('src'):null;};
return JSON.stringify({login:location.pathname.indexOf('/login')===0||location.hostname.indexOf('accounts.')===0,
  ready:!!document.querySelector('mark-all-messages-read,mark-all-notifications-seen'),items:ilayRead(document),next:ilayNext(document)});
})()"""
    }
}
