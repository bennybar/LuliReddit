package com.bennybar.luli_for_reddit.feature.settings

import androidx.compose.animation.animateContentSize
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.tween
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
import com.bennybar.luli_for_reddit.feature.feed.FloatingChipsSample
import com.bennybar.luli_for_reddit.feature.feed.PostCard
import com.bennybar.luli_for_reddit.feature.post.SampleCommentThread
import com.bennybar.luli_for_reddit.model.Comment
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
 * It follows the options in view ([kind], see [pickPreview]): the post for the layout,
 * colour and text options, a sample thread for the comments' size, the floating chips
 * for theirs, and nothing for the options it can't show, so those get the whole screen.
 *
 * [scrolled]: the options have gone under it, so a hairline sets it off from them.
 */
@Composable
fun AppearancePreview(scrolled: Boolean, kind: PreviewKind, modifier: Modifier = Modifier) {
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
                // One preview cross-fades into the next while the height follows (none: 0).
                .animateContentSize(tween(PREVIEW_SWAP_MS))
                .clearAndSetSemantics {
                    contentDescription = when (kind) {
                        PreviewKind.POST -> "Preview of a post with these settings"
                        PreviewKind.COMMENTS -> "Preview of comments with these settings"
                        PreviewKind.CHIPS -> "Preview of the floating filter chips"
                        PreviewKind.NONE -> ""
                    }
                }
                // Look, don't touch: no votes, swipes, menus or opening the post.
                .pointerInput(Unit) {
                    awaitPointerEventScope {
                        while (true) awaitPointerEvent(PointerEventPass.Initial).changes.forEach { it.consume() }
                    }
                },
        ) {
            Crossfade(kind, animationSpec = tween(PREVIEW_SWAP_MS), label = "appearancePreview") { k ->
                when (k) {
                    PreviewKind.POST -> {
                        // The feed's own spacing above a post: Compact's rows sit closer (PostListView).
                        val top = if (display.postDisplay == PostDisplay.COMPACT) 6.dp else 10.dp
                        ClipHeight(max, onClipped = { clipped = it }) {
                            Box(Modifier.padding(start = FEED_SIDE_INSET, top = top, end = FEED_SIDE_INSET, bottom = 10.dp)) {
                                CompositionLocalProvider(LocalFeedSideInset provides FEED_SIDE_INSET) { PostCard(post) }
                            }
                        }
                    }
                    // The thread's own rows, in its style (Calm or cards), at the comments' size.
                    PreviewKind.COMMENTS -> ClipHeight(max, onClipped = { clipped = it }) {
                        Box(Modifier.padding(bottom = 6.dp)) { SampleCommentThread(SAMPLE_COMMENTS, post.author, display) }
                    }
                    // The floating row over the top of a feed, as it's drawn there.
                    PreviewKind.CHIPS -> Box(Modifier.fillMaxWidth().height(CHIPS_STAGE).clipToBounds()) {
                        Box(Modifier.padding(start = FEED_SIDE_INSET, top = 34.dp, end = FEED_SIDE_INSET)) {
                            CompositionLocalProvider(LocalFeedSideInset provides FEED_SIDE_INSET) { PostCard(post) }
                        }
                        FloatingChipsSample(display.floatingChipsSolid, Modifier.padding(top = 6.dp))
                    }
                    PreviewKind.NONE -> Box(Modifier.fillMaxWidth())
                }
            }
            if (clipped && kind != PreviewKind.NONE && kind != PreviewKind.CHIPS) {
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

/** What Appearance's preview shows: what the options in view change. */
enum class PreviewKind { POST, COMMENTS, CHIPS, NONE }

/** One group of Appearance options: what the preview shows for it, and where its first row is. */
data class PreviewSection(val kind: PreviewKind, val top: Float)

/**
 * The preview for the options in view, with hysteresis. [sections] in page order, each
 * with its first row's top in px from a fixed point (the top of the page under its bar),
 * [Float.NEGATIVE_INFINITY] once scrolled above the page and [Float.POSITIVE_INFINITY]
 * below it. A group is the one in view once its first row has come up to [line]. [current]
 * stays while any group within [slack] of the line still has it, so a boundary resting on
 * the line doesn't flicker; past that, the group at the line wins.
 *
 * Nothing here moves when the preview changes height: [line] is fixed, and the page under
 * it is kept where it was while the preview grows or shrinks (the list scrolls by as much),
 * so a swap can't trigger another.
 */
fun pickPreview(sections: List<PreviewSection>, line: Float, slack: Float, current: PreviewKind): PreviewKind {
    if (sections.isEmpty()) return current
    fun at(y: Float) = sections.indexOfLast { it.top <= y }.coerceAtLeast(0)
    val from = at(line - slack)
    val to = at(line + slack)
    if ((from..to).any { sections[it].kind == current }) return current
    return sections[at(line)].kind
}

/** How long one preview takes to give way to the next. */
const val PREVIEW_SWAP_MS = 250

/** The floating chips' stage: the row, over the top of a post as in a feed. */
private val CHIPS_STAGE = 118.dp

/** A comment and the poster's reply under it, for the comments' preview. */
private val SAMPLE_COMMENTS = listOf(
    Comment(
        id = "appearance_preview_c1",
        fullname = "t1_appearance_preview_c1",
        parentId = "t3_appearance_preview",
        author = "early_riser",
        body = "That light on the water is unreal. What time did you get there?",
        score = 212,
        createdUtc = System.currentTimeMillis() - 90 * 60_000L,
        depth = 0,
    ),
    Comment(
        id = "appearance_preview_c2",
        fullname = "t1_appearance_preview_c2",
        parentId = "t1_appearance_preview_c1",
        author = "ilay_preview",
        body = "Just before six, the fog lifted twenty minutes later.",
        score = 87,
        createdUtc = System.currentTimeMillis() - 60 * 60_000L,
        depth = 1,
    ),
)
