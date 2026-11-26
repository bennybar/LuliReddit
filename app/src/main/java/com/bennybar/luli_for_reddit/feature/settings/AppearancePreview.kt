package com.bennybar.luli_for_reddit.feature.settings

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bennybar.luli_for_reddit.R
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.feature.feed.LocalFeedSideInset
import com.bennybar.luli_for_reddit.feature.feed.PostCard
import com.bennybar.luli_for_reddit.model.FlairPart
import com.bennybar.luli_for_reddit.model.Post
import com.bennybar.luli_for_reddit.model.PostType
import com.bennybar.luli_for_reddit.model.UserFlair
import com.bennybar.luli_for_reddit.settings.PostDisplay

/**
 * Settings › Appearance's live preview: a window into the feed, not a shrunk card. The
 * sample post is drawn by the feed's own [PostCard] at true size, with the feed list's side
 * inset and spacing, on the feed's background, so every look option (layout, corners,
 * text sizes, font, theme, icons, flair…) shows exactly as it will. Pinned under the page
 * title; up to about half the screen, a taller card fading out at the bottom with its top
 * always readable. The sample is local (a bundled picture, no Reddit requests) and inert.
 *
 * [scrolled]: the options have gone under it, so a hairline sets it off from them.
 */
@Composable
fun AppearancePreview(scrolled: Boolean, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val post = remember { samplePost("android.resource://${context.packageName}/${R.drawable.appearance_preview_photo}") }
    val display by remember { app.settings.state }.collectAsStateWithLifecycle()
    val cs = MaterialTheme.colorScheme
    BoxWithConstraints(modifier.fillMaxWidth().background(cs.background)) {
        val max = (maxHeight.takeIf { it != Dp.Infinity } ?: 800.dp) * 0.52f
        var clipped by remember { mutableStateOf(false) }
        Box(
            Modifier
                .fillMaxWidth()
                .animateContentSize()
                .clearAndSetSemantics { contentDescription = "Preview of a post with these settings" }
                // Look, don't touch: no votes, swipes, menus or opening the post.
                .pointerInput(Unit) {
                    awaitPointerEventScope {
                        while (true) awaitPointerEvent(PointerEventPass.Initial).changes.forEach { it.consume() }
                    }
                },
        ) {
            // The feed's own spacing above a post: Compact's rows sit closer (PostListView).
            val top = if (display.postDisplay == PostDisplay.COMPACT) 6.dp else 10.dp
            ClipHeight(max, onClipped = { clipped = it }) {
                Box(Modifier.padding(start = FEED_SIDE_INSET, top = top, end = FEED_SIDE_INSET, bottom = 10.dp)) {
                    CompositionLocalProvider(LocalFeedSideInset provides FEED_SIDE_INSET) { PostCard(post) }
                }
            }
            if (clipped) {
                // The rest of a tall card fades into the stage instead of being cut hard.
                Box(
                    Modifier
                        .align(Alignment.BottomCenter)
                        .fillMaxWidth()
                        .height(36.dp)
                        .background(Brush.verticalGradient(listOf(Color.Transparent, cs.background))),
                )
            }
        }
        if (scrolled) HorizontalDivider(Modifier.align(Alignment.BottomCenter), color = cs.outlineVariant)
    }
}

/** As the feed's list (PostListView): Compact's rows reach past it to the edges. */
private val FEED_SIDE_INSET = 7.dp

/** [content] at its true size, cut at [maxHeight] from the bottom when taller (never scaled). */
@Composable
private fun ClipHeight(maxHeight: Dp, onClipped: (Boolean) -> Unit, content: @Composable () -> Unit) {
    Layout(content, Modifier.clipToBounds()) { measurables, c ->
        val p = measurables.first().measure(c.copy(minHeight = 0, maxHeight = Constraints.Infinity))
        val maxPx = maxHeight.roundToPx()
        onClipped(p.height > maxPx)
        layout(c.maxWidth, minOf(p.height, maxPx)) { p.place(0, 0) }
    }
}

/**
 * A made-up post that shows most of a card in little height: one line of title, one
 * flair, one line of body and a wide photo.
 */
internal fun samplePost(photo: String) = Post(
    id = "appearance_preview",
    fullname = "t3_appearance_preview",
    title = "Morning fog over the lake",
    subreddit = "photography",
    subredditPrefixed = "r/photography",
    author = "ilay_preview",
    score = 1234,
    numComments = 84,
    upvoteRatio = 0.97,
    createdUtc = System.currentTimeMillis() - 2 * 3_600_000L,
    permalink = "/r/photography/comments/appearance_preview/",
    url = photo,
    domain = "i.redd.it",
    type = PostType.IMAGE,
    selftext = "Shot handheld at sunrise.",
    linkFlairText = "OC",
    linkFlair = UserFlair(listOf(FlairPart("OC"))),
    previewUrl = photo,
    previewMedUrl = photo,
    // About 2.4:1, so the stage stays low; the bundled 16:9 picture is cropped to it.
    previewWidth = 1200,
    previewHeight = 500,
)
