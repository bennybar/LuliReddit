package com.bennybar.luli_for_reddit.ui

import androidx.compose.material3.FilledTonalIconToggleButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.IconToggleButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
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
