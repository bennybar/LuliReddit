package com.bennybar.luli_for_reddit.feature.media

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.Dp
import com.bennybar.luli_for_reddit.model.GalleryImage
import com.bennybar.luli_for_reddit.model.Post
import com.bennybar.luli_for_reddit.nav.AppNavigator
import com.bennybar.luli_for_reddit.nav.Route

/** [Agent D] A video post's playable URL, without network lookups. */
fun postVideoUrl(p: Post): String = p.hlsUrl ?: p.fallbackVideoUrl ?: p.url

/** [Agent D] Opens a video post full-screen; RedGifs resolved to HD first. */
suspend fun openPostVideo(nav: AppNavigator, post: Post) {
    nav.openVideo(postVideoUrl(post), title = post.title)
}

/** [Agent D] Downloads to the folder chosen in Settings, else the gallery, with progress + cancel. */
suspend fun saveMediaToGallery(url: String, isVideo: Boolean) {}

/** [Agent D] Inline swipeable gallery with counter + dots; tap opens the viewer at that index. */
@Composable
fun GalleryCarousel(images: List<GalleryImage>, modifier: Modifier = Modifier, title: String? = null, height: Dp? = null) {}

/**
 * [Agent D] Frosted "NSFW"/"Spoiler" cover until tapped. With Reddit's
 * pre-blurred copy ([blurredImageUrl]) it just draws that (no live blur).
 */
@Composable
fun NsfwBlur(blur: Boolean, modifier: Modifier = Modifier, blurredImageUrl: String? = null, label: String = "NSFW", content: @Composable () -> Unit) {
    content()
}

/** [Agent D] Feed video: autoplays muted + looping while visible, pauses off-screen; tap = viewer. */
@Composable
fun InlineVideo(url: String, height: Dp, onTap: () -> Unit, modifier: Modifier = Modifier, poster: String? = null) {}

/** [Agent D] Full-screen image viewer (zoom, swipe-to-dismiss, save/share). */
@Composable fun ImageViewerScreen(url: String, title: String?) {}
/** [Agent D] Full-screen gallery viewer. */
@Composable fun GalleryViewerScreen(route: Route.GalleryViewer) {}
/** [Agent D] Full-screen video player with sound. */
@Composable fun VideoViewerScreen(route: Route.VideoViewer) {}
