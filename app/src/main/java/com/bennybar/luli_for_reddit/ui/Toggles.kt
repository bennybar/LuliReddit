package com.bennybar.luli_for_reddit.ui

import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.Icons
import androidx.compose.foundation.layout.size
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.material3.FilledTonalIconToggleButton
import androidx.compose.material3.Icon
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.IconToggleButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector

/**
 * An on/off icon (save, favourite…) as a real Material 3 toggle: screen
 * readers hear its state, and its shape changes with it (round → squarer
 * when on). [tonal]: on a filled tonal container, for filters.
 */
@Composable
fun ToggleIcon(
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    on: ImageVector,
    off: ImageVector,
    description: String,
    modifier: Modifier = Modifier,
    tonal: Boolean = false,
) {
    if (tonal) {
        FilledTonalIconToggleButton(checked, onCheckedChange, shapes = IconButtonDefaults.toggleableShapes(), modifier = modifier) {
            Icon(if (checked) on else off, description)
        }
    } else {
        IconToggleButton(checked, onCheckedChange, shapes = IconButtonDefaults.toggleableShapes(), modifier = modifier) {
            Icon(if (checked) on else off, description)
        }
    }
}

/**
 * A quick springy pop each time [on] turns true: vote arrows and save
 * icons (#47), in the spirit of the Expressive toggles' shape change.
 */
@Composable
fun Modifier.popOn(on: Boolean): Modifier {
    val scale = remember { Animatable(1f) }
    // Not on first composition: a post that's already upvoted doesn't pop as it scrolls in.
    val first = remember { booleanArrayOf(true) }
    LaunchedEffect(on) {
        if (on && !first[0]) {
            scale.animateTo(1.35f, tween(90))
            scale.animateTo(1f, spring(Spring.DampingRatioMediumBouncy, Spring.StiffnessMedium))
        }
        first[0] = false
    }
    return graphicsLayer {
        scaleX = scale.value
        scaleY = scale.value
    }
}

/** A switch's thumb: a tick when on, a cross when off (Material 3 Expressive). */
fun switchThumb(checked: Boolean): @Composable () -> Unit = {
    Icon(if (checked) Icons.Rounded.Check else Icons.Rounded.Close, null, Modifier.size(SwitchDefaults.IconSize))
}
