package com.bennybar.luli_for_reddit.feature.media

import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.BrokenImage
import androidx.compose.material.icons.rounded.Collections
import androidx.compose.material.icons.rounded.VisibilityOff
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.compose.SubcomposeAsyncImage
import com.bennybar.luli_for_reddit.core.isVideoUrl
import com.bennybar.luli_for_reddit.core.net.Redgifs
import com.bennybar.luli_for_reddit.core.resolveVideoUrl
import com.bennybar.luli_for_reddit.model.GalleryImage
import com.bennybar.luli_for_reddit.model.Post
import com.bennybar.luli_for_reddit.nav.AppNavigator
import com.bennybar.luli_for_reddit.nav.LocalNavigator
import com.bennybar.luli_for_reddit.nav.Route

/**
 * A video post's playable URL, without any network lookup: Reddit's own
 * stream when it hosts the video, a direct file link as-is, and otherwise
 * Reddit's mp4 copy of the embed (e.g. RedGifs), whose own URL is a web page.
 */
fun postVideoUrl(p: Post): String {
    (p.hlsUrl ?: p.fallbackVideoUrl)?.let { return it }
    val direct = resolveVideoUrl(p.url)
    val uri = runCatching { Uri.parse(direct) }.getOrNull()
    if (uri != null && isVideoUrl(uri)) return direct
    return p.gifMp4Url ?: direct
}

/**
 * Opens a video post full-screen. RedGifs clips are resolved to their HD
 * file (with sound) first, falling back to Reddit's silent mp4 copy.
 */
suspend fun openPostVideo(nav: AppNavigator, post: Post) {
    var src = postVideoUrl(post)
    var download = post.fallbackVideoUrl ?: src
    if (post.hlsUrl == null && post.fallbackVideoUrl == null && Redgifs.id(post.url) != null) {
        val hd = Redgifs.resolve(post.url)
        if (hd != null) {
            src = hd
            download = hd
        }
    }
    nav.openVideo(src, title = post.title, downloadUrl = download, externalUrl = post.url)
}

/**
 * Downloads a media file to the folder picked in Settings, else the device
 * gallery's "Ilay" album, with a cancellable progress dialog showing
 * downloaded / total size.
 */
suspend fun saveMediaToGallery(url: String, isVideo: Boolean) = saveMedia(url, isVideo)

/**
 * An inline, swipeable gallery preview with a page counter and dot indicator.
 * Tapping any image opens the full-screen viewer at that index. With
 * [height] it's a fixed-height (cover-cropped) banner instead of sizing to
 * the first image's aspect ratio.
 */
@Composable
fun GalleryCarousel(images: List<GalleryImage>, modifier: Modifier = Modifier, title: String? = null, height: Dp? = null) {
    if (images.isEmpty()) return
    val nav = LocalNavigator.current
    val cs = MaterialTheme.colorScheme
    val first = images.first()
    val aspect = if (first.width != null && first.height != null && first.height > 0) {
        (first.width.toFloat() / first.height).coerceIn(0.5f, 2f)
    } else 16f / 9f
    val pager = rememberPagerState { images.size }
    val sized = if (height != null) modifier.fillMaxWidth().height(height) else modifier.fillMaxWidth().aspectRatio(aspect)
    Box(sized.clip(RoundedCornerShape(16.dp))) {
        HorizontalPager(pager, Modifier.fillMaxSize(), key = { it }) { i ->
            SubcomposeAsyncImage(
                model = images[i].url,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize().clickable { nav.openGallery(images, title, i) },
                loading = { Box(Modifier.fillMaxSize().background(cs.surfaceContainerHighest)) },
                error = {
                    Box(Modifier.fillMaxSize().background(cs.surfaceContainerHighest), contentAlignment = Alignment.Center) {
                        Icon(Icons.Outlined.BrokenImage, null, tint = cs.onSurfaceVariant)
                    }
                },
            )
        }
        // Counter badge
        Row(
            Modifier
                .align(Alignment.TopEnd)
                .padding(8.dp)
                .background(Color.Black.copy(alpha = 0.54f), RoundedCornerShape(10.dp))
                .padding(horizontal = 8.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Rounded.Collections, null, Modifier.size(14.dp), tint = Color.White)
            Spacer(Modifier.width(4.dp))
            Text(
                "${pager.currentPage + 1}/${images.size}",
                color = Color.White,
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
            )
        }
        // Dot indicator
        if (images.size > 1) {
            Row(
                Modifier.align(Alignment.BottomCenter).padding(bottom = 8.dp),
                horizontalArrangement = Arrangement.Center,
            ) {
                for (i in images.indices) {
                    Box(
                        Modifier
                            .padding(horizontal = 2.dp)
                            .size(6.dp)
                            .background(if (i == pager.currentPage) Color.White else Color.White.copy(alpha = 0.54f), CircleShape),
                    )
                }
            }
        }
    }
}

/**
 * Wraps media with a frosted blur + "NSFW" label until tapped to reveal.
 * When [blur] is false it renders [content] unchanged.
 *
 * Given Reddit's pre-blurred copy ([blurredImageUrl]) it just draws that:
 * a live blur re-renders the media on every frame, which is one of the most
 * expensive things a scrolling list can do. While covered, inline videos
 * inside don't autoplay ([LocalMediaCovered]).
 */
@Composable
fun NsfwBlur(blur: Boolean, modifier: Modifier = Modifier, blurredImageUrl: String? = null, label: String = "NSFW", content: @Composable () -> Unit) {
    var revealed by rememberSaveable { mutableStateOf(false) }
    if (!blur || revealed) {
        Box(modifier) { content() }
        return
    }
    Box(modifier) {
        CompositionLocalProvider(LocalMediaCovered provides true) {
            // Without a pre-blurred copy, blur the media itself (RenderEffect).
            Box(if (blurredImageUrl == null) Modifier.blur(24.dp) else Modifier) { content() }
        }
        Box(Modifier.matchParentSize().clip(RoundedCornerShape(16.dp))) {
            if (blurredImageUrl != null) {
                SubcomposeAsyncImage(
                    model = blurredImageUrl,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize(),
                    loading = { Box(Modifier.fillMaxSize().background(Color.Black)) },
                    error = { Box(Modifier.fillMaxSize().background(Color.Black)) },
                )
            }
            Column(
                Modifier
                    .fillMaxSize()
                    .background(Color.Black.copy(alpha = 0.25f))
                    .clickable { revealed = true },
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Icon(Icons.Rounded.VisibilityOff, null, Modifier.size(32.dp), tint = Color.White)
                Spacer(Modifier.height(8.dp))
                Text("$label · tap to view", color = Color.White, fontWeight = FontWeight.Bold)
            }
        }
    }
}

/** Feed video: autoplays muted + looping while visible, pauses off-screen; tap = viewer. */
@Composable
fun InlineVideo(url: String, height: Dp, onTap: () -> Unit, modifier: Modifier = Modifier, poster: String? = null) =
    InlineVideoImpl(url, height, onTap, modifier, poster)

/** Full-screen image viewer (zoom, swipe-to-dismiss, save/share). */
@Composable fun ImageViewerScreen(url: String, title: String?) = ImageViewer(url, title)

/** Full-screen gallery viewer. */
@Composable fun GalleryViewerScreen(route: Route.GalleryViewer) = GalleryViewer(route)

/** Full-screen video player with sound. */
@Composable fun VideoViewerScreen(route: Route.VideoViewer) = VideoViewer(route)
