package com.bennybar.luli_for_reddit.feature.feed

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/*
 * The menus that slide up from the bottom (#181), as Material 3 Expressive's: rows in
 * rounded groups, 2dp apart and inset from the sheet's edges (as Settings' and History's),
 * an icon on each, and the picked one a fully round pill in the side bar's selected colour.
 * One look for every menu: Top's time range, Profile's sort, accounts, a post's ⋯, and
 * Settings' pickers.
 */

/** One row of a [MenuGroup]. [selected] rows are choices (radio buttons, to screen readers). */
class MenuEntry(
    val title: String,
    val icon: ImageVector? = null,
    val subtitle: String? = null,
    val selected: Boolean? = null,
    val danger: Boolean = false,
    val leading: (@Composable () -> Unit)? = null,
    val trailing: (@Composable () -> Unit)? = null,
    val onClick: (() -> Unit)? = null,
)

class MenuGroupScope internal constructor() {
    internal val entries = mutableListOf<MenuEntry>()

    fun item(
        title: String,
        icon: ImageVector? = null,
        subtitle: String? = null,
        selected: Boolean? = null,
        danger: Boolean = false,
        leading: (@Composable () -> Unit)? = null,
        trailing: (@Composable () -> Unit)? = null,
        onClick: (() -> Unit)? = null,
    ) {
        entries += MenuEntry(title, icon, subtitle, selected, danger, leading, trailing, onClick)
    }
}

/** A menu section's name, over its group. */
@Composable
fun MenuLabel(text: String) {
    Text(
        text,
        Modifier.padding(start = 22.dp, top = 4.dp, end = 22.dp, bottom = 8.dp),
        fontSize = 13.sp,
        fontWeight = FontWeight.SemiBold,
        color = MaterialTheme.colorScheme.primary,
    )
}

/** A group of menu rows; its outer corners are round only where it starts and ends. */
@Composable
fun MenuGroup(build: MenuGroupScope.() -> Unit) {
    val entries = MenuGroupScope().apply(build).entries
    if (entries.isEmpty()) return
    Column(Modifier.fillMaxWidth().padding(start = 14.dp, end = 14.dp, bottom = 14.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        entries.forEachIndexed { i, e -> MenuRow(e, first = i == 0, last = i == entries.lastIndex) }
    }
}

@Composable
private fun MenuRow(e: MenuEntry, first: Boolean, last: Boolean) {
    val cs = MaterialTheme.colorScheme
    val on = e.selected == true
    // The pick morphs into a pill: its corners round out and its colour fills in.
    val top by animateDpAsState(if (on) 28.dp else if (first) 20.dp else 4.dp, label = "menuTop")
    val bottom by animateDpAsState(if (on) 28.dp else if (last) 20.dp else 4.dp, label = "menuBottom")
    val bg by animateColorAsState(if (on) cs.secondaryContainer else cs.surfaceContainerHigh, label = "menuBg")
    val fg = when {
        on -> cs.onSecondaryContainer
        e.danger -> cs.error
        else -> cs.onSurface
    }
    val tint = if (on || e.danger) fg else cs.onSurfaceVariant
    val click = e.onClick
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 52.dp)
            .clip(RoundedCornerShape(top, top, bottom, bottom))
            .background(bg)
            .then(
                when {
                    click == null -> Modifier
                    e.selected != null -> Modifier.selectable(selected = on, role = Role.RadioButton, onClick = click)
                    else -> Modifier.clickable(onClick = click)
                },
            )
            .padding(start = 16.dp, top = 10.dp, end = 12.dp, bottom = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        if (e.leading != null) e.leading.invoke() else if (e.icon != null) Icon(e.icon, null, tint = tint)
        Column(Modifier.weight(1f)) {
            Text(e.title, color = fg, style = MaterialTheme.typography.bodyLarge)
            if (e.subtitle != null) {
                Text(e.subtitle, color = if (on) fg else cs.onSurfaceVariant, style = MaterialTheme.typography.bodySmall)
            }
        }
        if (e.trailing != null) e.trailing.invoke() else if (on) Icon(Icons.Rounded.Check, "Selected", tint = fg)
    }
}
