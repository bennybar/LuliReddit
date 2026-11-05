package com.bennybar.luli_for_reddit.state

import org.junit.Assert.assertEquals
import org.junit.Test

class RecentSubredditsTest {
    private fun r(name: String) = RecentSubreddit(name, "r/$name", null, 0, 0)

    @Test
    fun `newest first, once per subreddit whatever the case, at most five listed`() {
        var list = emptyList<RecentSubreddit>()
        for (n in listOf("a", "b", "c", "d", "e", "f")) list = RecentSubreddits.visited(list, r(n))
        assertEquals(listOf("f", "e", "d", "c", "b"), RecentSubreddits.shown(list, byVisits = false).map { it.name })
        list = RecentSubreddits.visited(list, r("C"))
        assertEquals(listOf("C", "f", "e", "d", "b"), RecentSubreddits.shown(list, byVisits = false).map { it.name })
    }

    @Test
    fun `visits are counted whatever the case`() {
        var list = emptyList<RecentSubreddit>()
        for (n in listOf("pics", "news", "Pics", "PICS")) list = RecentSubreddits.visited(list, r(n))
        assertEquals(listOf("PICS" to 3, "news" to 1), list.map { it.name to it.visits })
    }

    @Test
    fun `most visited first, ties newest first, and a frequent one outlives five newer`() {
        var list = emptyList<RecentSubreddit>()
        repeat(4) { list = RecentSubreddits.visited(list, r("often")) }
        for (n in listOf("a", "b", "c", "d", "e", "f")) list = RecentSubreddits.visited(list, r(n))
        list = RecentSubreddits.visited(list, r("b"))
        assertEquals(listOf("often", "b", "f", "e", "d"), RecentSubreddits.shown(list, byVisits = true).map { it.name })
        // Most recent: "often" fell off the five listed but kept its count.
        assertEquals(listOf("b", "f", "e", "d", "c"), RecentSubreddits.shown(list, byVisits = false).map { it.name })
        assertEquals(4, list.first { it.name == "often" }.visits)
    }

    @Test
    fun `remembers a hundred`() {
        var list = emptyList<RecentSubreddit>()
        for (i in 0 until 120) list = RecentSubreddits.visited(list, r("s$i"))
        assertEquals(100, list.size)
        assertEquals("s119", list.first().name)
        assertEquals("s20", list.last().name)
    }
}
