package com.bennybar.luli_for_reddit.feature.home

import androidx.compose.material3.IconButtonDefaults
import androidx.compose.ui.Modifier
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.dp
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.State
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.unit.LayoutDirection
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
 * True while a touch that went down at the start edge is held (#158): that drag is the
 * side bar's, whose own gesture follows the finger. A tab's pager and swipe rows leave
 * it alone, or they take it first (Inbox snapped the bar open; Profile switched tabs).
 */
val LocalEdgeDrag = staticCompositionLocalOf<State<Boolean>> { mutableStateOf(false) }

/**
 * Watches for touches at the start edge (48dp) and flags them in [LocalEdgeDrag] for
 * [content]; only with the side bar on. Nothing is consumed: the drawer gets the drag.
 */
@Composable
fun SideBarEdge(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    val edgeDrag = remember { mutableStateOf(false) }
    val on = LocalSideBar.current != null
    val rtl = LocalLayoutDirection.current == LayoutDirection.Rtl
    Box(
        if (!on) modifier else modifier.pointerInput(rtl) {
            val edge = 48.dp.toPx()
            awaitEachGesture {
                val down = awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
                if (if (rtl) down.position.x < size.width - edge else down.position.x > edge) return@awaitEachGesture
                edgeDrag.value = true
                try {
                    while (awaitPointerEvent(PointerEventPass.Initial).changes.any { it.pressed }) Unit
                } finally {
                    edgeDrag.value = false
                }
            }
        },
    ) { CompositionLocalProvider(LocalEdgeDrag provides edgeDrag, content = content) }
}

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
