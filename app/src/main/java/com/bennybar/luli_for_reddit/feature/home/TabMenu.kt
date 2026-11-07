package com.bennybar.luli_for_reddit.feature.home

import androidx.compose.material3.IconButtonDefaults
import androidx.compose.ui.Modifier
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.dp
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

/**
 * How far the home shell's floating nav has slid away, 0 (shown) to 1 (gone), as it
 * animates; null where there is no floating nav (Settings › Navigation: side bar only,
 * or outside the shell). A lambda, so it's read where it's drawn (graphicsLayer), not
 * in composition.
 */
val LocalNavHidden = staticCompositionLocalOf<(() -> Float)?> { null }

/** The floating nav over the system bar: its 64dp pill and 20dp margin. */
private val FloatingNavHeight = 84.dp

/**
 * A tab's floating button over the floating nav: 12dp above the pill, sliding down
 * into the nav's place as it hides. On top of the button's usual 16dp above the system
 * bar (a Scaffold's, or the caller's own padding), so nothing where there is no nav.
 */
@Composable
fun Modifier.aboveFloatingNav(): Modifier {
    val navHidden = LocalNavHidden.current ?: return this
    val lift = FloatingNavHeight + 12.dp - 16.dp
    return graphicsLayer { translationY = lift.toPx() * navHidden() }.padding(bottom = lift)
}

/**
 * The ☰ at the start of a tab's top bar, when the side bar is on. Every tab
 * places it the same: 4dp from the edge and 8dp from the top of the tab
 * (the Inbox's top app bar puts it there itself), so it doesn't shift as
 * you switch tabs (#34).
 */
@Composable
fun SideBarButton(modifier: Modifier = Modifier) {
    val open = LocalSideBar.current ?: return
    IconButton(onClick = open, shapes = IconButtonDefaults.shapes(), modifier = modifier) { Icon(Icons.Rounded.Menu, "Open menu") }
}

/** The ⚙ at the top of a tab's main screen: straight to Settings. */
@Composable
fun SettingsButton() {
    val nav = LocalNavigator.current
    IconButton(onClick = { nav.push(Route.Settings) }, shapes = IconButtonDefaults.shapes()) { Icon(Icons.Outlined.Settings, "Settings") }
}
