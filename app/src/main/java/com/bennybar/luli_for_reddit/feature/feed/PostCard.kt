package com.bennybar.luli_for_reddit.feature.feed

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.HelpOutline
import androidx.compose.material.icons.automirrored.rounded.OpenInNew
import androidx.compose.material.icons.outlined.BrokenImage
import androidx.compose.material.icons.outlined.ModeComment
import androidx.compose.material.icons.rounded.ArrowDownward
import androidx.compose.material.icons.rounded.ArrowUpward
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Bookmark
import androidx.compose.material.icons.rounded.BookmarkBorder
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.CheckCircleOutline
import androidx.compose.material.icons.rounded.Collections
import androidx.compose.material.icons.rounded.Gif
import androidx.compose.material.icons.rounded.Image
import androidx.compose.material.icons.rounded.Link
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material.icons.rounded.Newspaper
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.PlayCircleFilled
import androidx.compose.material.icons.rounded.PushPin
import androidx.compose.material.icons.rounded.Repeat
import androidx.compose.material.icons.rounded.Sell
import androidx.compose.material.icons.rounded.SentimentSatisfied
import androidx.compose.material.icons.rounded.Share
import androidx.compose.material.icons.rounded.Tune
import androidx.compose.material.icons.rounded.VisibilityOff
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.State
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.Color
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onVisibilityChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import coil3.compose.SubcomposeAsyncImage
import coil3.compose.AsyncImage
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.core.Analytics
import com.bennybar.luli_for_reddit.core.compactNumber
import com.bennybar.luli_for_reddit.core.timeAgo
import com.bennybar.luli_for_reddit.feature.foryou.showTuneSheet
import com.bennybar.luli_for_reddit.feature.media.GalleryCarousel
import com.bennybar.luli_for_reddit.feature.media.InlineVideo
import com.bennybar.luli_for_reddit.feature.media.NsfwBlur
import com.bennybar.luli_for_reddit.feature.media.postVideoUrl
import com.bennybar.luli_for_reddit.feature.post.hidePost
import com.bennybar.luli_for_reddit.feature.post.showPostActionsSheet
import com.bennybar.luli_for_reddit.feature.post.showReplySheet
import com.bennybar.luli_for_reddit.model.Post
import com.bennybar.luli_for_reddit.model.PostType
import com.bennybar.luli_for_reddit.nav.AppNavigator
import com.bennybar.luli_for_reddit.nav.LocalNavigator
import com.bennybar.luli_for_reddit.settings.PostDisplay
import com.bennybar.luli_for_reddit.settings.Settings
import com.bennybar.luli_for_reddit.settings.SwipeAction
import com.bennybar.luli_for_reddit.state.PostOverride
import com.bennybar.luli_for_reddit.state.PostOverrides
import com.bennybar.luli_for_reddit.ui.theme.LocalVoteColors
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

/**
 * The actions behind a card. Network calls run on the app scope, so a vote
 * still completes (or rolls back) if the card scrolls away mid-request.
 */
@Immutable
private class PostActions(val post: Post, val nav: AppNavigator) {
    // Vote / score / saved / comment-count live in the shared post-overrides
    // store (keyed by post id) so the card stays in sync with the post-detail
    // screen and survives scrolling.
    private val ov: PostOverride get() = app.postOverrides.effective(post)

    fun vote(dir: Int) {
        val overrides = app.postOverrides
        val current = PostOverrides.dirOf(ov.likes)
        val target = if (current == dir) 0 else dir
        overrides.setVote(post, target)
        val learner = app.forYou.learner
        learner.vote(post, current, target)
        app.scope.launch {
            try {
                app.repository.vote(post.fullname, target)
            } catch (e: Exception) {
                overrides.setVote(post, current) // revert
                learner.vote(post, target, current)
                nav.showActionError("vote", e)
            }
        }
    }

    fun toggleSave() {
        val overrides = app.postOverrides
        val next = !ov.saved
        overrides.setSaved(post, next)
        val learner = app.forYou.learner
        learner.save(post, next)
        app.scope.launch {
            try {
                app.repository.setSaved(post.fullname, next)
            } catch (e: Exception) {
                overrides.setSaved(post, !next)
                learner.save(post, !next)
                nav.showActionError(if (next) "save" else "unsave", e)
            }
        }
    }

    fun openDetail() {
        Analytics.track("post_opened")
        if (app.settings.value.trackHistory) app.history.markViewed(post)
        app.forYou.learner.open(post)
        nav.openPost(post)
    }

    fun openMedia() {
        val p = post
        // Viewing media is engagement too (slightly stronger than a plain open).
        if (p.type != PostType.SELF) app.forYou.learner.viewMedia(p)
        when (p.type) {
            PostType.IMAGE -> nav.openImage(p.previewUrl ?: p.url, title = p.title)
            // Play reddit's mp4 variant (small, loops); else the animated .gif.
            PostType.GIF -> if (p.gifMp4Url != null) {
                nav.openVideo(p.gifMp4Url, title = p.title, downloadUrl = p.gifMp4Url, externalUrl = p.url)
            } else {
                nav.openImage(p.url, title = p.title)
            }
            PostType.GALLERY -> nav.openGallery(p.gallery, title = p.title)
            PostType.VIDEO -> nav.openPostVideo(p)
            PostType.LINK -> nav.openInBrowser(p.url)
            PostType.SELF -> openDetail()
        }
    }

    fun openSubreddit() = nav.openSubreddit(post.subreddit)

    fun openAuthor() {
        val a = post.author
        if (a.isNotEmpty() && a != "[deleted]") nav.openUser(a)
    }

    /** Long-press → "Tune For You": why it's here, and explicit More/Less. */
    fun tune() = showTuneSheet(post)

    fun more() = showPostActionsSheet(post)

    fun toggleRead(seen: Boolean) {
        if (seen) app.history.removeViewed(post.id) else app.history.markViewed(post)
    }

    fun reply() {
        app.scope.launch {
            val reply = showReplySheet(post.fullname, parentDepth = -1)
            if (reply != null) app.postOverrides.bumpComments(post, 1)
        }
    }

    fun hide() {
        app.scope.launch { hidePost(post) }
    }

    fun share() {
        // Sharing is a strong interest signal (as in the ⋮ sheet).
        app.forYou.learner.share(post)
        nav.share("https://reddit.com${post.permalink}", subject = post.title)
    }
}

/** The live override for one post: only this card recomposes when it changes. */
@Composable
private fun rememberOverride(post: Post): State<PostOverride?> {
    val flow = remember(post.id) { app.postOverrides.state.map { it[post.id] }.distinctUntilChanged() }
    return flow.collectAsState(initial = app.postOverrides.state.value[post.id])
}

/** Whether [post] is in the local history (read). */
@Composable
fun rememberSeen(postId: String): State<Boolean> {
    val flow = remember(postId) { app.history.ids.map { postId in it }.distinctUntilChanged() }
    return flow.collectAsState(initial = app.history.contains(postId))
}

/**
 * A post in a feed, in the layout chosen in Settings (Default / Cards / Mini
 * cards / Calm / Calm cards). Calm posts are segments of one connected list:
 * [calmTop] / [calmBottom] are its corner radii (big at the list's ends).
 */
@Composable
fun PostCard(post: Post, modifier: Modifier = Modifier, calmTop: Dp = CalmOuter, calmBottom: Dp = CalmOuter) {
    val settings by app.settings.state.collectAsState()
    val nav = LocalNavigator.current
    val actions = remember(post, nav) { PostActions(post, nav) }
    val seen by rememberSeen(post.id)
    val cs = MaterialTheme.colorScheme
    val votes = LocalVoteColors.current
    val reason = post.feedReason

    var outer: Modifier = modifier
    // For You impressions (shown-but-never-opened posts get demoted on the
    // next build) and "mark read on scroll" both need to know what was seen.
    // A card flung past mid-scroll wasn't really seen; counting it would bury
    // posts the user never had a chance to read. Only a card that sits ≥60%
    // visible for a second counts as shown.
    if (reason != null || settings.markReadOnScroll) {
        outer = outer.onVisibilityChanged(minDurationMs = 1000, minFractionVisible = 0.6f) { visible ->
            if (!visible) return@onVisibilityChanged
            if (post.feedReason != null) app.forYou.learner.impression(post)
            // "Mark read on scroll": a card actually seen counts as read (history
            // only — no interest learning, which is for real engagement).
            val s = app.settings.value
            if (s.markReadOnScroll && s.trackHistory) app.history.markViewed(post)
        }
    }

    // What a swipe on this card does, per Settings → Swipe actions.
    fun swipe(action: SwipeAction): SwipeSpec? = when (action) {
        SwipeAction.UPVOTE -> SwipeSpec(action.icon, votes.up) { actions.vote(1) }
        SwipeAction.DOWNVOTE -> SwipeSpec(action.icon, votes.down) { actions.vote(-1) }
        SwipeAction.SAVE -> SwipeSpec(action.icon, cs.primary) { actions.toggleSave() }
        SwipeAction.REPLY -> SwipeSpec(action.icon, cs.tertiary) { actions.reply() }
        SwipeAction.HIDE -> SwipeSpec(action.icon, cs.error) { actions.hide() }
        SwipeAction.COLLAPSE, SwipeAction.NONE -> null
    }
    val startSpec = remember(settings.swipePostStart, actions, votes, cs) { swipe(settings.swipePostStart) }
    val endSpec = remember(settings.swipePostEnd, actions, votes, cs) { swipe(settings.swipePostEnd) }

    // The whole card, "why" banner included, is the swipe target (as Flutter).
    SwipeActions(start = startSpec, end = endSpec, modifier = outer, enabled = settings.swipeActions) {
        Column {
            // "Why you're seeing this" banner (For You feed only). Calm shows
            // the reason in the card header instead.
            if (reason != null && !settings.postDisplay.isCalm) ReasonRow(reason, onTune = actions::tune)
            // Dim already-viewed posts when history tracking is on. A
            // page-colour veil looks the same as 55% opacity — the card sits on
            // the page surface — without re-rendering the whole card, images
            // and all, into an offscreen layer every frame it scrolls.
            val veil = if (seen && settings.trackHistory) cs.surface.copy(alpha = 0.45f) else Color.Transparent
            val dim = Modifier.drawWithContent {
                drawContent()
                if (veil.alpha > 0f) drawRect(veil)
            }
            when (settings.postDisplay) {
                PostDisplay.LARGE -> LargeCard(post, actions, settings, dim)
                PostDisplay.CARD -> CardsCard(post, actions, settings, dim)
                PostDisplay.MINI -> MiniCard(post, actions, settings, dim)
                PostDisplay.CALM -> CalmCard(post, actions, settings, dim, calmTop, calmBottom)
                PostDisplay.CALM_CARDS -> CalmCardsCard(post, actions, settings, dim)
            }
        }
    }
}

@Composable
private fun ReasonRow(reason: String, onTune: () -> Unit) {
    val cs = MaterialTheme.colorScheme
    Row(
        Modifier.fillMaxWidth()
            // Long-press anywhere on the card tunes For You, banner included.
            .pointerInput(onTune) { detectTapGestures(onLongPress = { onTune() }) }
            .padding(start = 18.dp, top = 2.dp, end = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Rounded.AutoAwesome, null, Modifier.size(13.dp), tint = cs.primary)
        Spacer(Modifier.width(6.dp))
        Text(
            reason,
            Modifier.weight(1f),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            fontSize = 11.5.sp,
            fontWeight = FontWeight.SemiBold,
            color = cs.primary,
        )
        // Discoverable entry to the feed-tuning sheet (also on long-press)
        // so "show less from this subreddit" isn't hidden.
        Row(
            Modifier.clip(RoundedCornerShape(20.dp)).clickable(onClick = onTune).padding(horizontal = 8.dp, vertical = 2.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Rounded.Tune, null, Modifier.size(13.dp), tint = cs.primary)
            Spacer(Modifier.width(4.dp))
            Text("Tune", fontSize = 11.5.sp, fontWeight = FontWeight.SemiBold, color = cs.primary)
        }
    }
}

private val TitleLineHeight = 1.25.em

@Composable
private fun LargeCard(p: Post, a: PostActions, s: Settings, dim: Modifier) {
    val cs = MaterialTheme.colorScheme
    BloomCard(dim, onClick = a::openDetail, onLongClick = a::tune) {
        Column(Modifier.padding(start = 16.dp, top = 14.dp, end = 8.dp, bottom = 6.dp)) {
            Header(p, a)
            Spacer(Modifier.height(10.dp))
            Text(
                p.title,
                style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold, lineHeight = TitleLineHeight),
            )
            p.linkFlairText?.let {
                Spacer(Modifier.height(8.dp))
                Flair(it)
            }
            CrosspostLine(p)
            Spacer(Modifier.height(12.dp))
            Media(p, a, s)
            PollOptions(p)
            if (p.selftext.isNotEmpty()) {
                Spacer(Modifier.height(4.dp))
                Text(
                    p.selftext,
                        maxLines = 3,
                    overflow = TextOverflow.Ellipsis,
                    style = MaterialTheme.typography.bodyMedium,
                    color = cs.onSurfaceVariant,
                )
            }
            ActionsRow(p, a)
        }
    }
}

/**
 * "Cards" — a full-width card like the default, but with media capped to a
 * shorter banner height so cards stay compact and scannable.
 */
@Composable
private fun CardsCard(p: Post, a: PostActions, s: Settings, dim: Modifier) {
    val cs = MaterialTheme.colorScheme
    BloomCard(dim, onClick = a::openDetail, onLongClick = a::tune) {
        Column(Modifier.padding(start = 16.dp, top = 14.dp, end = 8.dp, bottom = 6.dp)) {
            Header(p, a)
            Spacer(Modifier.height(10.dp))
            Text(
                p.title,
                style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold, lineHeight = TitleLineHeight),
            )
            p.linkFlairText?.let {
                Spacer(Modifier.height(8.dp))
                Flair(it)
            }
            CrosspostLine(p)
            Spacer(Modifier.height(12.dp))
            BannerMedia(p, a, s, 180.dp)
            PollOptions(p)
            if (p.selftext.isNotEmpty()) {
                Spacer(Modifier.height(4.dp))
                Text(
                    p.selftext,
                        maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    style = MaterialTheme.typography.bodyMedium,
                    color = cs.onSurfaceVariant,
                )
            }
            ActionsRow(p, a)
        }
    }
}

/** "Mini cards" — compact: header + title with a small side thumbnail, full action row below. */
@Composable
private fun MiniCard(p: Post, a: PostActions, s: Settings, dim: Modifier) {
    BloomCard(dim, onClick = a::openDetail, onLongClick = a::tune) {
        Column(Modifier.padding(start = 14.dp, top = 12.dp, end = 6.dp, bottom = 4.dp)) {
            Header(p, a)
            Spacer(Modifier.height(8.dp))
            Row {
                Column(Modifier.weight(1f)) {
                    Text(
                        p.title,
                        maxLines = 3,
                        overflow = TextOverflow.Ellipsis,
                        style = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.Bold, lineHeight = TitleLineHeight),
                    )
                    p.linkFlairText?.let {
                        Spacer(Modifier.height(6.dp))
                        Flair(it)
                    }
                    CrosspostLine(p)
                }
                if (p.type != PostType.SELF) {
                    Spacer(Modifier.width(12.dp))
                    Thumb(p, a, s, 88.dp)
                }
            }
            ActionsRow(p, a)
        }
    }
}

/** Feed preview URL, mid-resolution when the data-saver setting is on. */
private fun cardImg(p: Post, s: Settings): String? {
    val preview = if (s.midResThumbnails) p.previewMedUrl ?: p.previewUrl else p.previewUrl
    if (preview != null) return preview
    // Direct image links (preview.redd.it / i.redd.it / i.imgur.com) carry no
    // preview block — use the URL itself.
    if (p.type == PostType.IMAGE || p.type == PostType.GIF) return p.url
    return null
}

/** The image URL a full-width card shows (shared with the list's prefetcher). */
fun feedImageUrl(p: Post, s: Settings): String? = cardImg(p, s) ?: p.gallery.firstOrNull()?.url

private fun blurOf(p: Post, s: Settings) = (p.over18 && s.blurNsfw) || p.spoiler
private fun blurLabel(p: Post, s: Settings) = if (p.over18 && s.blurNsfw) "NSFW" else "Spoiler"

/** Full-width media for the "Cards" layout, cover-cropped to [height]. */
@Composable
private fun BannerMedia(p: Post, a: PostActions, s: Settings, height: Dp) {
    val cs = MaterialTheme.colorScheme
    if (p.type == PostType.SELF) return
    if (p.type == PostType.LINK) {
        LinkPreview(p, a)
        return
    }
    val blur = blurOf(p, s)
    if (p.type == PostType.GALLERY && p.gallery.isNotEmpty()) {
        NsfwBlur(blur, Modifier.padding(bottom = 4.dp), label = blurLabel(p, s)) {
            GalleryCarousel(p.gallery, title = p.title, height = height)
        }
        return
    }
    val url = feedImageUrl(p, s)
    // Inline autoplay for videos (when enabled and not NSFW-blurred).
    if (p.type == PostType.VIDEO && !blur && s.autoplayMedia) {
        val vurl = postVideoUrl(p)
        if (vurl.isNotEmpty() && !vurl.lowercase().endsWith(".gif")) {
            Box(Modifier.padding(bottom = 4.dp).clip(RoundedCornerShape(16.dp))) {
                androidx.compose.runtime.key(p.id) {
                    InlineVideo(vurl, height = height, onTap = a::openMedia, poster = url)
                }
            }
            return
        }
    }
    NsfwBlur(blur, Modifier.padding(bottom = 4.dp), blurredImageUrl = p.blurredPreviewUrl, label = blurLabel(p, s)) {
        Box(
            Modifier
                .fillMaxWidth()
                .height(height)
                .clip(RoundedCornerShape(16.dp))
                .background(cs.surfaceContainerHighest)
                .clickable(onClick = a::openMedia),
        ) {
            if (url != null) FeedImage(url, Modifier.fillMaxSize())
            if (p.type == PostType.VIDEO || p.type == PostType.GIF) PlayBadge(Modifier.align(Alignment.Center))
            if (p.type == PostType.GIF) MediaPill("GIF", Icons.Rounded.Gif, Modifier.align(Alignment.TopEnd).padding(8.dp))
            if (p.type == PostType.GALLERY) {
                MediaPill("${p.gallery.size}", Icons.Rounded.Collections, Modifier.align(Alignment.TopEnd).padding(8.dp))
            }
        }
    }
}

/** Small square thumbnail for the mini layout. */
@Composable
private fun Thumb(p: Post, a: PostActions, s: Settings, size: Dp) {
    val cs = MaterialTheme.colorScheme
    val url = cardImg(p, s) ?: p.gallery.firstOrNull()?.url ?: p.thumbnailUrl
    val blur = blurOf(p, s)
    val px = with(LocalDensity.current) { size.roundToPx() }
    Box(
        Modifier.size(size).clip(RoundedCornerShape(14.dp)).background(cs.surfaceContainerHighest),
        contentAlignment = Alignment.Center,
    ) {
        if (url != null && !blur) {
            // Cover-cropped into a square: 2× leaves room for a 2:1 image.
            SubcomposeAsyncImage(
                model = rememberSizedRequest(url, px * 2),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
                error = { Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Icon(Icons.Rounded.Link, null, tint = cs.onSurfaceVariant) } },
            )
        } else {
            Icon(
                when {
                    blur -> Icons.Rounded.VisibilityOff
                    p.type == PostType.LINK -> Icons.Rounded.Link
                    else -> Icons.Rounded.Image
                },
                null,
                tint = cs.onSurfaceVariant,
            )
        }
        if (p.type == PostType.VIDEO) Icon(Icons.Rounded.PlayCircleFilled, null, Modifier.size(26.dp), tint = Color.White)
    }
}

@Composable
private fun Header(p: Post, a: PostActions) {
    val cs = MaterialTheme.colorScheme
    Row(verticalAlignment = Alignment.CenterVertically) {
        LetterAvatar(
            p.subreddit,
            size = 28.dp,
            container = cs.secondaryContainer,
            content = cs.onSecondaryContainer,
            fontSize = 13.sp,
            modifier = Modifier.clickable(onClick = a::openSubreddit),
        )
        Spacer(Modifier.width(10.dp))
        // Tapping the "u/author" part of the header opens their profile; the
        // rest opens the subreddit.
        val text = remember(p.id, cs) {
            buildAnnotatedString {
                withStyle(SpanStyle(fontWeight = FontWeight.SemiBold, color = cs.onSurface)) {
                    append(p.subredditPrefixed.ifEmpty { "r/${p.subreddit}" })
                }
                append("  ·  ")
                withLink(LinkAnnotation.Clickable("author") { a.openAuthor() }) { append("u/${p.author}") }
                append("  ·  ${timeAgo(p.createdUtc)}")
            }
        }
        Text(
            text,
            Modifier.weight(1f).clickable(onClick = a::openSubreddit),
            fontSize = 13.sp,
            color = cs.onSurfaceVariant,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        if (p.stickied) Icon(Icons.Rounded.PushPin, null, Modifier.size(16.dp), tint = cs.primary)
        if (p.over18) {
            Text(
                "NSFW",
                Modifier
                    .padding(start = 6.dp)
                    .background(cs.errorContainer, RoundedCornerShape(6.dp))
                    .padding(horizontal = 6.dp, vertical = 2.dp),
                fontSize = 10.sp,
                fontWeight = FontWeight.Bold,
                color = cs.onErrorContainer,
            )
        }
    }
}

@Composable
private fun Flair(text: String) {
    val cs = MaterialTheme.colorScheme
    Text(
        text,
        Modifier.background(cs.surfaceContainerHighest, RoundedCornerShape(8.dp)).padding(horizontal = 10.dp, vertical = 4.dp),
        fontSize = 12.sp,
        color = cs.onSurfaceVariant,
    )
}

/** "Crossposted from r/x" (the media comes from the original post). */
@Composable
private fun CrosspostLine(p: Post) {
    val from = p.crosspostFrom ?: return
    val cs = MaterialTheme.colorScheme
    Spacer(Modifier.height(8.dp))
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(Icons.Rounded.Repeat, null, Modifier.size(14.dp), tint = cs.onSurfaceVariant)
        Spacer(Modifier.width(6.dp))
        Text("Crossposted from r/$from", fontSize = 12.sp, color = cs.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** A poll's options (read-only: Reddit's API can't vote in polls). */
@Composable
private fun PollOptions(p: Post) {
    if (p.pollOptions.isEmpty()) return
    val cs = MaterialTheme.colorScheme
    Column(Modifier.padding(top = 4.dp, bottom = 4.dp)) {
        for (opt in p.pollOptions) {
            Text(
                opt,
                Modifier
                    .fillMaxWidth()
                    .padding(bottom = 8.dp)
                    .background(cs.surfaceContainerHigh, RoundedCornerShape(14.dp))
                    .padding(horizontal = 14.dp, vertical = 12.dp),
            )
        }
        Text("Vote in the official app", fontSize = 12.sp, color = cs.onSurfaceVariant)
    }
}

/** Default layout media: gallery carousel, aspect-correct preview, or link card. */
@Composable
private fun Media(p: Post, a: PostActions, s: Settings) {
    val blur = blurOf(p, s)
    when (p.type) {
        PostType.GALLERY -> if (p.gallery.isNotEmpty()) {
            NsfwBlur(blur, Modifier.padding(bottom = 4.dp), label = blurLabel(p, s)) {
                GalleryCarousel(p.gallery, title = p.title)
            }
        } else {
            NsfwBlur(blur, blurredImageUrl = p.blurredPreviewUrl, label = blurLabel(p, s)) { MediaPreview(p, a, s) }
        }
        PostType.IMAGE, PostType.GIF, PostType.VIDEO ->
            NsfwBlur(blur, blurredImageUrl = p.blurredPreviewUrl, label = blurLabel(p, s)) { MediaPreview(p, a, s) }
        PostType.LINK -> LinkPreview(p, a)
        PostType.SELF -> {}
    }
}

@Composable
private fun MediaPreview(p: Post, a: PostActions, s: Settings) {
    val cs = MaterialTheme.colorScheme
    // Mid-res when the data-saver setting is on, like the other layouts.
    val preview = if (s.midResThumbnails) p.previewMedUrl ?: p.previewUrl else p.previewUrl
    val url = preview ?: p.gallery.firstOrNull()?.url
    val w = p.previewWidth
    val h = p.previewHeight
    val aspect = if (w != null && h != null && h > 0) w.toFloat() / h else 16f / 9f
    Box(
        Modifier
            .padding(bottom = 4.dp)
            .fillMaxWidth()
            .aspectRatio(aspect.coerceIn(0.5f, 2.0f))
            .clip(RoundedCornerShape(16.dp))
            .background(cs.surfaceContainerHighest)
            .clickable(onClick = a::openMedia),
    ) {
        if (url != null) FeedImage(url, Modifier.fillMaxSize(), brokenIcon = true)
        if (p.type == PostType.VIDEO) PlayBadge(Modifier.align(Alignment.Center))
        if (p.type == PostType.GALLERY) {
            MediaPill("${p.gallery.size}", Icons.Rounded.Collections, Modifier.align(Alignment.TopEnd).padding(8.dp))
        }
        if (p.type == PostType.GIF) MediaPill("GIF", null, Modifier.align(Alignment.TopStart).padding(8.dp))
    }
}

/** A cover-cropped feed image decoded at screen width (the prefetcher uses the same request). */
@Composable
private fun FeedImage(url: String, modifier: Modifier, brokenIcon: Boolean = false) {
    val cs = MaterialTheme.colorScheme
    val request = rememberSizedRequest(url, feedDecodeWidth())
    if (brokenIcon) {
        SubcomposeAsyncImage(
            model = request,
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = modifier,
            error = {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Icon(Icons.Outlined.BrokenImage, null, tint = cs.onSurfaceVariant)
                }
            },
        )
    } else {
        AsyncImage(model = request, contentDescription = null, contentScale = ContentScale.Crop, modifier = modifier)
    }
}

@Composable
private fun LinkPreview(p: Post, a: PostActions) {
    val cs = MaterialTheme.colorScheme
    Row(
        Modifier
            .padding(bottom = 4.dp)
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(cs.surfaceContainerHighest)
            .clickable(onClick = a::openMedia),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (p.thumbnailUrl != null) {
            val px = with(LocalDensity.current) { 72.dp.roundToPx() }
            AsyncImage(
                model = rememberSizedRequest(p.thumbnailUrl, px * 2),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.size(72.dp).clip(RoundedCornerShape(topStart = 16.dp, bottomStart = 16.dp)),
            )
        } else {
            Box(Modifier.size(72.dp), contentAlignment = Alignment.Center) {
                Icon(Icons.Rounded.Link, null, tint = cs.onSurfaceVariant)
            }
        }
        Text(
            p.domain,
            Modifier.weight(1f).padding(horizontal = 12.dp),
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            color = cs.onSurfaceVariant,
        )
        Icon(Icons.AutoMirrored.Rounded.OpenInNew, null, Modifier.padding(end = 12.dp).size(18.dp), tint = cs.onSurfaceVariant)
    }
}

@Composable
private fun ActionsRow(p: Post, a: PostActions) {
    val cs = MaterialTheme.colorScheme
    // Live values from the shared overrides store (kept in sync with the detail).
    val ov by rememberOverride(p)
    val likes = if (ov != null) ov!!.likes else p.likes
    val score = ov?.score ?: p.score
    val saved = ov?.saved ?: p.saved
    val numComments = ov?.numComments ?: p.numComments
    Row(verticalAlignment = Alignment.CenterVertically) {
        VotePill(score, likes, onUp = { a.vote(1) }, onDown = { a.vote(-1) })
        Spacer(Modifier.width(8.dp))
        CountChip(Icons.Outlined.ModeComment, compactNumber(numComments), onClick = a::openDetail)
        Spacer(Modifier.weight(1f))
        ReadToggle(p, a)
        IconButton(onClick = a::toggleSave) {
            Icon(
                if (saved) Icons.Rounded.Bookmark else Icons.Rounded.BookmarkBorder,
                if (saved) "Unsave" else "Save",
                tint = if (saved) cs.primary else cs.onSurfaceVariant,
            )
        }
        IconButton(onClick = a::more) { Icon(Icons.Rounded.MoreVert, "More", tint = cs.onSurfaceVariant) }
    }
}

/**
 * "Read" toggle shown on every post card (left of Save). Marks the post as
 * read/unread in local history; read posts get a filled, accent check.
 */
@Composable
private fun ReadToggle(p: Post, a: PostActions) {
    val cs = MaterialTheme.colorScheme
    val seen by rememberSeen(p.id)
    IconButton(onClick = { a.toggleRead(seen) }) {
        Icon(
            if (seen) Icons.Rounded.CheckCircle else Icons.Rounded.CheckCircleOutline,
            if (seen) "Mark as unread" else "Mark as read",
            tint = if (seen) cs.primary else cs.onSurfaceVariant,
        )
    }
}

/** Bloom "split" votes: a soft pill holding up / count / down. */
@Composable
fun VotePill(score: Int, likes: Boolean?, onUp: () -> Unit, onDown: () -> Unit, modifier: Modifier = Modifier) {
    val cs = MaterialTheme.colorScheme
    val votes = LocalVoteColors.current
    val up = likes == true
    val down = likes == false
    val countColor = if (up) votes.up else if (down) votes.down else cs.onSurfaceVariant
    Row(
        modifier.background(cs.surfaceContainerHigh, CircleShape),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        MiniButton(Icons.Rounded.ArrowUpward, if (up) votes.up else cs.onSurfaceVariant, "Upvote", onUp)
        Text(compactNumber(score), fontWeight = FontWeight.Bold, color = countColor)
        MiniButton(Icons.Rounded.ArrowDownward, if (down) votes.down else cs.onSurfaceVariant, "Downvote", onDown)
    }
}

@Composable
private fun MiniButton(icon: ImageVector, tint: Color, label: String, onClick: () -> Unit) {
    // Flutter's VisualDensity.compact IconButton: a 40dp target, 20dp icon.
    Box(
        Modifier.size(40.dp).clip(CircleShape).clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) { Icon(icon, label, Modifier.size(20.dp), tint = tint) }
}

@Composable
private fun CountChip(icon: ImageVector, label: String, onClick: () -> Unit) {
    val cs = MaterialTheme.colorScheme
    Row(
        Modifier
            .clip(RoundedCornerShape(20.dp))
            .background(cs.surfaceContainerHighest)
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Icon(icon, null, Modifier.size(18.dp), tint = cs.onSurfaceVariant)
        Text(label, color = cs.onSurfaceVariant)
    }
}

@Composable
private fun PlayBadge(modifier: Modifier = Modifier) {
    Box(
        modifier.background(Color.Black.copy(alpha = 0.54f), CircleShape).padding(14.dp),
        contentAlignment = Alignment.Center,
    ) { Icon(Icons.Rounded.PlayArrow, "Play", Modifier.size(36.dp), tint = Color.White) }
}

@Composable
private fun MediaPill(label: String, icon: ImageVector?, modifier: Modifier = Modifier) {
    Row(
        modifier
            .background(Color.Black.copy(alpha = 0.54f), RoundedCornerShape(10.dp))
            .padding(horizontal = 8.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) {
            Icon(icon, null, Modifier.size(14.dp), tint = Color.White)
            Spacer(Modifier.width(4.dp))
        }
        Text(label, color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold)
    }
}

// ---------------------------------------------------------------------------
// Calm layout
// ---------------------------------------------------------------------------

/** Outer corner of a Calm list's ends / a Calm card; segments meet at [CalmInner]. */
val CalmOuter = 28.dp
private val CalmInner = 6.dp
/** Gap between connected segments (Calm posts; a Calm card's parts). */
val CalmGap = 3.dp
/** Expressive media: round corners with one tighter corner. */
private val CalmExpressiveMedia = RoundedCornerShape(topStart = 24.dp, topEnd = 24.dp, bottomEnd = 24.dp, bottomStart = 8.dp)

/**
 * Calm's surfaces. In light mode surfaceContainerLow is almost the page colour,
 * so cards were lost in one off-white sheet: cards use a clearly tinted
 * container. Dark mode already contrasts.
 */
@Composable
internal fun calmCardColor(): Color {
    val cs = MaterialTheme.colorScheme
    return if (cs.surface.luminance() > 0.5f) cs.surfaceContainerHigh else cs.surfaceContainerLow
}

/** True inside a Calm card: its controls go a lighter tint (light mode) to stand out from the card. */
internal val LocalCalmOnCard = staticCompositionLocalOf { false }

@Composable
internal fun calmControlColor(): Color {
    val cs = MaterialTheme.colorScheme
    val light = cs.surface.luminance() > 0.5f
    return if (light && LocalCalmOnCard.current) cs.surfaceContainerLow else cs.surfaceContainerHigh
}

/**
 * The feed's Calm button groups: a solid secondary tone (deepened a touch in
 * light mode, where secondaryContainer is close to the card).
 */
@Composable
private fun calmButtonColor(): Color {
    val cs = MaterialTheme.colorScheme
    return if (cs.surface.luminance() > 0.5f) cs.primary.copy(alpha = 0.10f).compositeOver(cs.secondaryContainer) else cs.secondaryContainer
}

/** Live vote / save / comment state of a post (optimistic overrides first). */
private class CalmLive(val likes: Boolean?, val score: Int, val saved: Boolean, val numComments: Int)

@Composable
private fun rememberCalmLive(p: Post): CalmLive {
    val ov by rememberOverride(p)
    val o = ov
    return CalmLive(
        likes = if (o != null) o.likes else p.likes,
        score = o?.score ?: p.score,
        saved = o?.saved ?: p.saved,
        numComments = o?.numComments ?: p.numComments,
    )
}

/**
 * "Calm" — posts as segments of one connected list (3dp apart, big corners
 * only at the list's ends): a rounded-square avatar header, a bold title, a
 * flair pill, expressive media and a connected [↑ score][↓][comments] group.
 * Mark-read lives in the ⋮ sheet.
 */
@Composable
private fun CalmCard(p: Post, a: PostActions, s: Settings, dim: Modifier, top: Dp, bottom: Dp) {
    val live = rememberCalmLive(p)
    val shape = RoundedCornerShape(topStart = top, topEnd = top, bottomStart = bottom, bottomEnd = bottom)
    CompositionLocalProvider(LocalCalmOnCard provides true) {
        BloomCard(Modifier.padding(horizontal = 2.dp).then(dim), onClick = a::openDetail, onLongClick = a::tune, shape = shape, color = calmCardColor()) {
            Column(Modifier.padding(start = 16.dp, top = 14.dp, end = 10.dp, bottom = 10.dp)) {
                Column(Modifier.padding(end = 6.dp)) { CalmBody(p, a, s, CalmExpressiveMedia) }
                Row(Modifier.padding(top = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                    CalmActionGroup(live, a, withComments = true)
                    Spacer(Modifier.weight(1f))
                    CalmShareSave(live, a)
                }
            }
        }
    }
}

/**
 * "Calm cards" — each post its own connected group: the content, the media
 * (edge to edge) and the actions as separate segments, 3dp apart.
 */
@Composable
private fun CalmCardsCard(p: Post, a: PostActions, s: Settings, dim: Modifier) {
    val live = rememberCalmLive(p)
    val color = calmCardColor()
    val hasMedia = p.type != PostType.SELF
    CompositionLocalProvider(LocalCalmOnCard provides true) {
        Column(Modifier.padding(horizontal = 2.dp).then(dim), verticalArrangement = Arrangement.spacedBy(CalmGap)) {
            BloomCard(
                onClick = a::openDetail,
                onLongClick = a::tune,
                shape = RoundedCornerShape(topStart = CalmOuter, topEnd = CalmOuter, bottomStart = CalmInner, bottomEnd = CalmInner),
                color = color,
            ) {
                Column(Modifier.padding(start = 16.dp, top = 14.dp, end = 10.dp, bottom = 14.dp)) {
                    Column(Modifier.padding(end = 6.dp)) { CalmBody(p, a, s, mediaShape = null) }
                }
            }
            if (hasMedia) CalmMedia(p, a, s, RoundedCornerShape(CalmInner), topPad = 0.dp)
            BloomCard(
                onClick = a::openDetail,
                onLongClick = a::tune,
                shape = RoundedCornerShape(topStart = CalmInner, topEnd = CalmInner, bottomStart = CalmOuter, bottomEnd = CalmOuter),
                color = color,
            ) {
                Row(Modifier.padding(start = 10.dp, top = 8.dp, end = 6.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    CalmActionGroup(live, a, withComments = false)
                    Spacer(Modifier.width(8.dp))
                    CalmButtonGroup(listOf(CalmButton(Icons.Outlined.ModeComment, compactNumber(live.numComments), null, null, a::openDetail)))
                    Spacer(Modifier.weight(1f))
                    CalmShareSave(live, a)
                }
            }
        }
    }
}

/** Header, title, flair, crosspost, media (when [mediaShape] is set), poll and selftext. */
@Composable
private fun CalmBody(p: Post, a: PostActions, s: Settings, mediaShape: androidx.compose.ui.graphics.Shape?) {
    val cs = MaterialTheme.colorScheme
    CalmHeader(p, a)
    Text(
        p.title,
        Modifier.padding(top = 10.dp),
        fontSize = 18.sp,
        fontWeight = FontWeight.SemiBold,
        lineHeight = 1.3.em,
        letterSpacing = (-0.1).sp,
        color = cs.onSurface,
    )
    p.linkFlairText?.let { CalmFlair(it, Modifier.padding(top = 8.dp)) }
    CrosspostLine(p)
    if (mediaShape != null) CalmMedia(p, a, s, mediaShape)
    if (p.pollOptions.isNotEmpty()) {
        Spacer(Modifier.height(10.dp))
        PollOptions(p)
    }
    if (p.selftext.isNotEmpty()) {
        Text(
            p.selftext,
            Modifier.padding(top = 6.dp),
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            fontSize = 14.sp,
            color = cs.onSurfaceVariant,
        )
    }
}

/** [↑ score][↓] (+ [comments] when [withComments]) as one connected button group. */
@Composable
private fun CalmActionGroup(live: CalmLive, a: PostActions, withComments: Boolean) {
    val votes = LocalVoteColors.current
    val up = live.likes == true
    val down = live.likes == false
    val buttons = buildList {
        add(CalmButton(Icons.Rounded.ArrowUpward, compactNumber(live.score), "Upvote", if (up) votes.up else null, { a.vote(1) }, labelTint = if (down) votes.down else null))
        add(CalmButton(Icons.Rounded.ArrowDownward, null, "Downvote", if (down) votes.down else null, { a.vote(-1) }))
        if (withComments) add(CalmButton(Icons.Outlined.ModeComment, compactNumber(live.numComments), null, null, a::openDetail))
    }
    CalmButtonGroup(buttons)
}

@Composable
private fun CalmShareSave(live: CalmLive, a: PostActions) {
    val cs = MaterialTheme.colorScheme
    CalmGhost(Icons.Rounded.Share, "Share", cs.onSurfaceVariant, a::share, size = 40.dp)
    CalmGhost(
        if (live.saved) Icons.Rounded.Bookmark else Icons.Rounded.BookmarkBorder,
        if (live.saved) "Unsave" else "Save",
        if (live.saved) cs.primary else cs.onSurfaceVariant,
        a::toggleSave,
        size = 40.dp,
    )
}

private class CalmButton(
    val icon: ImageVector,
    val label: String?,
    val clickLabel: String?,
    /** A vote colour: fills the button at 22% and colours its content. */
    val tint: Color?,
    val onClick: () -> Unit,
    val labelTint: Color? = null,
)

/** M3 Expressive connected button group: 40dp, outer corners round, inner 6dp, 3dp apart. */
@Composable
private fun CalmButtonGroup(buttons: List<CalmButton>) {
    val cs = MaterialTheme.colorScheme
    val base = calmButtonColor()
    val height = 40.dp
    val r = height / 2
    Row(horizontalArrangement = Arrangement.spacedBy(CalmGap)) {
        buttons.forEachIndexed { i, b ->
            val start = if (i == 0) r else CalmInner
            val end = if (i == buttons.lastIndex) r else CalmInner
            val bg = if (b.tint != null) b.tint.copy(alpha = 0.22f).compositeOver(base) else base
            val fg = b.tint ?: cs.onSecondaryContainer
            Row(
                Modifier
                    .height(height)
                    .clip(RoundedCornerShape(topStart = start, bottomStart = start, topEnd = end, bottomEnd = end))
                    .background(bg)
                    .clickable(onClickLabel = b.clickLabel, onClick = b.onClick)
                    .padding(start = if (i == 0) 14.dp else 12.dp, end = if (i == buttons.lastIndex) 14.dp else 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(b.icon, null, Modifier.size(19.dp), tint = fg)
                if (b.label != null) {
                    Spacer(Modifier.width(6.dp))
                    Text(b.label, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = b.labelTint ?: fg)
                }
            }
        }
    }
}

@Composable
private fun CalmHeader(p: Post, a: PostActions) {
    val cs = MaterialTheme.colorScheme
    // The subreddit is already the line above: drop a trailing " · r/sub" from the reason.
    val reason = p.feedReason?.removeSuffix(" · r/${p.subreddit}")?.removeSuffix(" · ${p.subredditPrefixed}")
    Row(verticalAlignment = Alignment.CenterVertically) {
        // Expressive: a rounded-square avatar in one of three tonal pairs,
        // picked per subreddit so a sub keeps its colour.
        val (bg, fg) = when (Math.floorMod(p.subreddit.lowercase().hashCode(), 3)) {
            0 -> cs.primaryContainer to cs.onPrimaryContainer
            1 -> cs.secondaryContainer to cs.onSecondaryContainer
            else -> cs.tertiaryContainer to cs.onTertiaryContainer
        }
        LetterAvatar(
            p.subreddit,
            size = 36.dp,
            container = bg,
            content = fg,
            modifier = Modifier.clickable(onClick = a::openSubreddit),
            shape = RoundedCornerShape(12.dp),
        )
        Spacer(Modifier.width(10.dp))
        Column(Modifier.weight(1f)) {
            Text(
                p.subredditPrefixed.ifEmpty { "r/${p.subreddit}" },
                Modifier.clickable(onClick = a::openSubreddit),
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold,
                color = cs.onSurface,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            if (reason != null) {
                // For You: why it's here, in place of the author. Tap → the
                // "why you're seeing this" / tune sheet.
                Row(Modifier.clickable(onClick = a::tune), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Rounded.AutoAwesome, null, Modifier.size(13.dp), tint = cs.primary)
                    Spacer(Modifier.width(4.dp))
                    Text(
                        reason,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Medium,
                        color = cs.primary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            } else {
                Text(
                    "u/${p.author} · ${timeAgo(p.createdUtc)}",
                    Modifier.clickable(onClick = a::openAuthor),
                    fontSize = 12.sp,
                    color = cs.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
        if (p.stickied) Icon(Icons.Rounded.PushPin, null, Modifier.size(16.dp), tint = cs.primary)
        if (p.over18) {
            Text(
                "NSFW",
                Modifier
                    .padding(start = 6.dp)
                    .background(cs.errorContainer, RoundedCornerShape(6.dp))
                    .padding(horizontal = 6.dp, vertical = 2.dp),
                fontSize = 10.sp,
                fontWeight = FontWeight.Bold,
                color = cs.onErrorContainer,
            )
        }
        Box(
            Modifier.size(36.dp).clip(CircleShape).clickable(onClick = a::more),
            contentAlignment = Alignment.Center,
        ) { Icon(Icons.Rounded.MoreVert, "More", Modifier.size(20.dp), tint = cs.onSurfaceVariant) }
    }
}

/** Calm media in [shape]: 16:10 cover crop, galleries, inline video, or a link block. */
@Composable
private fun CalmMedia(p: Post, a: PostActions, s: Settings, shape: androidx.compose.ui.graphics.Shape, topPad: Dp = 10.dp) {
    val cs = MaterialTheme.colorScheme
    if (p.type == PostType.SELF) return
    val blur = blurOf(p, s)
    val top = Modifier.padding(top = topPad)
    if (p.type == PostType.LINK) {
        val img = cardImg(p, s) ?: p.thumbnailUrl
        Column(top.fillMaxWidth().clip(shape).background(calmControlColor()).clickable(onClick = a::openMedia)) {
            if (img != null) {
                NsfwBlur(blur, blurredImageUrl = p.blurredPreviewUrl, label = blurLabel(p, s)) {
                    Box(Modifier.fillMaxWidth().aspectRatio(2f).background(cs.surfaceContainerHighest)) {
                        FeedImage(img, Modifier.fillMaxSize())
                    }
                }
            }
            Row(Modifier.padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Rounded.Link, null, Modifier.size(14.dp), tint = cs.onSurfaceVariant)
                Spacer(Modifier.width(6.dp))
                Text(p.domain, Modifier.weight(1f), fontSize = 12.sp, color = cs.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Icon(Icons.AutoMirrored.Rounded.OpenInNew, null, Modifier.size(14.dp), tint = cs.onSurfaceVariant)
            }
        }
        return
    }
    BoxWithConstraints(top.fillMaxWidth()) {
        val height = maxWidth * 10f / 16f
        if (p.type == PostType.GALLERY && p.gallery.isNotEmpty()) {
            NsfwBlur(blur, label = blurLabel(p, s)) {
                GalleryCarousel(p.gallery, Modifier.clip(shape), title = p.title, height = height)
            }
            return@BoxWithConstraints
        }
        val url = feedImageUrl(p, s)
        // Inline autoplay for videos (when enabled and not NSFW-blurred).
        if (p.type == PostType.VIDEO && !blur && s.autoplayMedia) {
            val vurl = postVideoUrl(p)
            if (vurl.isNotEmpty() && !vurl.lowercase().endsWith(".gif")) {
                Box(Modifier.clip(shape)) {
                    androidx.compose.runtime.key(p.id) {
                        InlineVideo(vurl, height = height, onTap = a::openMedia, poster = url)
                    }
                }
                return@BoxWithConstraints
            }
        }
        NsfwBlur(blur, blurredImageUrl = p.blurredPreviewUrl, label = blurLabel(p, s)) {
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(height)
                    .clip(shape)
                    .background(cs.surfaceContainerHighest)
                    .clickable(onClick = a::openMedia),
            ) {
                if (url != null) FeedImage(url, Modifier.fillMaxSize(), brokenIcon = true)
                if (p.type == PostType.VIDEO || p.type == PostType.GIF) PlayBadge(Modifier.align(Alignment.Center))
                if (p.type == PostType.GIF) MediaPill("GIF", Icons.Rounded.Gif, Modifier.align(Alignment.TopEnd).padding(8.dp))
                if (p.type == PostType.GALLERY) {
                    MediaPill("${p.gallery.size}", Icons.Rounded.Collections, Modifier.align(Alignment.TopEnd).padding(8.dp))
                }
            }
        }
    }
}

private val FlairShortcode = Regex(""":[A-Za-z0-9_+\-]+:""")
private val Whitespace = Regex("\\s+")

/** Flair text without Reddit's `:emoji:` shortcodes (":Discussion: Discussion" → "Discussion"). */
fun cleanFlair(text: String): String = text.replace(FlairShortcode, " ").replace(Whitespace, " ").trim()

/** A small icon matching common flair words (the flair's emoji images aren't in its text). */
private fun flairIcon(text: String): ImageVector {
    val t = text.lowercase()
    return when {
        "discuss" in t -> Icons.Outlined.ModeComment
        "question" in t || "help" in t -> Icons.AutoMirrored.Rounded.HelpOutline
        "news" in t -> Icons.Rounded.Newspaper
        "meme" in t || "humor" in t || "funny" in t -> Icons.Rounded.SentimentSatisfied
        t == "oc" || "image" in t || "photo" in t || "art" in t -> Icons.Rounded.Image
        "video" in t -> Icons.Rounded.PlayArrow
        else -> Icons.Rounded.Sell
    }
}

/** Calm flair pill: 26dp, surfaceContainerHigh, icon + cleaned text. Nothing when it's only emoji. */
@Composable
fun CalmFlair(raw: String, modifier: Modifier = Modifier) {
    val text = remember(raw) { cleanFlair(raw) }
    if (text.isEmpty()) return
    val cs = MaterialTheme.colorScheme
    Row(
        modifier
            .height(26.dp)
            .background(calmControlColor(), RoundedCornerShape(13.dp))
            .padding(start = 8.dp, end = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(flairIcon(text), null, Modifier.size(14.dp), tint = cs.primary)
        Spacer(Modifier.width(5.dp))
        Text(text, fontSize = 12.sp, fontWeight = FontWeight.Medium, color = cs.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/**
 * Calm's connected vote group: [↑ score][↓] segments (outer corners
 * [height]/2, inner 6, 2dp gap); the active segment takes the vote colour.
 */
@Composable
fun CalmVoteGroup(
    score: Int,
    likes: Boolean?,
    onUp: () -> Unit,
    onDown: () -> Unit,
    height: Dp = 36.dp,
    iconSize: Dp = 18.dp,
    hPad: Dp = 11.dp,
) {
    val votes = LocalVoteColors.current
    val up = likes == true
    val down = likes == false
    val r = height / 2
    Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
        CalmSegment(
            RoundedCornerShape(topStart = r, bottomStart = r, topEnd = 6.dp, bottomEnd = 6.dp),
            if (up) votes.up else null,
            height,
            hPad,
            "Upvote",
            onUp,
        ) { fg ->
            Icon(Icons.Rounded.ArrowUpward, null, Modifier.size(iconSize), tint = fg)
            Spacer(Modifier.width(4.dp))
            Text(compactNumber(score), fontSize = 13.sp, fontWeight = FontWeight.Medium, color = if (down) votes.down else fg)
        }
        CalmSegment(
            RoundedCornerShape(topStart = 6.dp, bottomStart = 6.dp, topEnd = r, bottomEnd = r),
            if (down) votes.down else null,
            height,
            hPad,
            "Downvote",
            onDown,
        ) { fg -> Icon(Icons.Rounded.ArrowDownward, null, Modifier.size(iconSize), tint = fg) }
    }
}

/** A solo Calm pill (icon + label), e.g. the comment count. */
@Composable
fun CalmPill(icon: ImageVector, label: String, onClick: (() -> Unit)?, height: Dp = 36.dp, iconSize: Dp = 17.dp, hPad: Dp = 11.dp) {
    CalmSegment(RoundedCornerShape(height / 2), null, height, hPad, null, onClick) { fg ->
        Icon(icon, null, Modifier.size(iconSize), tint = fg)
        Spacer(Modifier.width(4.dp))
        Text(label, fontSize = 13.sp, fontWeight = FontWeight.Medium, color = fg)
    }
}

/** One tonal segment; [tint] (a vote colour) fills it at 22% and colours its content. */
@Composable
private fun CalmSegment(
    shape: RoundedCornerShape,
    tint: Color?,
    height: Dp,
    hPad: Dp,
    label: String?,
    onClick: (() -> Unit)?,
    content: @Composable (Color) -> Unit,
) {
    val cs = MaterialTheme.colorScheme
    val base = calmControlColor()
    val bg = if (tint != null) tint.copy(alpha = 0.22f).compositeOver(base) else base
    val fg = tint ?: cs.onSurface
    Row(
        Modifier
            .height(height)
            .clip(shape)
            .background(bg)
            .then(if (onClick != null) Modifier.clickable(onClickLabel = label, onClick = onClick) else Modifier)
            .padding(horizontal = hPad),
        verticalAlignment = Alignment.CenterVertically,
    ) { content(fg) }
}

/** A borderless icon button (Calm's share / save). */
@Composable
fun CalmGhost(icon: ImageVector, label: String, tint: Color, onClick: () -> Unit, size: Dp = 36.dp, iconSize: Dp = 19.dp) {
    Box(Modifier.size(size).clip(CircleShape).clickable(onClick = onClick), contentAlignment = Alignment.Center) {
        Icon(icon, label, Modifier.size(iconSize), tint = tint)
    }
}
