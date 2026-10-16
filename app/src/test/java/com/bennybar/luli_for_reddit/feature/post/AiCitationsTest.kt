package com.bennybar.luli_for_reddit.feature.post

import com.bennybar.luli_for_reddit.core.AppJson
import com.bennybar.luli_for_reddit.model.Comment
import com.bennybar.luli_for_reddit.model.Post
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AiCitationsTest {
    private val post = Post.fromData(AppJson.parseToJsonElement("""{"id":"p","title":"Battery life?","subreddit":"GalaxyWatch","num_comments":40}"""))
    private fun comment(id: String, author: String, score: Int, body: String) =
        Comment(id = id, fullname = "t1_$id", author = author, body = body, score = score, createdUtc = 0, depth = 0)

    private val comments = listOf(
        comment("a", "low", 1, "Meh."),
        comment("b", "top", 90, "Two days with AOD off."),
        comment("c", "mid", 20, "One day with AOD on."),
    )

    @Test
    fun `comments are tagged most upvoted first`() {
        val t = AiService.buildCitedThread(post, comments, maxChars = 10_000)
        assertEquals(listOf("top", "mid", "low"), t.refs.values.map { it.author })
        assertTrue(t.text.contains("[c1] [90] u/top: Two days with AOD off."))
        assertEquals(3, t.included)
    }

    @Test
    fun `only what fits is tagged and counted`() {
        val t = AiService.buildCitedThread(post, comments, maxChars = 230)
        assertTrue(t.included < 3)
        assertEquals(3, t.loaded)
        assertEquals(t.included, t.refs.size)
    }

    @Test
    fun `citations become comment links, unknown tags are dropped`() {
        val t = AiService.buildCitedThread(post, comments, maxChars = 10_000)
        val out = AiService.linkCitations("Most get two days [c1] [c2], one disagrees [c9].", t.refs)
        assertEquals("Most get two days [u/top](ilay-comment:t1_b) [u/mid](ilay-comment:t1_c), one disagrees .", out)
    }
}
