package com.bennybar.luli_for_reddit.feature.feed

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class FabScrollTest {
    @Test
    fun `folds scrolling down, opens scrolling up, and ignores flings and jitter`() {
        val fab = FabScroll()
        assertTrue(fab.expanded)
        fab.onPreScroll(Offset(0f, -20f), NestedScrollSource.UserInput)
        assertFalse(fab.expanded)
        fab.onPreScroll(Offset(0f, 0.5f), NestedScrollSource.UserInput)
        assertFalse(fab.expanded)
        fab.onPreScroll(Offset(0f, 20f), NestedScrollSource.SideEffect)
        assertFalse(fab.expanded)
        fab.onPreScroll(Offset(0f, 20f), NestedScrollSource.UserInput)
        assertTrue(fab.expanded)
    }
}
