package com.bennybar.luli_for_reddit.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.material3.ButtonGroupDefaults
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.Text
import androidx.compose.material3.ToggleButton
import androidx.compose.material3.ToggleButtonShapes
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/** Material 3 Expressive's connected button shapes for item [i] of [count] (round ends, tight inner corners). */
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun connectedShapes(i: Int, count: Int): ToggleButtonShapes = when {
    i == 0 -> ButtonGroupDefaults.connectedLeadingButtonShapes()
    i == count - 1 -> ButtonGroupDefaults.connectedTrailingButtonShapes()
    else -> ButtonGroupDefaults.connectedMiddleButtonShapes()
}

/** The gap between connected buttons. */
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
val ConnectedGap: Dp @Composable get() = ButtonGroupDefaults.ConnectedSpaceBetween

/**
 * A pick-one choice as a Material 3 Expressive connected button group (#35).
 * [fill]: the buttons share the width equally; otherwise they size to their
 * labels (put it in a sideways-scrolling row for longer lists).
 */
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun <K> ConnectedChoice(
    options: List<Pair<K, String>>,
    selected: K,
    onSelect: (K) -> Unit,
    modifier: Modifier = Modifier,
    fill: Boolean = true,
) {
    Row(
        if (fill) modifier.fillMaxWidth() else modifier,
        horizontalArrangement = Arrangement.spacedBy(ConnectedGap),
    ) {
        options.forEachIndexed { i, (key, label) ->
            ToggleButton(
                checked = key == selected,
                onCheckedChange = { onSelect(key) },
                modifier = (if (fill) Modifier.weight(1f) else Modifier).semantics { role = Role.RadioButton },
                shapes = connectedShapes(i, options.size),
                contentPadding = PaddingValues(horizontal = if (fill) 8.dp else 16.dp),
            ) { Text(label, maxLines = 1, overflow = TextOverflow.Ellipsis) }
        }
    }
}
