package com.bennybar.luli_for_reddit.feature.foryou

import android.annotation.SuppressLint
import android.content.Context
import android.webkit.CookieManager
import android.webkit.WebView
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebViewClient
import com.bennybar.luli_for_reddit.AppContainer
import com.bennybar.luli_for_reddit.core.AppJson
import com.bennybar.luli_for_reddit.core.str
import com.bennybar.luli_for_reddit.model.Listing
import com.bennybar.luli_for_reddit.model.Post
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonArray
import kotlin.coroutines.resume

/**
 * Reads the user's real reddit.com Home feed — Reddit's own ranking and
 * recommendations — by loading the site in a hidden WebView with the user's
 * own website session, the way their browser would, and collecting the ids
 * of the posts the page shows, in order. Promoted posts are skipped.
 *
 * EXPERIMENTAL and opt-in (Settings → Reddit Home): this is not an official
 * API. It uses no Reddit app credentials and doesn't disguise itself — it is
 * a browser view of the user's own Home — but automated reading of the site
 * is against Reddit's User Agreement, and it breaks whenever Reddit changes
 * its page. Callers fall back to For You when it yields nothing.
 *
 * Every WebView call runs on the main thread.
 */
class RedditHomeLoader(private val context: Context) {
    private var view: WebView? = null
    private var cookies: String? = null // the session the hidden browser was opened with
    private val seen = HashSet<String>()

    /**
     * The next post ids: on a [restart] (first page / refresh) the first ~10
     * as soon as they render, otherwise up to [want] more. [cookieHeader] is
     * the active account's session.
     */
    suspend fun next(
        restart: Boolean,
        cookieHeader: String,
        want: Int = 25,
        onProgress: ((Int) -> Unit)? = null, // running count, for the UI
    ): List<String> = withContext(Dispatchers.Main) {
        if (view == null || cookieHeader != cookies) {
            // First use, or the account changed: (re)open with its session.
            disposeNow()
            seen.clear()
            open(cookieHeader)
        } else if (restart) {
            // Refresh: reload the page in the already-open browser instead of
            // tearing it down and re-setting every cookie. Mark the old document so
            // its posts aren't read as the new page's.
            seen.clear()
            eval("document.documentElement.setAttribute('data-ilay-old','1')")
            view?.loadUrl(HOME)
        }

        // A refresh hands back the first posts as soon as they render; the feed
        // pages for more on its own as you scroll.
        val target = if (restart) 10 else want
        // The page renders a first handful of posts with its HTML and fetches
        // the rest ~2s later: on a restart, hand the first wave back once it
        // stops growing (the next page call picks up the second wave).
        val settleMs = 350L
        val fresh = ArrayList<String>()
        val deadline = System.currentTimeMillis() + 15_000
        var lastGrowth = System.currentTimeMillis()
        var lastScroll = 0L
        while (System.currentTimeMillis() < deadline) {
            val ids = ids()
            var grew = false
            for (id in ids ?: emptyList()) {
                if (seen.add(id)) {
                    fresh.add(id)
                    grew = true
                }
            }
            if (grew) onProgress?.invoke(fresh.size)
            if (fresh.size >= target) break
            val now = System.currentTimeMillis()
            if (grew) lastGrowth = now
            if (restart && fresh.isNotEmpty() && now - lastGrowth >= settleMs) break
            // Nothing new for a while after posts had appeared: end of the feed.
            // (Before any appear, the page is still loading — keep waiting.)
            if (seen.isNotEmpty() && now - lastGrowth >= 6_000) break
            // Out of rendered posts: scroll so the page loads its next batch, at
            // most every 1.5s.
            if (ids != null && seen.isNotEmpty() && !grew && now - lastScroll >= 1_500) {
                lastScroll = now
                eval("window.scrollTo(0, document.body.scrollHeight);")
            }
            // Check often: posts appear well before the whole page has loaded.
            delay(100)
        }
        fresh
    }

    @SuppressLint("SetJavaScriptEnabled")
    private suspend fun open(cookieHeader: String) {
        cookies = cookieHeader
        // The WebView's cookie jar may hold a different account's session (the
        // last one that signed in through it): load the active one's.
        val jar = CookieManager.getInstance()
        suspend fun set(cookie: String) = suspendCancellableCoroutine { cont ->
            jar.setCookie(HOME, cookie) { if (cont.isActive) cont.resume(Unit) }
        }
        fun session(header: String?) = header?.split(';')
            ?.firstOrNull { it.trim().startsWith("reddit_session=") }?.trim()
        // Same account already in the jar: keep it as is. Wiping it also threw
        // away the cookies Reddit set when the page passed its browser check,
        // so every launch had to pass that check again (an extra page load).
        if (session(jar.getCookie(HOME)) != session(cookieHeader)) {
            for (part in jar.getCookie(HOME)?.split(';') ?: emptyList()) {
                val name = part.substringBefore('=').trim()
                if (name.isEmpty()) continue
                set("$name=; Domain=.reddit.com; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT")
                set("$name=; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT")
            }
            for (part in cookieHeader.split(';')) {
                val i = part.indexOf('=')
                if (i <= 0) continue
                val name = part.substring(0, i).trim()
                val value = part.substring(i + 1).trim()
                set("$name=$value; Domain=.reddit.com; Path=/; Secure")
            }
        }
        jar.flush()

        val v = WebView(context.applicationContext)
        v.settings.javaScriptEnabled = true
        v.settings.domStorageEnabled = true
        // Ilay loads its own images for the cards; the hidden page doesn't
        // need to download any, which gets its posts on screen sooner.
        v.settings.blockNetworkImage = true
        // Keep navigation inside the hidden view, and skip what the page
        // doesn't need to list its posts: autoplaying videos (dozens of
        // streams), fonts and telemetry. They competed with the feed request
        // for bandwidth and CPU. Reddit's own scripts and checks still load.
        v.webViewClient = object : WebViewClient() {
            override fun shouldInterceptRequest(view: WebView?, request: WebResourceRequest?): WebResourceResponse? {
                val url = request?.url ?: return null
                return if (isSkippable(url)) EMPTY_RESPONSE() else null
            }
        }
        // A real viewport, so the page lays out and "scroll to bottom" loads more.
        v.layout(0, 0, 1080, 2400)
        view = v
        // Don't wait for the whole page to load: next() reads posts as soon as
        // they're in the page.
        v.loadUrl(HOME)
    }

    private suspend fun eval(js: String): String? {
        val v = view ?: return null
        return suspendCancellableCoroutine { cont ->
            v.evaluateJavascript(js) { if (cont.isActive) cont.resume(it) }
        }
    }

    /** The post ids on the page now, or null while a reload is still showing the previous page. */
    private suspend fun ids(): List<String>? = try {
        val r = eval(READ_IDS)
        when {
            r == null || r == "null" -> null
            else -> (AppJson.parseToJsonElement(r) as? JsonArray)?.mapNotNull { it.str() } ?: emptyList()
        }
    } catch (e: kotlinx.coroutines.CancellationException) {
        throw e
    } catch (_: Exception) {
        emptyList() // page between documents
    }

    private fun disposeNow() {
        val v = view
        view = null
        cookies = null
        v?.stopLoading()
        v?.destroy()
    }

    suspend fun dispose() = withContext(Dispatchers.Main) { disposeNow() }

    companion object {
        private const val HOME = "https://www.reddit.com/"

        private val SKIP_HOSTS = setOf(
            "v.redd.it", "packaged-media.redd.it", "fonts.gstatic.com", "w3-reporting.reddit.com", "pi.reddit.com",
        )
        private val SKIP_EXT = listOf(".mp4", ".m3u8", ".mpd", ".m4s", ".ts", ".woff", ".woff2", ".ttf", ".gif", ".webm")
        private val SKIP_PATHS = listOf("/svc/shreddit/events", "/svc/shreddit/perfMetrics", "/svc/events/")

        /** Media, fonts and telemetry: not needed to read the feed's post ids. */
        internal fun isSkippable(url: android.net.Uri): Boolean {
            val host = url.host?.lowercase() ?: return false
            if (host in SKIP_HOSTS) return true
            val path = url.path?.lowercase() ?: return false
            if (SKIP_EXT.any { path.endsWith(it) }) return true
            return (host == "www.reddit.com" || host == "reddit.com") && SKIP_PATHS.any { path.startsWith(it) }
        }

        @Suppress("FunctionName")
        private fun EMPTY_RESPONSE() = WebResourceResponse("text/plain", "utf-8", 204, "No Content", emptyMap(), java.io.ByteArrayInputStream(ByteArray(0)))

        // The ids of the feed's posts, in page order. Reddit's site renders each
        // post as a <shreddit-post id="t3_…">; ads are separate elements. Returns
        // null while the previous document is still showing during a reload.
        private const val READ_IDS = """
(function () {
  if (document.documentElement.getAttribute('data-ilay-old')) return null;
  return Array.from(document.querySelectorAll('shreddit-post'))
    .filter(function (e) { return !e.hasAttribute('promoted'); })
    .map(function (e) { return e.getAttribute('id') || ''; })
    .filter(function (id) { return id.indexOf('t3_') === 0; });
})();
"""
    }
}

/** Experimental Reddit Home (headless WebView), falling back to For You. */
class RedditHomeEngine internal constructor(private val c: AppContainer, private val m: ForYouModule) {
    private val _progress = MutableStateFlow(0)

    /** Posts found so far while the first page loads (for the loading deck). */
    val progress: StateFlow<Int> = _progress

    /** A one-off notice for the feed ("Couldn't load Reddit Home, showing For You instead."). */
    val notice = MutableStateFlow<String?>(null)

    private var loader: RedditHomeLoader? = null

    // This load fell back to For You (Reddit Home couldn't be read); paging
    // continues with For You until the next refresh.
    @Volatile private var fellBack = false
    @Volatile private var homeEmpty = 0 // consecutive empty "more" batches from Reddit Home

    suspend fun page(after: String?, loaded: List<Post>): Listing<Post> {
        if (after == null) fellBack = false
        return if (fellBack) m.engine.page(after, loaded) else homePage(after, loaded)
    }

    private suspend fun homePage(after: String?, loaded: List<Post>): Listing<Post> {
        val firstPage = after == null
        try {
            val store = c.secureStore
            if (store.authMode() != "web") throw IllegalStateException("Reddit Home needs website sign-in")
            val l = loader ?: RedditHomeLoader(c.context).also { loader = it }
            if (firstPage) _progress.value = 0
            val ids = l.next(
                restart = firstPage,
                cookieHeader = store.webCookie() ?: "",
                onProgress = if (firstPage) { n -> _progress.value = n } else null,
            )
            if (ids.isEmpty()) {
                if (firstPage) throw IllegalStateException("No posts found on Reddit Home")
                // One empty batch can just be the page still setting up its "load
                // more"; only two in a row end the feed.
                return Listing(emptyList(), after = if (++homeEmpty >= 2) null else "home")
            }
            homeEmpty = 0
            val posts = c.repository.getPostsByIds(ids)
            val user = c.session.username
            if (firstPage && user.isNotEmpty()) {
                c.scope.launch(Dispatchers.IO) { saveForYouPage(c.context, user, posts, c.repository::rawPost, feed = "home") }
            }
            return Listing(posts, after = "home")
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: Exception) {
            if (!firstPage) throw e // a failed page keeps its cursor; retry
            // Reddit changed its page, the session expired, or the site refused:
            // show For You rather than an empty feed, and say so.
            fellBack = true
            notice.value = "Couldn't load Reddit Home, showing For You instead."
            return m.engine.page(null, loaded)
        }
    }

    /** The last Home page, minus posts opened since, while the fresh one loads. */
    suspend fun cachedFirstPage(): Listing<Post>? {
        val user = c.session.username
        if (user.isEmpty()) return null
        val posts = loadForYouPage(c.context, user, c.history.ids.value, feed = "home") ?: return null
        return Listing(posts, after = null)
    }

    /** Closes the hidden browser (the feed went away). */
    fun dispose() {
        val l = loader ?: return
        loader = null
        c.scope.launch { l.dispose() }
    }
}
