package com.bennybar.luli_for_reddit.nav

import androidx.compose.animation.AnimatedVisibilityScope
import androidx.compose.animation.ExperimentalSharedTransitionApi
import androidx.compose.animation.SharedTransitionScope
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.tween
import androidx.compose.runtime.Composable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier

/**
 * Search opens as Gmail's does (#271): the Posts tab's search box (or its 🔍 with the
 * Expandable bar) grows into the Search screen's field while the page fades in, and
 * Back shrinks it again. A shared-bounds transition between the two, keyed by the
 * screen search was opened from, so two screens that both have a search box never
 * morph into each other while one slides over the other.
 */

/** The app's one shared-transition layout, around the NavHost. Null outside it (previews, other hosts). */
@OptIn(ExperimentalSharedTransitionApi::class)
val LocalSharedTransition = staticCompositionLocalOf<SharedTransitionScope?> { null }

/** The destination being drawn: its enter/exit transition and its back stack entry's id. */
class ScreenTransition(val scope: AnimatedVisibilityScope, val entryId: String)

val LocalScreenTransition = staticCompositionLocalOf<ScreenTransition?> { null }

/** On the Search screen: the id of the entry it was opened from. */
val LocalSearchOpenedFrom = staticCompositionLocalOf<String?> { null }

/** On a screen's search box or button: where the Search screen's field grows from. */
@Composable
fun Modifier.searchMorphSource(): Modifier = searchMorph(LocalScreenTransition.current?.entryId)

/** On the Search screen's field. */
@Composable
fun Modifier.searchMorphField(): Modifier = searchMorph(LocalSearchOpenedFrom.current)

/** On the search box's words: they travel to the Search screen's placeholder, not just fade (#285). */
@Composable
fun Modifier.searchMorphSourceText(): Modifier = searchMorphText(LocalScreenTransition.current?.entryId)

/** On the Search screen's placeholder. */
@Composable
fun Modifier.searchMorphFieldText(): Modifier = searchMorphText(LocalSearchOpenedFrom.current)

private val Emphasized = CubicBezierEasing(0.2f, 0f, 0f, 1f)

@OptIn(ExperimentalSharedTransitionApi::class)
@Composable
private fun Modifier.searchMorphText(from: String?): Modifier {
    val shared = LocalSharedTransition.current
    val screen = LocalScreenTransition.current
    if (shared == null || screen == null || from == null) return this
    return with(shared) {
        this@searchMorphText.sharedElement(
            rememberSharedContentState("searchText:$from"),
            screen.scope,
            boundsTransform = { _, _ -> tween(300, easing = Emphasized) },
            // Over the field growing around it.
            zIndexInOverlay = 1f,
        )
    }
}

@OptIn(ExperimentalSharedTransitionApi::class)
@Composable
private fun Modifier.searchMorph(from: String?): Modifier {
    val shared = LocalSharedTransition.current
    val screen = LocalScreenTransition.current
    if (shared == null || screen == null || from == null) return this
    return with(shared) {
        this@searchMorph.sharedBounds(
            rememberSharedContentState("search:$from"),
            screen.scope,
            // The page's own 300ms, so the field lands as the page settles.
            boundsTransform = { _, _ -> tween(300, easing = Emphasized) },
            // Laid out at each size on the way, not scaled: a 🔍 stretched to the
            // field's width would be huge.
            resizeMode = SharedTransitionScope.ResizeMode.RemeasureToBounds,
        )
    }
}
