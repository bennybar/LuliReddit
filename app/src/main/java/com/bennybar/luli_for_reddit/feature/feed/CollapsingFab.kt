package com.bennybar.luli_for_reddit.feature.feed

import com.bennybar.luli_for_reddit.ui.SearchIcon
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandHorizontally
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkHorizontally
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.VerticalAlignTop
import com.bennybar.luli_for_reddit.settings.HomeFab
import androidx.compose.material.icons.outlined.VisibilityOff

/**
 * Whether a [CollapsingFab] shows its label: it folds as the finger scrolls down and opens on
 * the way up (#62), once the finger has gone [threshold] px that way, not on the first nudge
 * (#177), as Gmail's.
 */
class FabScroll(private val threshold: Float) : NestedScrollConnection {
    var expanded by mutableStateOf(true)
        private set

    /** How far the finger has scrolled since it last turned around (negative: down). */
    private var travel = 0f

    override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
        if (source == NestedScrollSource.UserInput && available.y != 0f) {
            if ((available.y < 0f) != (travel < 0f)) travel = 0f
            travel += available.y
            if (travel < -threshold) expanded = false else if (travel > threshold) expanded = true
        }
        return Offset.Zero
    }
}

@Composable
fun rememberFabScroll(): FabScroll {
    val threshold = with(LocalDensity.current) { 48.dp.toPx() }
    return remember(threshold) { FabScroll(threshold) }
}

/**
 * A floating button with a label, or just its icon once scrolled, like Gmail's
 * Compose. Its own animation, not ExtendedFloatingActionButton's, which looked odd
 * beside Gmail's: it overshot and clipped the label (#65). Opening springs with a
 * little bounce, as Material 3 Expressive's motion; folding settles without one, so
 * the label never clips (#177). Corners as Material 3 Expressive's FAB, 16dp (#177).
 */
@Composable
fun CollapsingFab(icon: ImageVector, label: String, expanded: Boolean, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val cs = MaterialTheme.colorScheme
    FloatingActionButton(
        onClick = onClick,
        modifier = modifier,
        shape = RoundedCornerShape(16.dp),
        containerColor = cs.primaryContainer,
        contentColor = cs.onPrimaryContainer,
    ) {
        Row(Modifier.padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, if (expanded) null else label)
            AnimatedVisibility(
                expanded,
                enter = expandHorizontally(spring(dampingRatio = 0.7f, stiffness = Spring.StiffnessMediumLow), Alignment.Start) +
                    fadeIn(tween(220, delayMillis = 60)),
                exit = shrinkHorizontally(spring(dampingRatio = Spring.DampingRatioNoBouncy, stiffness = Spring.StiffnessMediumLow), Alignment.Start) +
                    fadeOut(tween(180)),
            ) {
                Row {
                    Spacer(Modifier.width(12.dp))
                    Text(label, maxLines = 1, softWrap = false, overflow = TextOverflow.Clip)
                }
            }
        }
    }
}

/**
 * A feed's floating button, as Settings has it for Home and subreddits (#90, #300); nothing
 * when it's Off. [hideOnScroll]: it hides while scrolling down instead of folding (#301).
 */
@Composable
fun FeedFab(
    kind: HomeFab,
    expanded: Boolean,
    hideOnScroll: Boolean,
    onNewPost: () -> Unit,
    onSearch: () -> Unit,
    onTop: () -> Unit,
    onRefresh: () -> Unit,
    onHideRead: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val (icon, onClick) = when (kind) {
        HomeFab.OFF -> return
        HomeFab.NEW_POST -> Icons.Rounded.Edit to onNewPost
        HomeFab.SEARCH -> SearchIcon to onSearch
        HomeFab.SCROLL_TOP -> Icons.Rounded.VerticalAlignTop to onTop
        HomeFab.REFRESH -> Icons.Rounded.Refresh to onRefresh
        HomeFab.HIDE_READ -> Icons.Outlined.VisibilityOff to onHideRead
    }
    if (hideOnScroll) {
        // Gone while scrolling down, back whole on the way up (#301), as Material's FABs hide.
        AnimatedVisibility(expanded, modifier, enter = scaleIn() + fadeIn(), exit = scaleOut() + fadeOut()) {
            CollapsingFab(icon, kind.label, true, onClick)
        }
    } else {
        CollapsingFab(icon, kind.label, expanded, onClick, modifier)
    }
}
