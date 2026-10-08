package com.bennybar.luli_for_reddit.feature.feed

import org.junit.Assert.assertEquals
import org.junit.Test

/** The Calm flair pill shows flair text without Reddit's `:emoji:` shortcodes. */
class CalmFlairTest {
    @Test
    fun `strips emoji shortcodes`() {
        assertEquals("Discussion", cleanFlair(":Discussion: Discussion"))
        assertEquals("Medieval Europe", cleanFlair("Medieval Europe :castle:"))
        assertEquals("Help me", cleanFlair(":q:  Help   :x_y-1: me"))
    }

    @Test
    fun `keeps plain text and empties emoji-only flair`() {
        assertEquals("OC", cleanFlair("OC"))
        assertEquals("10:30 AM", cleanFlair("10:30 AM"))
        assertEquals("", cleanFlair(":star:"))
    }
}
