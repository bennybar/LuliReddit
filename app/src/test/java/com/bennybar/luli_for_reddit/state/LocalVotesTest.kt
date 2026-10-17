package com.bennybar.luli_for_reddit.state

import org.junit.Assert.assertEquals
import org.junit.Test

class LocalVotesTest {
    @Test
    fun `Reddit still has the old vote - show yours on its score`() {
        val v = LocalVotes()
        v.record("a", 1, serverScore = 10, serverLikes = null)
        assertEquals(true to 11, v.reconcile("a", null, 10))
        // Someone else voted meanwhile: their vote counts, yours is added on top.
        assertEquals(true to 13, v.reconcile("a", null, 12))
    }

    @Test
    fun `vote is in but score has not moved - add it`() {
        val v = LocalVotes()
        v.record("a", 1, serverScore = 10, serverLikes = null)
        assertEquals(true to 11, v.reconcile("a", true, 10))
    }

    @Test
    fun `Reddit caught up - trust it from then on`() {
        val v = LocalVotes()
        v.record("a", -1, serverScore = 10, serverLikes = null)
        assertEquals(false to 9, v.reconcile("a", false, 9))
        assertEquals(false to 7, v.reconcile("a", false, 7))
    }

    @Test
    fun `changing a vote twice keeps the first baseline`() {
        val v = LocalVotes()
        v.reconcile("a", true, 20) // seen: upvoted at 20
        v.record("a", 0, serverScore = 20, serverLikes = true)
        v.record("a", -1, serverScore = 19, serverLikes = null)
        assertEquals(false to 18, v.reconcile("a", true, 20))
        assertEquals(false to 18, v.reconcile("a", false, 20))
    }

    @Test
    fun `no local vote - server wins`() {
        assertEquals(null to 5, LocalVotes().reconcile("a", null, 5))
    }
}
