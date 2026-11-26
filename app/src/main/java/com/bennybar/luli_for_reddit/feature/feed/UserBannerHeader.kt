package com.bennybar.luli_for_reddit.feature.feed

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material3.FilledTonalIconToggleButton
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.compose.AsyncImage
import coil3.request.ImageRequest
import coil3.toBitmap
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.core.compactNumber
import com.bennybar.luli_for_reddit.core.timeAgo
import com.bennybar.luli_for_reddit.feature.media.opensPicture
import com.bennybar.luli_for_reddit.model.RedditUser
import com.bennybar.luli_for_reddit.nav.LocalNavigator
import com.bennybar.luli_for_reddit.ui.userName
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

/**
 * A profile with the community page's header (#293): the bar's buttons, drawn over the
 * banner by the profile itself. [leading] is ← (or the side bar's ☰), null for none.
 */
class BannerBar(
    val leading: (@Composable () -> Unit)?,
    val actions: @Composable RowScope.() -> Unit,
)

/** The bar's row and the room under it, which the header never slides above. */
internal fun bannerBarHeight(top: Dp): Dp = top + BAR_ROW_TOP + 52.dp

/**
 * A profile's header as a community's (#293): with a banner, it under the status bar, the
 * picture over its foot and the name beside it; without one, no coloured band but the
 * picture big and centred, the name under it. Karma and the account's age under the name,
 * Follow as a round + / ✓, and the user's description in a card when they wrote one.
 */
@Composable
internal fun UserBannerHeader(
    user: RedditUser,
    canFollow: Boolean,
    onSwitchAccount: (() -> Unit)?,
    top: Dp,
    request: ImageRequest?,
    onLight: (Boolean) -> Unit,
    onFollowed: (Boolean) -> Unit,
) {
    val cs = MaterialTheme.colorScheme
    val picture = user.iconUrl?.let { Modifier.opensPicture(it, "u/${user.name}") } ?: Modifier
    if (user.bannerUrl != null) {
        val scope = rememberCoroutineScope()
        val density = LocalDensity.current
        // As the community header's: a banner too small to fill this becomes a soft wash of
        // its colours with the banner itself sharp across it (#294).
        var soft by remember(user.bannerUrl) { mutableStateOf(false) }
        BoxWithConstraints(Modifier.fillMaxWidth()) {
            val boxW = with(density) { maxWidth.roundToPx() }
            val bannerPx = with(density) { (top + BANNER.dp).roundToPx() }
            val barPx = with(density) { (top + BAR_ROW_TOP + 48.dp).toPx() }
            Box(Modifier.fillMaxWidth().height(top + BANNER.dp).background(cs.primaryContainer)) {
                if (request != null) {
                    AsyncImage(
                        model = request,
                        contentDescription = null,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.fillMaxSize().then(if (soft) Modifier.blur(30.dp) else Modifier),
                        onSuccess = { s ->
                            soft = bannerPx > s.result.image.height * 1.5f
                            scope.launch { onLight(isLight(s.result.image.toBitmap(), boxW, bannerPx, barPx / bannerPx)) }
                        },
                    )
                    if (soft) {
                        AsyncImage(
                            model = request,
                            contentDescription = null,
                            contentScale = ContentScale.Fit,
                            modifier = Modifier.fillMaxSize().padding(top = top),
                        )
                    }
                }
            }
            Column(Modifier.fillMaxWidth().padding(top = top + BANNER.dp + NAME_GAP)) {
                Row(Modifier.padding(start = 16.dp + ICON + 12.dp, end = 16.dp)) {
                    Column(Modifier.weight(1f)) {
                        ProfileName(user, onSwitchAccount)
                        KarmaLine(user)
                    }
                    if (canFollow) {
                        Spacer(Modifier.width(8.dp))
                        FollowButton(user, onFollowed)
                    }
                }
                Spacer(Modifier.height(8.dp))
                AboutCard(user.description)
                Spacer(Modifier.height(8.dp))
            }
            // The picture over the banner's foot, a third of it on the banner (#277's).
            val ring = 3.dp
            Box(
                Modifier
                    .offset(16.dp - ring, top + BANNER.dp - ICON_OVER - ring)
                    .size(ICON + ring * 2)
                    .background(cs.surface, CircleShape)
                    .padding(ring),
            ) {
                LetterAvatar(user.name, ICON, cs.primaryContainer, cs.onPrimaryContainer, imageUrl = user.iconUrl, modifier = picture)
            }
        }
    } else {
        // No banner: no band of colour standing in for one, the picture big instead.
        Column(
            Modifier.fillMaxWidth().padding(top = bannerBarHeight(top)),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            LetterAvatar(user.name, 112.dp, cs.primaryContainer, cs.onPrimaryContainer, imageUrl = user.iconUrl, modifier = picture)
            Spacer(Modifier.height(10.dp))
            Box(Modifier.padding(horizontal = 16.dp)) { ProfileName(user, onSwitchAccount, size = 28) }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center) {
                KarmaLine(user)
                if (canFollow) {
                    Spacer(Modifier.width(12.dp))
                    FollowButton(user, onFollowed)
                }
            }
            Spacer(Modifier.height(8.dp))
            AboutCard(user.description)
            Spacer(Modifier.height(8.dp))
        }
    }
}

/** u/name (the "r/ and u/ before names" setting's, #289), with a ▾ for the accounts on your own (#144). */
@Composable
private fun ProfileName(user: RedditUser, onSwitchAccount: (() -> Unit)?, size: Int = 26) {
    val style = Modifier
    if (onSwitchAccount == null) {
        Text(userName(user.name), style, fontSize = size.sp, fontWeight = FontWeight.ExtraBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
    } else {
        Row(
            Modifier.clip(RoundedCornerShape(8.dp)).clickable(onClickLabel = "Switch or add account", onClick = onSwitchAccount),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(userName(user.name), Modifier.weight(1f, fill = false), fontSize = size.sp, fontWeight = FontWeight.ExtraBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Icon(Icons.Rounded.KeyboardArrowDown, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/** Karma and how long the account has been around: "6.2M karma · 20y". */
@Composable
private fun KarmaLine(user: RedditUser) {
    Text(
        "${compactNumber(user.linkKarma + user.commentKarma)} karma · ${timeAgo(user.createdUtc)}",
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        style = MaterialTheme.typography.bodyMedium,
    )
}

/**
 * Follow as Join is on a community (#277): + to follow, ✓ to stop. Following a user is
 * subscribing to their profile (u_<name>): their posts then show in your feeds.
 */
@Composable
private fun FollowButton(user: RedditUser, onFollowed: (Boolean) -> Unit) {
    val nav = LocalNavigator.current
    val scope = rememberCoroutineScope()
    var following by remember(user.name) { mutableStateOf(user.following) }
    var busy by remember { mutableStateOf(false) }
    val label = userName(user.name)
    FilledTonalIconToggleButton(
        checked = following,
        onCheckedChange = {
            val next = !following
            following = next
            busy = true
            scope.launch {
                try {
                    app.repository.setSubscribed("u_${user.name}", next)
                    onFollowed(next)
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    following = !next
                    nav.showActionError(if (next) "follow" else "unfollow", e)
                } finally {
                    busy = false
                }
            }
        },
        enabled = !busy,
        modifier = Modifier.size(JOIN).semantics { contentDescription = if (following) "Unfollow $label" else "Follow $label" },
    ) {
        AnimatedContent(
            following,
            transitionSpec = { (scaleIn(initialScale = 0.5f) + fadeIn()) togetherWith (scaleOut(targetScale = 0.5f) + fadeOut()) },
            label = "follow",
        ) { on -> Icon(if (on) Icons.Rounded.Check else Icons.Rounded.Add, null) }
    }
}

/**
 * The bar's row over the profile's header (#293), as a community's: the buttons in lightly
 * tinted circles with the banner blurred inside them; the bar's colour and the name come in
 * as the header slides under it ([fraction] 0 → 1). [bannerShift] is how far the header has
 * slid, so the blurred copy stays lined up with the banner.
 */
@Composable
internal fun UserBannerBar(
    bar: BannerBar,
    user: RedditUser?,
    light: Boolean,
    top: Dp,
    request: ImageRequest?,
    fraction: () -> Float,
    bannerShift: () -> Float,
) {
    val cs = MaterialTheme.colorScheme
    val f = fraction()
    val hasBanner = user?.bannerUrl != null
    val onBanner = if (hasBanner) lerp(if (light) Color.Black.copy(alpha = 0.87f) else Color.White, cs.onSurface, f) else cs.onSurface
    var root by remember { mutableStateOf<LayoutCoordinates?>(null) }
    val holes = remember { mutableStateMapOf<Int, Rect>() }
    Box(Modifier.fillMaxWidth().height(bannerBarHeight(top)).onGloballyPositioned { root = it }) {
        Box(Modifier.matchParentSize().graphicsLayer { alpha = fraction() }.background(cs.surface))
        if (hasBanner && request != null && holes.isNotEmpty()) {
            val shapes = holes.values.toList()
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(top + BANNER.dp)
                    .graphicsLayer { alpha = 1f - fraction() }
                    .drawWithContent {
                        val path = Path().apply { shapes.forEach { addRoundRect(RoundRect(it, CornerRadius(it.height / 2))) } }
                        clipPath(path) { translate(top = bannerShift()) { this@drawWithContent.drawContent() } }
                    },
            ) {
                AsyncImage(model = request, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize().blur(16.dp))
            }
        }
        CompositionLocalProvider(LocalContentColor provides onBanner) {
            Row(
                Modifier.padding(start = 4.dp, top = top + BAR_ROW_TOP, end = 4.dp).height(48.dp).fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                val tint = if (hasBanner) {
                    (if (light) Color.White.copy(alpha = 0.3f) else Color.Black.copy(alpha = 0.25f)).let { it.copy(alpha = it.alpha * (1f - f)) }
                } else {
                    cs.surfaceContainerHigh.copy(alpha = 1f - f)
                }
                fun back(i: Int) = Modifier
                    .onGloballyPositioned { c -> root?.takeIf { it.isAttached }?.let { r -> holes[i] = r.localBoundingBoxOf(c) } }
                    .background(tint, CircleShape)
                bar.leading?.let { Box(back(0)) { it() } }
                // The name in the bar once the header has gone under it.
                Text(
                    user?.let { userName(it.name) } ?: "",
                    Modifier.weight(1f).padding(horizontal = 12.dp).graphicsLayer { alpha = ((fraction() - 0.6f) / 0.4f).coerceIn(0f, 1f) },
                    fontSize = 20.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Row(back(1), content = bar.actions)
            }
        }
    }
}
