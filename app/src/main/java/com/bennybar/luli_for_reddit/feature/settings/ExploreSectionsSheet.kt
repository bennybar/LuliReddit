package com.bennybar.luli_for_reddit.feature.settings

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.KeyboardArrowUp
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.settings.ExploreSection
import com.bennybar.luli_for_reddit.ui.Overlays
import com.bennybar.luli_for_reddit.ui.switchThumb

/**
 * Settings › Explore sections (#161): which sections Explore shows, and in what
 * order. Each change applies at once. Your communities aren't listed: they stay
 * last, with their filter and sort.
 */
internal fun showExploreSections() {
    Overlays.launch { dismiss ->
        OverlaySheet<Unit>(done = { dismiss() }) { _ ->
            val s by app.settings.state.collectAsStateWithLifecycle()
            val items = s.exploreSections
            SectionHeader("Explore sections", "In this order; your communities stay last")
            items.forEachIndexed { i, entry ->
                key(entry.section) {
                    SettingTile(
                        entry.section.label,
                        subtitle = if (entry.section == ExploreSection.RECENTLY_VISITED && !s.showRecentlyVisited) {
                            "Hidden everywhere while Data & storage › Recently visited is off"
                        } else null,
                        trailing = {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                IconButton(
                                    onClick = { app.settings.setExploreSections(items.toMutableList().apply { add(i - 1, removeAt(i)) }) },
                                    enabled = i > 0,
                                ) { Icon(Icons.Rounded.KeyboardArrowUp, "Move up") }
                                IconButton(
                                    onClick = { app.settings.setExploreSections(items.toMutableList().apply { add(i + 1, removeAt(i)) }) },
                                    enabled = i < items.lastIndex,
                                ) { Icon(Icons.Rounded.KeyboardArrowDown, "Move down") }
                                Switch(
                                    checked = entry.shown,
                                    onCheckedChange = { v -> app.settings.setExploreSections(items.toMutableList().apply { set(i, entry.copy(shown = v)) }) },
                                    thumbContent = switchThumb(entry.shown),
                                )
                            }
                        },
                    )
                }
            }
            TextButton(onClick = { app.settings.setExploreSections(null) }, Modifier.padding(start = 12.dp)) { Text("Reset to default") }
            Spacer(Modifier.height(12.dp))
        }
    }
}
