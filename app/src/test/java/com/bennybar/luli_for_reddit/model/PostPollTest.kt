package com.bennybar.luli_for_reddit.model

import com.bennybar.luli_for_reddit.core.AppJson
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class PostPollTest {
    private fun post(poll: String) = Post.fromData(
        AppJson.parseToJsonElement("""{"id":"p1","title":"Poll","subreddit":"polls","permalink":"/r/polls/comments/p1/poll/","poll_data":$poll}"""),
    )

    @Test
    fun `before voting - options only, no results`() {
        val p = post("""{"options":[{"id":"11","text":"Yes"},{"id":"12","text":"No"}],"user_selection":null}""")
        assertEquals(listOf("Yes", "No"), p.pollOptions)
        assertEquals(emptyList<Int>(), p.pollVotes)
        assertNull(p.pollChoice)
    }

    @Test
    fun `after voting - counts and your choice line up with the options`() {
        val p = post("""{"options":[{"id":"11","text":"Yes","vote_count":30},{"id":"x","text":""},{"id":"12","text":"No","vote_count":10}],"user_selection":"12"}""")
        assertEquals(listOf("Yes", "No"), p.pollOptions)
        assertEquals(listOf(30, 10), p.pollVotes)
        assertEquals(1, p.pollChoice)
    }
}
