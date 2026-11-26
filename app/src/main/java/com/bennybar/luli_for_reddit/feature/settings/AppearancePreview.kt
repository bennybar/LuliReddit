package com.bennybar.luli_for_reddit.feature.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.bennybar.luli_for_reddit.R
import com.bennybar.luli_for_reddit.feature.feed.LocalFeedSideInset
import com.bennybar.luli_for_reddit.feature.feed.PostCard
import com.bennybar.luli_for_reddit.model.FlairPart
import com.bennybar.luli_for_reddit.model.Post
import com.bennybar.luli_for_reddit.model.PostType
import com.bennybar.luli_for_reddit.model.UserFlair
import kotlin.math.roundToInt

/**
 * Settings › Appearance's live preview: a sample post drawn by the feed's own [PostCard],
 * so every look option (layout, corners, text sizes, font, theme, icons, flair…) shows
 * as it changes. Pinned above the options; scaled down when the layout is tall. The
 * sample is local — a bundled picture, no Reddit requests — and the card is inert.
 */
@Composable
fun AppearancePreview(modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val post = remember { samplePost("android.resource://${context.packageName}/${R.drawable.appearance_preview_photo}") }
    val cs = MaterialTheme.colorScheme
    BoxWithConstraints(modifier.fillMaxWidth().background(cs.surface)) {
        // Up to about 40% of the screen, so the options keep most of it.
        val max = (maxHeight.takeIf { it != Dp.Infinity } ?: 800.dp).let { it * 0.4f }
        Box(
            Modifier
                .fillMaxWidth()
                .clearAndSetSemantics { contentDescription = "Preview of a post with these settings" }
                // Look, don't touch: no votes, swipes, menus or opening the post.
                .pointerInput(Unit) {
                    awaitPointerEventScope {
                        while (true) awaitPointerEvent(PointerEventPass.Initial).changes.forEach { it.consume() }
                    }
                }
                .padding(horizontal = FEED_SIDE_INSET, vertical = 8.dp),
        ) {
            FitHeight(max) {
                CompositionLocalProvider(LocalFeedSideInset provides FEED_SIDE_INSET) { PostCard(post) }
            }
        }
        HorizontalDivider(Modifier.align(androidx.compose.ui.Alignment.BottomCenter), color = cs.outlineVariant)
    }
}

/** As the feed's list (PostListView): Compact's rows reach past it to the edges. */
private val FEED_SIDE_INSET = 7.dp

/** [content] at full width; shrunk (from its top centre) to fit [maxHeight] when taller. */
@Composable
private fun FitHeight(maxHeight: Dp, content: @Composable () -> Unit) {
    Layout(content, Modifier.clipToBounds()) { measurables, c ->
        val p = measurables.first().measure(c.copy(minHeight = 0, maxHeight = Constraints.Infinity))
        val maxPx = maxHeight.roundToPx()
        val scale = if (p.height > maxPx) maxPx.toFloat() / p.height else 1f
        layout(c.maxWidth, (p.height * scale).roundToInt()) {
            p.placeWithLayer((c.maxWidth - p.width) / 2, 0) {
                scaleX = scale
                scaleY = scale
                transformOrigin = TransformOrigin(0.5f, 0f)
            }
        }
    }
}

/** A made-up post that shows most of a card: flair, a short body and a photo. */
internal fun samplePost(photo: String) = Post(
    id = "appearance_preview",
    fullname = "t3_appearance_preview",
    title = "Morning fog over the lake, shot handheld at sunrise",
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
    selftext = "A short body shows under the title in layouts that preview the text.",
    linkFlairText = "OC",
    linkFlair = UserFlair(listOf(FlairPart("OC"))),
    previewUrl = photo,
    previewMedUrl = photo,
    previewWidth = 960,
    previewHeight = 540,
)
