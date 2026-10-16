package com.bennybar.luli_for_reddit.feature.foryou

import com.bennybar.luli_for_reddit.core.Analytics
import android.annotation.SuppressLint
import android.content.Context
import android.os.Looper
import android.webkit.CookieManager
import android.webkit.WebView
import android.webkit.RenderProcessGoneDetail
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebViewClient
import com.bennybar.luli_for_reddit.AppContainer
import com.bennybar.luli_for_reddit.core.AppJson
import com.bennybar.luli_for_reddit.core.arr
import com.bennybar.luli_for_reddit.core.get
import com.bennybar.luli_for_reddit.core.isTrue
import com.bennybar.luli_for_reddit.core.str
import com.bennybar.luli_for_reddit.model.Listing
import com.bennybar.luli_for_reddit.model.Post
import com.bennybar.luli_for_reddit.model.PostType
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.android.awaitFrame
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.JsonElement
import kotlin.coroutines.resume

/** The page shows the logged-out site: the website session has expired. */
class HomeSignedOutException : Exception("Your Reddit website sign-in has expired")

/**
 * One post as reddit.com's Home page shows it — enough for a feed card
 * straight away (the full post is fetched in the background).
 */
data class PagePost(
    val id: String, // t3_…
    val title: String,
    val subreddit: String,
    val subredditIcon: String?,
    val author: String,
    val score: Int,
    val comments: Int,
    val createdUtc: Long,
    val type: String, // text | image | video | gallery | link | crosspost | …
    val permalink: String,
    val href: String,
    val domain: String,
    val image: String?,
    val body: String,
    val flair: String?,
    val nsfw: Boolean,
    val spoiler: Boolean,
    /** Reddit's "why you're seeing this", when it shows one. */
    val reason: String?,
    /** Reddit offers "Show fewer posts like this" for it (recommended posts). */
    val canShowFewer: Boolean,
) {
    /** A feed card's worth of [Post]: replaced by the full post once fetched. */
    fun toPost(): Post {
        val bare = id.removePrefix("t3_")
        val sub = subreddit.removePrefix("r/")
        val vreddit = android.net.Uri.parse(href).takeIf { it.host == "v.redd.it" && it.pathSegments.isNotEmpty() }
        val postType = when (type) {
            "text" -> PostType.SELF
            "image" -> PostType.IMAGE
            "gallery" -> PostType.GALLERY
            "video" -> PostType.VIDEO
            "link" -> PostType.LINK
            else -> if (image != null) PostType.IMAGE else PostType.SELF
        }
        return Post(
            id = bare,
            fullname = id,
            title = title,
            subreddit = sub,
            subredditPrefixed = "r/$sub",
            subredditIcon = subredditIcon,
            author = author,
            score = score,
            numComments = comments,
            upvoteRatio = 0.0,
            createdUtc = createdUtc,
            permalink = permalink,
            url = href.ifEmpty { "https://www.reddit.com$permalink" },
            domain = domain,
            type = postType,
            isSelf = postType == PostType.SELF,
            selftext = body,
            over18 = nsfw,
            spoiler = spoiler,
            linkFlairText = flair,
            feedReason = reason,
            previewUrl = image,
            previewMedUrl = image,
            hlsUrl = vreddit?.let { "https://v.redd.it/${it.pathSegments.first()}/HLSPlaylist.m3u8" },
        )
    }

    companion object {
        internal fun parse(o: JsonElement?): PagePost? {
            val id = o["id"].str()?.takeIf { it.startsWith("t3_") } ?: return null
            return PagePost(
                id = id,
                title = o["title"].str().orEmpty().trim(),
                subreddit = o["sub"].str().orEmpty(),
                subredditIcon = o["subIcon"].str()?.ifEmpty { null },
                author = o["author"].str().orEmpty().ifEmpty { "[deleted]" },
                score = o["score"].str()?.toIntOrNull() ?: 0,
                comments = o["comments"].str()?.toIntOrNull() ?: 0,
                createdUtc = runCatching { java.time.OffsetDateTime.parse(o["created"].str().orEmpty().replace("+0000", "+00:00")).toInstant().toEpochMilli() }.getOrDefault(0L),
                type = o["type"].str().orEmpty(),
                permalink = o["permalink"].str().orEmpty(),
                href = o["href"].str().orEmpty(),
                domain = o["domain"].str().orEmpty(),
                image = o["img"].str()?.ifEmpty { null },
                body = o["body"].str().orEmpty(),
                flair = o["flair"].str()?.ifEmpty { null },
                nsfw = o["nsfw"].isTrue(),
                spoiler = o["spoiler"].isTrue(),
                reason = o["reason"].str()?.ifEmpty { null },
                canShowFewer = o["fewer"].isTrue(),
            )
        }
    }
}

/**
 * Reads the user's real reddit.com Home feed — Reddit's own ranking and
 * recommendations — by loading the site in a hidden WebView with the user's
 * own website session, the way their browser would, and reading the posts the
 * page shows, in order. Promoted posts are skipped.
 *
 * EXPERIMENTAL and opt-in (Settings → Reddit Home): this is not an official
 * API. It uses no Reddit app credentials and doesn't disguise itself — it is
 * a browser view of the user's own Home — but automated reading of the site
 * is against Reddit's User Agreement, and it breaks whenever Reddit changes
 * its page. Callers fall back to For You when it yields nothing.
 *
 * Every WebView call runs on the main thread, one at a time ([busy]).
 */
class RedditHomeLoader(private val context: Context) {
    private var view: WebView? = null
    private var cookies: String? = null // the session the hidden browser was opened with
    private val seen = HashSet<String>()
    private val busy = Mutex()

    /**
     * Ids (bare) of the posts on the hidden page now that Reddit offers "Show
     * fewer" for. Only those can take it: a card from an earlier page (one
     * saved before the app was closed) isn't on this one.
     */
    @Volatile var showFewerIds: Set<String> = emptySet()
        private set

    /**
     * The next posts: on a [restart] (first page / refresh) the first ~10 as
     * soon as they render, otherwise up to [want] more. [cookieHeader] is the
     * active account's session. Throws [HomeSignedOutException] when the page
     * shows the logged-out site.
     */
    suspend fun next(
        restart: Boolean,
        cookieHeader: String,
        want: Int = 25,
        onProgress: ((Int) -> Unit)? = null, // running count, for the UI
    ): List<PagePost> = withContext(Dispatchers.Main) {
        busy.withLock {
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
            val fresh = ArrayList<PagePost>()
            val deadline = System.currentTimeMillis() + 15_000
            var lastGrowth = System.currentTimeMillis()
            var lastScroll = 0L
            while (System.currentTimeMillis() < deadline) {
                val page = read()
                if (page?.signedOut == true) throw HomeSignedOutException()
                if (page != null) showFewerIds = page.posts.filter { it.canShowFewer }.mapTo(HashSet()) { it.id.removePrefix("t3_") }
                var grew = false
                for (p in page?.posts ?: emptyList()) {
                    if (seen.add(p.id)) {
                        fresh.add(p)
                        grew = true
                    }
                }
                if (grew) onProgress?.invoke(fresh.size)
                if (fresh.size >= target) break
                val now = System.currentTimeMillis()
                if (grew) lastGrowth = now
                // Nothing new for a while after posts had appeared: end of the feed.
                // (Before any appear, the page is still loading — keep waiting.) Once
                // a batch has been flowing, a shorter quiet spell is enough.
                val quiet = if (fresh.isNotEmpty()) 4_000 else 6_000
                if (seen.isNotEmpty() && now - lastGrowth >= quiet) break
                // Out of rendered posts: scroll so the page loads its next batch, at
                // most every second.
                if (page != null && seen.isNotEmpty() && !grew && now - lastScroll >= 1_000) {
                    lastScroll = now
                    eval("window.scrollTo(0, document.body.scrollHeight);")
                }
                // Check often: posts appear well before the whole page has loaded.
                delay(100)
            }
            fresh
        }
    }

    /**
     * Scrolls the hidden page to [postId] (what the user is looking at in Ilay),
     * so Reddit's own "seen" tracking follows what was actually on screen.
     * Skipped while a page load is running.
     */
    suspend fun scrollTo(postId: String) = withContext(Dispatchers.Main) {
        if (!busy.tryLock()) return@withContext
        try {
            eval("(function(){var e=document.getElementById('$postId');if(e)e.scrollIntoView({block:'center'});})()")
        } finally {
            busy.unlock()
        }
    }

    /**
     * Picks "Show fewer posts like this" in the post's own ⋯ menu on the hidden
     * page — the same action as on reddit.com. False if it isn't offered there.
     */
    suspend fun showFewer(postId: String): Boolean = withContext(Dispatchers.Main) {
        busy.withLock {
            // The menu's items may only be rendered once it has been opened:
            // open it (off screen, in the hidden page) and look again.
            repeat(4) { attempt ->
                val r = eval(
                    """
                    (function(){
                      var p = document.getElementById('$postId');
                      var m = p && p.querySelector('shreddit-post-overflow-menu');
                      if (!m) return 'gone';
                      var li = m.shadowRoot && m.shadowRoot.querySelector('#post-overflow-showFewer');
                      if (!li) {
                        var b = (m.shadowRoot && m.shadowRoot.querySelector('button')) || m.querySelector('button');
                        if (b && $attempt === 0) b.click();
                        return 'none';
                      }
                      (li.querySelector('[role="menuitem"]') || li).click();
                      return 'ok';
                    })()
                    """.trimIndent(),
                )
                if (r?.contains("ok") == true) return@withLock true
                if (r?.contains("gone") == true) return@withLock false
                delay(400)
            }
            false
        }
    }

    /** The app went to the background: stop the hidden page's timers and work. */
    fun pause() {
        view?.onPause()
        view?.pauseTimers()
    }

    fun resume() {
        view?.resumeTimers()
        view?.onResume()
    }

    @SuppressLint("SetJavaScriptEnabled")
    private suspend fun open(cookieHeader: String) {
        cookies = cookieHeader
        // Creating the first WebView starts Chromium on the main thread (100–300ms):
        // let the app's first frame and the loading deck draw before that.
        awaitFrame()
        suspendCancellableCoroutine { cont ->
            Looper.myQueue().addIdleHandler { if (cont.isActive) cont.resume(Unit); false }
        }
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
        // streams) and fonts. Reddit's own scripts, checks and events load.
        v.webViewClient = object : WebViewClient() {
            override fun shouldInterceptRequest(view: WebView?, request: WebResourceRequest?): WebResourceResponse? {
                val url = request?.url ?: return null
                return if (isSkippable(url)) EMPTY_RESPONSE() else null
            }

            // The page's renderer died (crashed, or killed for memory). Unhandled,
            // Android kills Ilay with it; instead drop this page, and the next
            // Home load opens a new one.
            override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
                if (this@RedditHomeLoader.view === view) {
                    this@RedditHomeLoader.view = null
                    cookies = null
                }
                view.destroy()
                return true
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
        // While the page is reloading, the WebView can drop a script's result
        // callback entirely; without a timeout that hung a refresh forever on
        // "Opening your Home…" (the deadline check never ran again).
        return withTimeoutOrNull(2_000) {
            suspendCancellableCoroutine { cont ->
                v.evaluateJavascript(js) { if (cont.isActive) cont.resume(it) }
            }
        }
    }

    private class PageRead(val posts: List<PagePost>, val signedOut: Boolean)

    /** The posts on the page now, or null while a reload is still showing the previous page. */
    private suspend fun read(): PageRead? = try {
        val r = eval(READ_POSTS)
        if (r == null || r == "null") null
        else {
            // evaluateJavascript returns the script's string result JSON-quoted.
            val json = AppJson.parseToJsonElement(AppJson.parseToJsonElement(r).str() ?: "null")
            PageRead(
                posts = json["posts"].arr()?.mapNotNull { PagePost.parse(it) } ?: emptyList(),
                signedOut = json["signedOut"].isTrue(),
            )
        }
    } catch (e: kotlinx.coroutines.CancellationException) {
        throw e
    } catch (_: Exception) {
        PageRead(emptyList(), false) // page between documents
    }

    private fun disposeNow() {
        val v = view
        view = null
        cookies = null
        showFewerIds = emptySet()
        v?.stopLoading()
        v?.destroy()
    }

    suspend fun dispose() = withContext(Dispatchers.Main) { busy.withLock { disposeNow() } }

    companion object {
        private const val HOME = "https://www.reddit.com/"

        // Only downloads that never change what the feed shows: autoplaying
        // video and fonts. Reddit's own events must go through — Home learns
        // from them which posts were seen, and without them a refresh kept
        // serving the same feed.
        private val SKIP_HOSTS = setOf("v.redd.it", "packaged-media.redd.it", "fonts.gstatic.com")
        private val SKIP_EXT = listOf(".mp4", ".m3u8", ".mpd", ".m4s", ".ts", ".woff", ".woff2", ".ttf", ".webm")

        /** Video and fonts: not needed to read the feed's posts. */
        internal fun isSkippable(url: android.net.Uri): Boolean {
            val host = url.host?.lowercase() ?: return false
            if (host in SKIP_HOSTS) return true
            val path = url.path?.lowercase() ?: return false
            return SKIP_EXT.any { path.endsWith(it) }
        }

        @Suppress("FunctionName")
        private fun EMPTY_RESPONSE() = WebResourceResponse("text/plain", "utf-8", 204, "No Content", emptyMap(), java.io.ByteArrayInputStream(ByteArray(0)))

        // The feed's posts, in page order, as cards: Reddit's site renders each
        // post as a <shreddit-post id="t3_…" post-title=… score=…> with its body
        // snippet, media preview and flair in named slots, and the
        // recommendation reason / "Show fewer" option on its ⋯ menu. Ads are
        // separate elements. signedOut: the page is the logged-out site (the
        // session expired). Returns null while the previous document is still
        // showing during a reload. (Element and attribute names as of 2026-10.)
        private const val READ_POSTS = """
(function () {
  if (document.documentElement.getAttribute('data-ilay-old')) return null;
  var app = document.querySelector('shreddit-app');
  var signedOut = !!app && app.getAttribute('user-logged-in') !== 'true';
  var posts = Array.from(document.querySelectorAll('shreddit-post'))
    .filter(function (e) { return !e.hasAttribute('promoted') && (e.id || '').indexOf('t3_') === 0; })
    .map(function (e) {
      function slot(n) { return e.querySelector('[slot="' + n + '"]'); }
      var media = slot('post-media-container');
      var img = media && media.querySelector('img');
      var body = slot('text-body');
      var flair = slot('post-flair');
      var credit = slot('credit-bar');
      var subIcon = credit && credit.querySelector('img');
      var menu = e.querySelector('shreddit-post-overflow-menu');
      var reason = '', fewer = false;
      try {
        var rc = JSON.parse((menu && menu.getAttribute('recommendation-context-json')) || '{}');
        // Recommended (not from a subscription): Reddit offers "Show fewer" on these.
        fewer = !!(rc && rc.recommendationSource) && rc.recommendationSource.indexOf('subscribed') !== 0;
        if (rc && rc.content && !rc.isContextHidden) {
          var doc = JSON.parse(rc.content.richtext || '{}').document || [];
          reason = doc.map(function (p) { return (p.c || []).map(function (c) { return c.t || ''; }).join(''); }).join(' ').trim();
        }
      } catch (x) {}
      return {
        id: e.id, title: e.getAttribute('post-title') || '',
        sub: e.getAttribute('subreddit-prefixed-name') || '', author: e.getAttribute('author') || '',
        subIcon: subIcon ? (subIcon.getAttribute('src') || '') : '',
        score: e.getAttribute('score') || '0', comments: e.getAttribute('comment-count') || '0',
        created: e.getAttribute('created-timestamp') || '', type: e.getAttribute('post-type') || '',
        permalink: e.getAttribute('permalink') || '', href: e.getAttribute('content-href') || '',
        domain: e.getAttribute('domain') || '',
        img: img ? (img.getAttribute('src') || '') : '',
        body: body ? (body.innerText || '').trim().slice(0, 400) : '',
        flair: flair ? (flair.innerText || '').trim() : '',
        nsfw: e.hasAttribute('nsfw'), spoiler: e.hasAttribute('spoiler'),
        reason: reason, fewer: fewer
      };
    });
  return JSON.stringify({ signedOut: signedOut, posts: posts });
})();
"""
    }
}

/** A message for the Home feed, with what its action button does. */
data class HomeNotice(val message: String, val action: Action) {
    enum class Action { RETRY, SIGN_IN }
}

/** Experimental Reddit Home (headless WebView), falling back to For You. */
class RedditHomeEngine internal constructor(private val c: AppContainer, private val m: ForYouModule) {
    private val _progress = MutableStateFlow(0)

    /** Posts found so far while the first page loads (for the loading deck). */
    val progress: StateFlow<Int> = _progress

    /** A one-off notice for the feed (fell back to For You; sign-in expired). */
    val notice = MutableStateFlow<HomeNotice?>(null)

    private val _upgrades = MutableSharedFlow<List<Post>>(extraBufferCapacity = 8)

    /**
     * Full posts for cards first shown from the page alone (the feed swaps
     * them in by id, keeping its order).
     */
    val upgrades: SharedFlow<List<Post>> = _upgrades

    private val _showFewer = MutableStateFlow<Set<String>>(emptySet())

    /** Post ids (bare) Reddit offers "Show fewer posts like this" for. */
    val showFewerIds: StateFlow<Set<String>> = _showFewer

    private var loader: RedditHomeLoader? = null

    // This load fell back to For You (Reddit Home couldn't be read); paging
    // continues with For You until the next refresh.
    @Volatile private var fellBack = false
    @Volatile private var loadGen = 0 // bumped by each first-page Home load
    @Volatile private var homeEmpty = 0 // consecutive empty "more" batches from Reddit Home

    // The next batch, read ahead while the user scrolls the current one.
    private var prefetch: Deferred<List<PagePost>>? = null
    private var viewJob: Job? = null

    suspend fun page(after: String?, loaded: List<Post>): Listing<Post> {
        if (after == null) fellBack = false
        return if (fellBack) m.engine.page(after, loaded) else homePage(after, loaded)
    }

    private suspend fun homePage(after: String?, loaded: List<Post>): Listing<Post> {
        val firstPage = after == null
        val started = System.currentTimeMillis()
        try {
            val store = c.secureStore
            if (store.authMode() != "web") throw IllegalStateException("Reddit Home needs website sign-in")
            val cookie = store.webCookie() ?: ""
            val l = loader ?: RedditHomeLoader(c.context).also { loader = it }
            if (firstPage) {
                loadGen++
                _progress.value = 0
                prefetch?.cancel()
                prefetch = null
            }
            val page = if (firstPage) {
                l.next(restart = true, cookieHeader = cookie, onProgress = { n -> _progress.value = n })
            } else {
                (prefetch?.takeIf { !it.isCancelled }?.let { runCatching { it.await() }.getOrNull() })
                    ?: l.next(restart = false, cookieHeader = cookie)
            }
            prefetch = null
            if (page.isEmpty()) {
                if (firstPage) throw IllegalStateException("No posts found on Reddit Home")
                // One empty batch can just be the page still setting up its "load
                // more"; only two in a row end the feed.
                return Listing(emptyList(), after = if (++homeEmpty >= 2) null else "home")
            }
            homeEmpty = 0
            _showFewer.value = l.showFewerIds
            // Cards straight from the page (no wait for the API); the full posts
            // (media, video, flair, NSFW) follow in the background.
            val cards = page.map { it.toPost() }
            val gen = loadGen
            c.scope.launch { upgrade(page, firstPage, gen) }
            // Read the next batch ahead, so reaching the end doesn't wait.
            prefetch = c.scope.async { l.next(restart = false, cookieHeader = cookie) }
            if (firstPage) trackLoad("ok", cards.size, started)
            return Listing(cards, after = "home")
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: Exception) {
            if (!firstPage) throw e // a failed page keeps its cursor; retry
            // Reddit changed its page, the session expired, or the site refused:
            // show For You rather than an empty feed, and say so.
            fellBack = true
            trackLoad(if (e is HomeSignedOutException) "signin_expired" else "fell_back", 0, started)
            notice.value = if (e is HomeSignedOutException) {
                HomeNotice("Your Reddit website sign-in has expired. Showing For You.", HomeNotice.Action.SIGN_IN)
            } else {
                HomeNotice("Couldn't load Reddit Home, showing For You instead.", HomeNotice.Action.RETRY)
            }
            return m.engine.page(null, loaded)
        }
    }

    /** Anonymous: whether a Home load worked, how many posts and how long (coarse ranges). */
    private fun trackLoad(outcome: String, posts: Int, started: Long) {
        val ms = System.currentTimeMillis() - started
        val seconds = when {
            ms < 2_000 -> "<2"
            ms < 5_000 -> "2-5"
            ms < 10_000 -> "5-10"
            else -> "10+"
        }
        Analytics.track("home_loaded", mapOf("outcome" to outcome, "posts" to Analytics.bucket(posts, 0, 9), "seconds" to seconds))
    }

    /** Fetches the full posts for [page] and hands them to the feed. */
    private suspend fun upgrade(page: List<PagePost>, firstPage: Boolean, gen: Int) {
        // The account these cards belong to: a switch mid-request must not give
        // its posts (or its saved Home page) to the next account. Likewise a
        // newer Home load ([gen]) makes these cards old: an upgrade finishing
        // after it must not overwrite the newer cards or saved page.
        val user = c.session.username
        fun stale() = c.session.username != user || gen != loadGen
        // A failed fetch left cards without media (empty galleries); try again
        // a couple of times before leaving them as they are.
        var full: List<Post>? = null
        for (wait in listOf(0L, 2_000L, 5_000L)) {
            delay(wait)
            full = runCatching { c.repository.getPostsByIds(page.map { it.id }) }.getOrNull()
            if (full != null || stale()) break
        }
        if (full == null || stale()) return
        val reasons = page.associate { it.id.removePrefix("t3_") to it.reason }
        val posts = full.map { p -> reasons[p.id]?.let { p.copy(feedReason = it) } ?: p }
        _upgrades.emit(posts)
        if (firstPage && user.isNotEmpty()) {
            launchIo { saveForYouPage(c.context, user, posts, c.repository::rawPost, feed = "home") }
        }
    }

    private fun launchIo(block: suspend () -> Unit) = c.scope.launch(Dispatchers.IO) { block() }

    /**
     * The user is looking at [postId] in Ilay: follow it in the hidden page so
     * Reddit's "seen" tracking matches (debounced; skipped while loading).
     */
    fun viewing(postId: String) {
        val l = loader ?: return
        viewJob?.cancel()
        viewJob = c.scope.launch {
            delay(800)
            l.scrollTo("t3_$postId")
        }
    }

    /** "Show fewer posts like this" on reddit.com for [post]. True if Reddit took it. */
    suspend fun showFewer(post: Post): Boolean {
        val l = loader ?: return false
        val ok = runCatching { l.showFewer(post.fullname) }.getOrDefault(false)
        _showFewer.update { it - post.id }
        return ok
    }

    /** The app went to the background / came back: pause the hidden page meanwhile. */
    fun onAppBackground() {
        loader?.pause()
    }

    fun onAppForeground() {
        loader?.resume()
    }

    /** The last Home page, minus posts opened since, while the fresh one loads. */
    suspend fun cachedFirstPage(): Listing<Post>? {
        val user = c.session.username
        if (user.isEmpty()) return null
        val posts = loadForYouPage(c.context, user, c.history.ids.value, feed = "home") ?: return null
        return Listing(posts, after = null)
    }

    suspend fun cachedFirstPageTime(): Long? = c.session.username.takeIf { it.isNotEmpty() }?.let { savedPageTime(c.context, it, "home") }

    /** Closes the hidden browser (the feed went away). */
    fun dispose() {
        prefetch?.cancel()
        prefetch = null
        _showFewer.value = emptySet()
        val l = loader ?: return
        loader = null
        c.scope.launch { l.dispose() }
    }
}
