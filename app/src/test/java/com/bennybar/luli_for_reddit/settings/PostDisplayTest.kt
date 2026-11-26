package com.bennybar.luli_for_reddit.settings

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** `postDisplay` is stored by index: the Compact layouts (#284) come after the old ones. */
class PostDisplayTest {
    @Test
    fun `stored layouts keep their meaning`() {
        assertEquals(
            listOf(PostDisplay.LARGE, PostDisplay.CARD, PostDisplay.MINI, PostDisplay.CALM, PostDisplay.CALM_CARDS),
            (0..4).map { PostDisplay.entries[it] },
        )
        assertEquals(PostDisplay.COMPACT, PostDisplay.entries[5])
        assertEquals(PostDisplay.COMPACT_CARDS, PostDisplay.entries[6])
    }

    @Test
    fun `compact layouts keep mark read in the sheet and only Compact cards asks for posters`() {
        assertFalse(PostDisplay.COMPACT.readToggleOnCard)
        assertFalse(PostDisplay.COMPACT_CARDS.readToggleOnCard)
        assertTrue(PostDisplay.LARGE.readToggleOnCard)
        assertFalse(PostDisplay.CALM.readToggleOnCard)
        assertTrue(PostDisplay.COMPACT_CARDS.showsPosters)
        assertFalse(PostDisplay.COMPACT.showsPosters)
        assertFalse(PostDisplay.COMPACT.isCalm)
    }
}
