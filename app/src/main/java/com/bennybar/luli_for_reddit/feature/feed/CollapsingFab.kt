package com.bennybar.luli_for_reddit.feature.feed

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandHorizontally
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkHorizontally
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

/** Whether a [CollapsingFab] shows its label: it folds as the finger scrolls down and opens on the way up (#62). */
class FabScroll : NestedScrollConnection {
    var expanded by mutableStateOf(true)
        private set

    override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
        if (source == NestedScrollSource.UserInput) {
            if (available.y < -1f) expanded = false else if (available.y > 1f) expanded = true
        }
        return Offset.Zero
    }
}

/**
 * A floating button with a label, or just its icon once scrolled, like Gmail's
 * Compose. Its own unbouncy animation, not ExtendedFloatingActionButton's, which
 * looked odd beside Gmail's: it overshot and clipped the label (#65).
 */
@Composable
fun CollapsingFab(icon: ImageVector, label: String, expanded: Boolean, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val cs = MaterialTheme.colorScheme
    FloatingActionButton(
        onClick = onClick,
        modifier = modifier,
        shape = RoundedCornerShape(20.dp),
        containerColor = cs.primaryContainer,
        contentColor = cs.onPrimaryContainer,
    ) {
        Row(Modifier.padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, if (expanded) null else label)
            AnimatedVisibility(
                expanded,
                enter = expandHorizontally(tween(250, easing = FastOutSlowInEasing), Alignment.Start) +
                    fadeIn(tween(200, delayMillis = 50)),
                exit = shrinkHorizontally(tween(250, easing = FastOutSlowInEasing), Alignment.Start) +
                    fadeOut(tween(120)),
            ) {
                Row {
                    Spacer(Modifier.width(12.dp))
                    Text(label, maxLines = 1, softWrap = false, overflow = TextOverflow.Clip)
                }
            }
        }
    }
}
