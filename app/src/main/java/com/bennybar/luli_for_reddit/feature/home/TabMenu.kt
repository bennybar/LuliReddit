package com.bennybar.luli_for_reddit.feature.home

import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.material.icons.rounded.Menu
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.runtime.Composable
import com.bennybar.luli_for_reddit.nav.LocalNavigator
import com.bennybar.luli_for_reddit.nav.Route

/** Opens the side bar (Settings › Navigation: side bar / both); null when it's off. */
val LocalSideBar = staticCompositionLocalOf<(() -> Unit)?> { null }

/** The ☰ at the start of a tab's top bar, when the side bar is on. */
@Composable
fun SideBarButton() {
    val open = LocalSideBar.current ?: return
    IconButton(onClick = open) { Icon(Icons.Rounded.Menu, "Open menu") }
}

/** The ⚙ at the top of a tab's main screen: straight to Settings. */
@Composable
fun SettingsButton() {
    val nav = LocalNavigator.current
    IconButton(onClick = { nav.push(Route.Settings) }) { Icon(Icons.Outlined.Settings, "Settings") }
}
