package com.bennybar.luli_for_reddit.state

import org.junit.Assert.assertEquals
import org.junit.Test

class RecentSubredditsTest {
    private fun r(name: String) = RecentSubreddit(name, "r/$name", null, 0, 0)

    @Test
    fun `newest first, once per subreddit whatever the case, at most five`() {
        var list = emptyList<RecentSubreddit>()
        for (n in listOf("a", "b", "c", "d", "e", "f")) list = RecentSubreddits.visited(list, r(n))
        assertEquals(listOf("f", "e", "d", "c", "b"), list.map { it.name })
        list = RecentSubreddits.visited(list, r("C"))
        assertEquals(listOf("C", "f", "e", "d", "b"), list.map { it.name })
    }
}
