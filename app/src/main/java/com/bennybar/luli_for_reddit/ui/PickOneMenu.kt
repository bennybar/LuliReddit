package com.bennybar.luli_for_reddit.ui

import androidx.compose.foundation.layout.size
import androidx.compose.ui.Modifier
import androidx.compose.material3.Icon
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.material3.DropdownMenuGroup
import androidx.compose.material3.DropdownMenuPopup
import androidx.compose.material3.MenuDefaults
import androidx.compose.material3.SelectableDropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable

/**
 * A Material 3 Expressive dropdown for picking one of [options]: one group,
 * the current one marked selected (also for screen readers). Picking closes it.
 */
@Composable
fun <K> PickOneMenu(
    expanded: Boolean,
    onDismiss: () -> Unit,
    options: List<Pair<K, String>>,
    selected: K?,
    onPick: (K) -> Unit,
    icon: ((K) -> ImageVector)? = null,
) {
    DropdownMenuPopup(expanded = expanded, onDismissRequest = onDismiss) {
        DropdownMenuGroup(shapes = MenuDefaults.groupShape(0, 1)) {
            options.forEachIndexed { i, (key, label) ->
                SelectableDropdownMenuItem(
                    selected = key == selected,
                    onClick = {
                        onDismiss()
                        onPick(key)
                    },
                    text = { Text(label) },
                    shapes = MenuDefaults.itemShape(i, options.size),
                    leadingIcon = icon?.let { f -> { Icon(f(key), null, Modifier.size(MenuDefaults.LeadingIconSize)) } },
                )
            }
        }
    }
}
