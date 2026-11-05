package com.bennybar.luli_for_reddit.feature.feed

import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import org.junit.Assert.assertEquals
import org.junit.Test

/** The top bar that hides on scroll, Home's and now a subreddit's and custom feed's (#112). */
class HidingBarTest {
    private fun bar() = HidingBar(LazyListState(), CoroutineScope(Job())).apply { height = 200 }

    @Test
    fun `follows the finger and stays between shown and hidden`() {
        val bar = bar()
        bar.onPostScroll(Offset(0f, -50f), Offset.Zero, NestedScrollSource.UserInput)
        assertEquals(-50f, bar.shift)
        bar.onPostScroll(Offset(0f, -500f), Offset.Zero, NestedScrollSource.UserInput)
        assertEquals(-200f, bar.shift)
        bar.onPostScroll(Offset(0f, 80f), Offset.Zero, NestedScrollSource.UserInput)
        assertEquals(-120f, bar.shift)
        bar.onPostScroll(Offset(0f, 500f), Offset.Zero, NestedScrollSource.UserInput)
        assertEquals(0f, bar.shift)
    }

    @Test
    fun `floating chips sit under the bar and leave with it`() {
        val bar = bar()
        assertEquals(200, bar.chipsY(60)) // bar out: right under it
        bar.shift = -100f
        assertEquals(70, bar.chipsY(60)) // half way: moving faster, so both leave together
        bar.shift = -200f
        assertEquals(-60, bar.chipsY(60)) // bar gone: just off the top
        bar.height = 0
        assertEquals(-60, bar.chipsY(60)) // not measured yet: off the top
    }
}
