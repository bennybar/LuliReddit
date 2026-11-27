package com.bennybar.luli_for_reddit.feature.feed

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material3.FilledTonalIconToggleButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
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

/** How much the profile's header opens under the bar: a community's with a banner, more for the big picture without. */
internal fun userHeaderExtra(user: RedditUser?): Dp = if (user?.bannerUrl != null) BANNER_EXTRA else CENTERED_EXTRA

/**
 * A profile's header as a community's, the same one (#293, #298): with a banner, it under
 * the status bar, the picture over its foot and the name beside it; without one, no coloured
 * band but the picture big and centred, the name under it. Either way they slide into the
 * bar as it folds. Karma and the account's age under the name, Follow as a round + / ✓.
 * [user] null while it loads: the name, a letter for the picture.
 */
@Composable
internal fun UserHeaderBar(
    state: CollapsingTitle,
    username: String,
    user: RedditUser?,
    canFollow: Boolean,
    onSwitchAccount: (() -> Unit)?,
    bar: BannerBar,
    onFollowed: (Boolean) -> Unit,
) {
    val cs = MaterialTheme.colorScheme
    val icon = user?.iconUrl
    BannerHeaderBar(
        state,
        bannerUrl = user?.bannerUrl,
        band = if (user?.bannerUrl != null) cs.primaryContainer else null,
        name = userName(user?.name ?: username),
        picture = { size ->
            LetterAvatar(
                user?.name ?: username, size, cs.primaryContainer, cs.onPrimaryContainer, imageUrl = icon,
                modifier = if (icon != null) Modifier.opensPicture(icon, "u/${user?.name ?: username}") else Modifier,
            )
        },
        subtitle = user?.let { "${compactNumber(it.linkKarma + it.commentKarma)} karma · ${timeAgo(it.createdUtc)}" },
        leading = bar.leading,
        trailing = if (user == null || !canFollow) null else { enabled -> FollowButton(user, enabled, onFollowed) },
        onName = onSwitchAccount,
        actions = bar.actions,
    )
}

/**
 * Follow as Join is on a community (#277): + to follow, ✓ to stop. Following a user is
 * subscribing to their profile (u_<name>): their posts then show in your feeds.
 */
@Composable
private fun FollowButton(user: RedditUser, enabled: Boolean, onFollowed: (Boolean) -> Unit) {
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
        enabled = enabled && !busy,
        modifier = Modifier.size(JOIN).semantics { contentDescription = if (following) "Unfollow $label" else "Follow $label" },
    ) {
        AnimatedContent(
            following,
            transitionSpec = { (scaleIn(initialScale = 0.5f) + fadeIn()) togetherWith (scaleOut(targetScale = 0.5f) + fadeOut()) },
            label = "follow",
        ) { on -> Icon(if (on) Icons.Rounded.Check else Icons.Rounded.Add, null) }
    }
}
