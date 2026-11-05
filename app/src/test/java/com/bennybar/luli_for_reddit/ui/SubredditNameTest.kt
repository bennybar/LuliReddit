package com.bennybar.luli_for_reddit.ui

import org.junit.Assert.assertEquals
import org.junit.Test

/** Subreddit names on screen with and without the "r/" (#97). */
class SubredditNameTest {
    @Test
    fun `with the prefix a bare or prefixed name shows as r slash name`() {
        assertEquals("r/pics", subredditName("pics", prefix = true))
        assertEquals("r/pics", subredditName("r/pics", prefix = true))
    }

    @Test
    fun `without the prefix it is just the name`() {
        assertEquals("pics", subredditName("pics", prefix = false))
        assertEquals("pics", subredditName("r/pics", prefix = false))
    }

    @Test
    fun `a user's profile keeps its u slash`() {
        assertEquals("u/someone", subredditName("u/someone", prefix = true))
        assertEquals("u/someone", subredditName("u/someone", prefix = false))
    }
}
