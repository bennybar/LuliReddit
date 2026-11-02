package com.bennybar.luli_for_reddit.feature.feed

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
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

/** A floating button with a label, or just its icon once scrolled, like Gmail's Compose. */
@Composable
fun CollapsingFab(icon: ImageVector, label: String, expanded: Boolean, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val cs = MaterialTheme.colorScheme
    ExtendedFloatingActionButton(
        text = { Text(label) },
        icon = { Icon(icon, if (expanded) null else label) },
        onClick = onClick,
        modifier = modifier,
        expanded = expanded,
        shape = RoundedCornerShape(20.dp),
        containerColor = cs.primaryContainer,
        contentColor = cs.onPrimaryContainer,
    )
}
