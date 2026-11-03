package com.bennybar.luli_for_reddit.feature.compose

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class LengthLimitTest {
    @Test
    fun countsCodePointsAsRedditDoes() {
        assertEquals(5, redditLength("hello"))
        // One emoji is two UTF-16 units but one character to Reddit.
        assertEquals(1, redditLength("😀"))
        assertEquals(0, redditLength(""))
    }

    @Test
    fun counterShowsOnlyNearTheLimit() {
        assertNull(lengthCounter("a".repeat(269), TITLE_LIMIT))
        assertEquals("270 / 300", lengthCounter("a".repeat(270), TITLE_LIMIT))
        assertEquals("301 / 300", lengthCounter("a".repeat(301), TITLE_LIMIT))
        assertNull(lengthCounter("a".repeat(8999), COMMENT_LIMIT))
        assertEquals("9000 / 10000", lengthCounter("a".repeat(9000), COMMENT_LIMIT))
        assertEquals("40001 / 40000", lengthCounter("a".repeat(40001), POST_BODY_LIMIT))
    }
}
