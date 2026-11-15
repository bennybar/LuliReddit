package com.bennybar.luli_for_reddit.feature.feed

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class FabScrollTest {
    @Test
    fun `folds scrolling down, opens scrolling up, and ignores flings and jitter`() {
        val fab = FabScroll(threshold = 48f)
        assertTrue(fab.expanded)
        fab.onPreScroll(Offset(0f, -60f), NestedScrollSource.UserInput)
        assertFalse(fab.expanded)
        fab.onPreScroll(Offset(0f, 0.5f), NestedScrollSource.UserInput)
        assertFalse(fab.expanded)
        fab.onPreScroll(Offset(0f, 60f), NestedScrollSource.SideEffect)
        assertFalse(fab.expanded)
        fab.onPreScroll(Offset(0f, 60f), NestedScrollSource.UserInput)
        assertTrue(fab.expanded)
    }

    @Test
    fun `a nudge doesn't fold it, a scroll that keeps going does (#177)`() {
        val fab = FabScroll(threshold = 48f)
        fab.onPreScroll(Offset(0f, -20f), NestedScrollSource.UserInput)
        assertTrue(fab.expanded)
        fab.onPreScroll(Offset(0f, -20f), NestedScrollSource.UserInput)
        assertTrue(fab.expanded)
        fab.onPreScroll(Offset(0f, -20f), NestedScrollSource.UserInput)
        assertFalse(fab.expanded)
        // Turning around starts the count again.
        fab.onPreScroll(Offset(0f, 30f), NestedScrollSource.UserInput)
        assertFalse(fab.expanded)
        fab.onPreScroll(Offset(0f, -10f), NestedScrollSource.UserInput)
        fab.onPreScroll(Offset(0f, 30f), NestedScrollSource.UserInput)
        assertFalse(fab.expanded)
        fab.onPreScroll(Offset(0f, 30f), NestedScrollSource.UserInput)
        assertTrue(fab.expanded)
    }
}
