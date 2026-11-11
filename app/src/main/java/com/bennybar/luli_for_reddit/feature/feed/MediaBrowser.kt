package com.bennybar.luli_for_reddit.feature.feed

import androidx.compose.material.icons.rounded.Replay
import android.content.Context
import android.view.TextureView
import androidx.annotation.OptIn
import androidx.compose.animation.core.animate
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.systemBarsIgnoringVisibility
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.VerticalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.VolumeOff
import androidx.compose.material.icons.automirrored.rounded.VolumeUp
import androidx.compose.material.icons.outlined.ModeComment
import androidx.compose.material.icons.rounded.Bookmark
import androidx.compose.material.icons.rounded.BookmarkBorder
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Share
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Velocity
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import coil3.compose.AsyncImage
import coil3.size.Dimension
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.core.compactNumber
import com.bennybar.luli_for_reddit.core.net.Redgifs
import com.bennybar.luli_for_reddit.core.timeAgo
import com.bennybar.luli_for_reddit.feature.media.EdgeBack
import com.bennybar.luli_for_reddit.feature.media.ImmersiveMode
import com.bennybar.luli_for_reddit.feature.media.LocalMediaCovered
import com.bennybar.luli_for_reddit.feature.media.NsfwBlur
import com.bennybar.luli_for_reddit.feature.media.ViewerControls
import com.bennybar.luli_for_reddit.feature.media.ZoomableImage
import com.bennybar.luli_for_reddit.feature.media.buildPlayer
import com.bennybar.luli_for_reddit.feature.media.isExternalVideo
import com.bennybar.luli_for_reddit.feature.media.mediaItemFor
import com.bennybar.luli_for_reddit.feature.media.postVideoUrl
import com.bennybar.luli_for_reddit.model.Post
import com.bennybar.luli_for_reddit.model.PostType
import com.bennybar.luli_for_reddit.nav.AppNavigator
import com.bennybar.luli_for_reddit.nav.LocalNavigator
import com.bennybar.luli_for_reddit.nav.MediaViewer
import com.bennybar.luli_for_reddit.ui.Loading
import com.bennybar.luli_for_reddit.ui.theme.rememberColorScheme
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.launch

/**
 * A post Browse media shows (#103): images, GIFs, galleries and the videos
 * Ilay plays itself. Text and link posts, and YouTube-style embeds that only
 * play in their own app, are skipped.
 */
fun isBrowsableMedia(p: Post): Boolean = when (p.type) {
    PostType.IMAGE, PostType.GIF -> true
    PostType.GALLERY -> p.gallery.isNotEmpty()
    PostType.VIDEO -> !isExternalVideo(p)
    PostType.SELF, PostType.LINK -> false
}

/**
 * The first page: the first media post at or below [topId] in [shown] (the
 * feed as listed). With none below it yet, the page after the last one (the
 * loading page), which then pages more in.
 */
fun mediaStartIndex(shown: List<Post>, topId: String?): Int {
    val top = shown.indexOfFirst { it.id == topId }.coerceAtLeast(0)
    return shown.subList(0, top).count(::isBrowsableMedia)
}

/**
 * When Browse media asks the feed for its next page: a few media posts
 * before the end, so a page is in by the time you get there. A page can
 * bring no media at all (a run of text posts, everything filtered, or the
 * request failed); after [MAX_BARREN] of those in a row it stops asking,
 * rather than walking a text-only feed to its end.
 */
class MediaPaging {
    private var mediaAtRequest = -1

    /** Requests in a row that brought no new media. */
    var barren = 0
        private set

    /** Whether to load more now, with the viewer on [page] of [mediaCount]; counts it as a request if so. */
    fun shouldLoad(page: Int, mediaCount: Int, hasMore: Boolean, loadingMore: Boolean): Boolean {
        if (!hasMore || loadingMore || barren >= MAX_BARREN || page < mediaCount - LOOKAHEAD) return false
        // Not loading any more: the last request (if any) is in. Did it bring media?
        if (mediaAtRequest >= 0) barren = if (mediaCount > mediaAtRequest) 0 else barren + 1
        if (barren >= MAX_BARREN) return false
        mediaAtRequest = mediaCount
        return true
    }

    companion object {
        const val LOOKAHEAD = 3
        const val MAX_BARREN = 5
    }
}

/** Opens Browse media on [feedKey] at the post at the top of its list ([listState]). */
fun openMediaBrowser(nav: AppNavigator, feedKey: String, listState: LazyListState) {
    // The first post card still showing below the list's top padding (the top bar).
    val top = listState.layoutInfo.visibleItemsInfo.firstOrNull {
        (it.contentType as? String)?.startsWith("post_") == true && it.offset + it.size > 0
    }?.key as? String
    nav.viewers.open(MediaViewer.Feed(feedKey, top))
}

/**
 * The browser's one player, handed from page to page: only the settled
 * page's clip is loaded, the others show their poster. One decoder for the
 * whole browser, as the feed's [com.bennybar.luli_for_reddit.feature.media.InlineVideoPool].
 */
@OptIn(UnstableApi::class)
private class BrowserVideo(context: Context, muted: Boolean) {
    // Muted, it doesn't take audio focus, so the user's music keeps playing.
    val player = buildPlayer(context, audioFocus = !muted).apply {
        repeatMode = Player.REPEAT_MODE_ONE
        volume = if (muted) 0f else 1f
    }

    /** The post whose clip is loaded. */
    var owner by mutableStateOf<String?>(null)
    var firstFrame by mutableStateOf(false)
    var aspect by mutableFloatStateOf(0f)
    var failed by mutableStateOf(false)
    var ended by mutableStateOf(false) // stopped at the end (Loop videos off, #156)
    var muted by mutableStateOf(muted)
        private set

    init {
        player.addListener(object : Player.Listener {
            override fun onRenderedFirstFrame() {
                firstFrame = true
            }

            override fun onVideoSizeChanged(videoSize: VideoSize) {
                if (videoSize.width > 0 && videoSize.height > 0) {
                    aspect = videoSize.width * videoSize.pixelWidthHeightRatio / videoSize.height
                }
            }

            override fun onPlayerError(error: PlaybackException) {
                failed = true
            }

            override fun onPlaybackStateChanged(state: Int) {
                ended = state == Player.STATE_ENDED
            }
        })
    }

    /** From the start again, after it stopped at the end. */
    fun replay() {
        player.seekTo(0)
        player.play()
    }

    fun toggleMute() {
        muted = !muted
        player.volume = if (muted) 0f else 1f
        player.setAudioAttributes(player.audioAttributes, !muted)
    }

    /** Plays [p]'s clip until cancelled (its page is no longer the settled one), then frees the decoder. */
    suspend fun play(p: Post) {
        // RedGifs: its HD file with sound, as the full-screen viewer plays it
        // (Reddit's own mp4 copy is silent); a GIF plays Reddit's mp4 of it.
        val url = when {
            p.type == PostType.GIF -> p.gifMp4Url ?: return
            p.hlsUrl == null && p.fallbackVideoUrl == null && Redgifs.id(p.url) != null ->
                Redgifs.resolve(p.url) ?: postVideoUrl(p)
            else -> postVideoUrl(p)
        }
        owner = p.id
        firstFrame = false
        failed = false
        ended = false
        aspect = 0f
        // Settings › Loop videos (#156); a GIF always loops.
        player.repeatMode = if (p.type == PostType.GIF || app.settings.value.loopVideos) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF
        // Carry on from where the feed card was (its chunks are cached).
        player.setMediaItem(mediaItemFor(url), app.media.inlinePlayer.position(url) ?: 0L)
        player.prepare()
        player.playWhenReady = true
        try {
            awaitCancellation()
        } finally {
            // The next page may have taken the player already.
            if (owner == p.id) {
                owner = null
                player.stop()
                player.clearMediaItems()
            }
        }
    }
}

private fun isVideoPost(p: Post) = p.type == PostType.VIDEO || (p.type == PostType.GIF && p.gifMp4Url != null)

/**
 * Browse media (#103): the feed's media posts full screen, one per page;
 * swipe up for the next, down for the previous. Same posts, order and
 * filters as the list, and it pages the feed in as you near the end. Tap
 * shows / hides the post's details and actions; closing puts the list at
 * the last post viewed.
 */
@kotlin.OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun FeedMediaBrowser(route: MediaViewer.Feed) {
    ImmersiveMode()
    val nav = LocalNavigator.current
    val context = LocalContext.current
    val density = LocalDensity.current
    val scope = rememberCoroutineScope()
    val settings by app.settings.state.collectAsStateWithLifecycle()
    val controller = rememberFeedController(route.feedKey)
    val ui by controller.ui.collectAsStateWithLifecycle()
    val state = (ui as? FeedUi.Data)?.state
    val shown = rememberShownPosts(route.feedKey, state?.posts ?: emptyList())
    val media = remember(shown) { shown.filter(::isBrowsableMedia) }
    val start = remember { mediaStartIndex(shown, route.startId) }
    // One page past the last media post: loading more, or the end.
    val pager = rememberPagerState(initialPage = start) { media.size + 1 }
    // Screen width, the feed's decode size: the card's image is then already
    // in the memory cache (same URL and size) and the page paints at once.
    val decodeWidth = feedDecodeWidth()
    val decodeSize = remember(decodeWidth) { coil3.size.Size(Dimension(decodeWidth), Dimension.Undefined) }

    val video = remember { BrowserVideo(context, muted = app.settings.value.viewerMuted) }
    DisposableEffect(video) { onDispose { video.player.release() } }
    LifecycleEventEffect(Lifecycle.Event.ON_PAUSE) { video.player.pause() }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { if (video.owner != null) video.player.play() }

    var overlay by remember { mutableStateOf(true) }
    var zoomed by remember { mutableStateOf(false) }
    LaunchedEffect(pager.currentPage) { zoomed = false }

    // A settled page counts as viewing its media, as opening it from the card
    // does (For You engagement); and the list returns to it on close.
    val settled = media.getOrNull(pager.settledPage)
    val lastViewed = remember { mutableStateOf<String?>(null) }
    LaunchedEffect(settled?.id) {
        val p = settled ?: return@LaunchedEffect
        lastViewed.value = p.id
        app.forYou.learner.viewMedia(p)
    }
    // Closed on the post it opened on, the list is already there: scrolling
    // it to the top would jump it, after the browser has gone, by the gap
    // above the card, and under the floating chips (#107).
    val startPost = remember { media.getOrNull(start)?.id }
    DisposableEffect(controller) {
        onDispose { lastViewed.value?.takeIf { it != startPost }?.let { controller.browsedTo.value = it } }
    }

    val paging = remember { MediaPaging() }
    LaunchedEffect(pager.currentPage, media.size, state?.hasMore, state?.loadingMore) {
        val s = state ?: return@LaunchedEffect
        if (paging.shouldLoad(pager.currentPage, media.size, s.hasMore, s.loadingMore)) controller.loadMore()
    }

    // Swipe down past the first post to dismiss, as the other viewers do.
    var pull by remember { mutableFloatStateOf(0f) }
    val dismissPx = with(density) { 130.dp.toPx() }
    val flingPx = with(density) { 800.dp.toPx() }
    val pullDown = remember(nav) {
        object : NestedScrollConnection {
            override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
                // Back up after pulling down: undo the pull before paging.
                if (pull <= 0f || available.y >= 0f) return Offset.Zero
                val used = maxOf(available.y, -pull)
                pull += used
                return Offset(0f, used)
            }

            override fun onPostScroll(consumed: Offset, available: Offset, source: NestedScrollSource): Offset {
                // Only the first page leaves a downward drag unused.
                if (source != NestedScrollSource.UserInput || available.y <= 0f) return Offset.Zero
                pull += available.y
                return Offset(0f, available.y)
            }

            override suspend fun onPreFling(available: Velocity): Velocity {
                if (pull == 0f) return Velocity.Zero
                if (pull > dismissPx || available.y > flingPx) nav.closeViewer()
                else animate(pull, 0f, animationSpec = tween(200)) { v, _ -> pull = v }
                return available
            }
        }
    }

    Box(Modifier.fillMaxSize()) {
        Box(Modifier.fillMaxSize().graphicsLayer { alpha = (1f - pull / (dismissPx * 4)).coerceIn(0f, 1f) }.background(Color.Black))
        VerticalPager(
            pager,
            Modifier
                .fillMaxSize()
                .nestedScroll(pullDown)
                .graphicsLayer { translationY = pull }
                // TalkBack: page with actions rather than a swipe.
                .semantics {
                    customActions = listOf(
                        CustomAccessibilityAction("Next post") {
                            scope.launch { pager.animateScrollToPage(pager.currentPage + 1) }
                            true
                        },
                        CustomAccessibilityAction("Previous post") {
                            scope.launch { pager.animateScrollToPage(pager.currentPage - 1) }
                            true
                        },
                    )
                },
            beyondViewportPageCount = 1, // the next and previous pages load ahead
            key = { if (it < media.size) media[it].id else "end" },
            userScrollEnabled = !zoomed,
        ) { i ->
            val p = media.getOrNull(i)
            if (p == null) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    if (state == null || state.loadingMore || (state.hasMore && paging.barren < MediaPaging.MAX_BARREN)) {
                        Loading(color = Color.White)
                    } else {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(
                                if (media.isEmpty()) "No images or videos here" else "That's all the media here",
                                color = Color.White.copy(alpha = 0.8f),
                                fontSize = 16.sp,
                            )
                            Spacer(Modifier.height(16.dp))
                            FilledTonalButton(onClick = { nav.closeViewer() }) { Text("Close") }
                        }
                    }
                }
            } else {
                val onTap = { overlay = !overlay }
                val onZoom = { z: Boolean -> if (i == pager.currentPage) zoomed = z }
                val active = i == pager.settledPage
                Box(Modifier.fillMaxSize().semantics { contentDescription = p.title }) {
                    NsfwBlur(blurOf(p, settings), Modifier.fillMaxSize(), blurredImageUrl = p.blurredPreviewUrl, label = blurLabel(p, settings)) {
                        when {
                            p.type == PostType.GALLERY -> GalleryPage(p, decodeSize, onTap, onZoom)
                            isVideoPost(p) -> VideoPage(p, active, video, decodeWidth, settings.autoplayMedia, onTap)
                            else -> ZoomableImage(p.previewUrl ?: p.url, onTap, onZoom, decodeSize = decodeSize)
                        }
                    }
                }
            }
        }

        val current = media.getOrNull(pager.currentPage)
        val overlayAlpha by animateFloatAsState(if (overlay && pull == 0f) 1f else 0f, tween(150), label = "browserOverlay")
        if (overlayAlpha > 0.01f) {
            ViewerControls(title = null, sourceUrl = null, modifier = Modifier.alpha(overlayAlpha))
            if (current != null) {
                MaterialTheme(colorScheme = rememberColorScheme(settings, dark = true)) {
                    PostOverlay(
                        current,
                        video.takeIf { isVideoPost(current) },
                        Modifier
                            .align(Alignment.BottomCenter)
                            .alpha(overlayAlpha)
                            .background(Brush.verticalGradient(listOf(Color.Transparent, Color(0xC0000000))))
                            // The bars are hidden, but keep clear of the gesture bar and a camera cutout.
                            .windowInsetsPadding(
                                WindowInsets.systemBarsIgnoringVisibility.union(WindowInsets.displayCutout)
                                    .only(WindowInsetsSides.Bottom + WindowInsetsSides.Horizontal),
                            ),
                    )
                }
            }
        }
        EdgeBack()
    }
}

/** A gallery: swipe sideways through its images, with an "i / n" counter and dots. */
@Composable
private fun GalleryPage(p: Post, decodeSize: coil3.size.Size, onTap: () -> Unit, onZoom: (Boolean) -> Unit) {
    val images = p.gallery
    val pager = rememberPagerState { images.size }
    LaunchedEffect(pager.currentPage) { onZoom(false) }
    Box(Modifier.fillMaxSize()) {
        HorizontalPager(pager, Modifier.fillMaxSize(), beyondViewportPageCount = 1, key = { it }) { j ->
            ZoomableImage(images[j].url, onTap, { z -> if (j == pager.currentPage) onZoom(z) }, decodeSize = decodeSize)
        }
        Column(
            Modifier
                .align(Alignment.TopCenter)
                .windowInsetsPadding(WindowInsets.statusBars.union(WindowInsets.displayCutout).only(WindowInsetsSides.Top))
                .padding(top = 60.dp)
                .background(Color.Black.copy(alpha = 0.54f), CircleShape)
                .padding(horizontal = 10.dp, vertical = 5.dp)
                .semantics { contentDescription = "Image ${pager.currentPage + 1} of ${images.size}" },
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text("${pager.currentPage + 1} / ${images.size}", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold)
            // Dots for a short gallery; a long one has only the count.
            if (images.size in 2..12) {
                Row(Modifier.padding(top = 4.dp)) {
                    for (j in images.indices) {
                        Box(
                            Modifier
                                .padding(horizontal = 2.dp)
                                .size(5.dp)
                                .background(if (j == pager.currentPage) Color.White else Color.White.copy(alpha = 0.45f), CircleShape),
                        )
                    }
                }
            }
        }
    }
}

/**
 * A video (or a GIF's mp4): the poster, and once its page has settled the
 * shared player on top. Autoplays per Settings › Autoplay media; with it off,
 * a play button starts it.
 */
@Composable
private fun VideoPage(p: Post, active: Boolean, video: BrowserVideo, decodeWidth: Int, autoplay: Boolean, onTap: () -> Unit) {
    // Under an NSFW / spoiler cover it waits for the reveal.
    val covered = LocalMediaCovered.current
    var started by remember { mutableStateOf(false) }
    val play = active && !covered && (autoplay || started)
    if (play) LaunchedEffect(p.id) { video.play(p) }
    val mine = video.owner == p.id
    Box(Modifier.fillMaxSize().clickable(interactionSource = null, indication = null, onClick = onTap), contentAlignment = Alignment.Center) {
        AsyncImage(
            model = rememberSizedRequest(p.previewUrl, decodeWidth),
            contentDescription = null,
            contentScale = ContentScale.Fit,
            modifier = Modifier.fillMaxSize(),
        )
        if (mine) {
            AndroidView(
                factory = { ctx -> TextureView(ctx).also(video.player::setVideoTextureView) },
                onRelease = video.player::clearVideoTextureView,
                modifier = (if (video.aspect > 0f) Modifier.aspectRatio(video.aspect) else Modifier.fillMaxSize())
                    .graphicsLayer { alpha = if (video.firstFrame) 1f else 0f },
            )
        }
        when {
            // Stopped at the end (Loop videos off, #156): play it again.
            mine && video.ended -> Box(
                Modifier
                    .size(72.dp)
                    .background(Color.Black.copy(alpha = 0.5f), CircleShape)
                    .clickable(onClickLabel = "Replay", onClick = video::replay),
                contentAlignment = Alignment.Center,
            ) { Icon(Icons.Rounded.Replay, "Replay", Modifier.size(40.dp), tint = Color.White) }
            mine && video.failed -> Text(
                "This video can't be played in the app",
                Modifier.background(Color.Black.copy(alpha = 0.6f), CircleShape).padding(horizontal = 16.dp, vertical = 8.dp),
                color = Color.White,
            )
            !autoplay && !started -> Box(
                Modifier
                    .size(72.dp)
                    .background(Color.Black.copy(alpha = 0.5f), CircleShape)
                    .clickable { started = true },
                contentAlignment = Alignment.Center,
            ) { Icon(Icons.Rounded.PlayArrow, "Play", Modifier.size(40.dp), tint = Color.White) }
            play && !(mine && video.firstFrame) -> Loading(color = Color.White)
        }
    }
}

/**
 * The post over its media: subreddit, author, age, the title (tap for all of
 * it) and its actions. The actions are the card's own ([PostActions]), so a
 * vote or save shows everywhere at once.
 */
@kotlin.OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
private fun PostOverlay(p: Post, video: BrowserVideo?, modifier: Modifier) {
    val nav = LocalNavigator.current
    val actions = remember(p, nav) { PostActions(p, nav) }
    val ov by rememberOverride(p)
    val likes = if (ov != null) ov!!.likes else p.likes
    val score = ov?.score ?: p.score
    val saved = ov?.saved ?: p.saved
    val numComments = ov?.numComments ?: p.numComments
    var expanded by remember(p.id) { mutableStateOf(false) }
    val white = Color.White
    val iconColors = IconButtonDefaults.iconButtonColors(contentColor = white)
    Column(modifier.fillMaxWidth().padding(start = 16.dp, top = 56.dp, end = 8.dp, bottom = 8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                p.subredditPrefixed,
                Modifier.clickable(onClickLabel = "Open subreddit", onClick = actions::openSubreddit),
                color = white,
                fontSize = 14.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 1,
            )
            Text(
                " · u/${p.author}",
                Modifier.weight(1f, fill = false).clickable(onClickLabel = "Open profile", onClick = actions::openAuthor),
                color = white.copy(alpha = 0.8f),
                fontSize = 13.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(" · ${timeAgo(p.createdUtc)}", color = white.copy(alpha = 0.8f), fontSize = 13.sp, maxLines = 1)
        }
        Spacer(Modifier.height(4.dp))
        Text(
            p.title,
            Modifier
                .padding(end = 8.dp)
                .clickable(onClickLabel = if (expanded) "Show less" else "Show the whole title") { expanded = !expanded },
            color = white,
            fontSize = 16.sp,
            fontWeight = FontWeight.SemiBold,
            maxLines = if (expanded) 12 else 3,
            overflow = TextOverflow.Ellipsis,
        )
        Spacer(Modifier.height(8.dp))
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            VotePill(score, likes, onUp = { actions.vote(1) }, onDown = { actions.vote(-1) })
            Row(
                Modifier
                    .background(MaterialTheme.colorScheme.surfaceContainerHigh, CircleShape)
                    .clickable(onClickLabel = "Open comments", onClick = actions::openDetail)
                    .padding(horizontal = 14.dp, vertical = 10.dp)
                    .semantics(mergeDescendants = true) { contentDescription = "${compactNumber(numComments)} comments" },
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.Outlined.ModeComment, null, Modifier.size(18.dp), tint = white)
                Spacer(Modifier.width(6.dp))
                Text(compactNumber(numComments), color = white)
            }
            Spacer(Modifier.weight(1f))
            if (video != null) {
                IconButton(onClick = video::toggleMute, shapes = IconButtonDefaults.shapes(), colors = iconColors) {
                    Icon(
                        if (video.muted) Icons.AutoMirrored.Rounded.VolumeOff else Icons.AutoMirrored.Rounded.VolumeUp,
                        if (video.muted) "Unmute" else "Mute",
                    )
                }
            }
            IconButton(onClick = actions::toggleSave, shapes = IconButtonDefaults.shapes(), colors = iconColors) {
                Icon(if (saved) Icons.Rounded.Bookmark else Icons.Rounded.BookmarkBorder, if (saved) "Unsave" else "Save")
            }
            IconButton(onClick = actions::share, shapes = IconButtonDefaults.shapes(), colors = iconColors) {
                Icon(Icons.Rounded.Share, "Share")
            }
            IconButton(onClick = actions::more, shapes = IconButtonDefaults.shapes(), colors = iconColors) {
                Icon(Icons.Rounded.MoreVert, "More")
            }
        }
    }
}
