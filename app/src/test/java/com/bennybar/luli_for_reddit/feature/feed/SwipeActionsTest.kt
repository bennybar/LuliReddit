package com.bennybar.luli_for_reddit.feature.feed

import org.junit.Assert.assertEquals
import org.junit.Test

/** Port of test/swipe_actions_test.dart, against the gesture's state machine. */
class SwipeActionsTest {
    /** Drags [dx] px in small steps (like a finger), releases, and returns what fired. */
    private fun swipe(rtl: Boolean, dx: Float, endSide: Boolean = true): List<String> {
        val fired = mutableListOf<String>()
        val t = SwipeTracker(threshold = 64f, maxDrag = 110f)
        val steps = 12
        repeat(steps) { t.update(dx / steps, rtl, hasStart = true, hasEnd = endSide) }
        when (t.release(rtl)) {
            SwipeTracker.Side.START -> fired.add("start")
            SwipeTracker.Side.END -> if (endSide) fired.add("end")
            null -> {}
        }
        return fired
    }

    @Test
    fun ltrRightIsStartLeftIsEnd() {
        assertEquals(listOf("start"), swipe(rtl = false, dx = 120f))
        assertEquals(listOf("end"), swipe(rtl = false, dx = -120f))
    }

    @Test
    fun rtlMirrorsTheDirections() {
        assertEquals(listOf("start"), swipe(rtl = true, dx = -120f))
        assertEquals(listOf("end"), swipe(rtl = true, dx = 120f))
    }

    @Test
    fun aSideWithNoActionDoesNothing() {
        assertEquals(emptyList<String>(), swipe(rtl = false, dx = -120f, endSide = false))
    }

    @Test
    fun aShortDragDoesNotFire() {
        assertEquals(emptyList<String>(), swipe(rtl = false, dx = 40f))
    }

    @Test
    fun crossingTheThresholdTicksOnce() {
        val t = SwipeTracker(threshold = 64f, maxDrag = 110f)
        val ticks = (1..20).count { t.update(10f, rtl = false, hasStart = true, hasEnd = true) }
        assertEquals(1, ticks)
        assertEquals(110f, t.dx) // clamped to the max drag
    }
}
