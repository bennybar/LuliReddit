package com.bennybar.luli_for_reddit.ui

import org.junit.Assert.assertEquals
import org.junit.Test

/** Subreddit and user names on screen with and without the "r/" and "u/" (#97, #289). */
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
    fun `a user's profile follows the same setting`() {
        assertEquals("u/someone", subredditName("u/someone", prefix = true))
        assertEquals("someone", subredditName("u/someone", prefix = false))
    }

    @Test fun aProfileSubredditReadsAsTheUser() {
        assertEquals("u/jackal-molotov", subredditName("u_jackal-molotov", prefix = true))
        assertEquals("jackal-molotov", subredditName("u_jackal-molotov", prefix = false))
    }

    @Test fun userNamesFollowTheSetting() {
        assertEquals("u/someone", userName("someone", prefix = true))
        assertEquals("u/someone", userName("u/someone", prefix = true))
        assertEquals("someone", userName("someone", prefix = false))
        assertEquals("someone", userName("u/someone", prefix = false))
    }
}
