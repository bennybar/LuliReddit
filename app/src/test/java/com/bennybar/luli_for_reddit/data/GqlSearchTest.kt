package com.bennybar.luli_for_reddit.data

import com.bennybar.luli_for_reddit.core.AppJson
import com.bennybar.luli_for_reddit.model.Post
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class GqlSearchTest {
    @Test
    fun `a GraphQL search post becomes a Post card`() {
        val node = AppJson.parseToJsonElement(
            """
            {"__typename":"SubredditPost","id":"t3_abc","postTitle":"iPhone 18 Pro review",
             "authorInfo":{"name":"someone"},"subreddit":{"name":"iphone","prefixedName":"r/iphone"},
             "score":120,"commentCount":45,"createdAt":"2026-10-04T00:26:11.575000+0000",
             "permalink":"/r/iphone/comments/abc/iphone_18_pro_review/","url":"https://i.redd.it/x.jpg",
             "isSelfPost":false,"isNsfw":false,"voteState":"UP","flair":{"text":"Review"},
             "media":{"still":{"small":{"url":"https://p/s.jpg","dimensions":{"width":108,"height":81}},
                               "source":{"url":"https://p/src.jpg","dimensions":{"width":1920,"height":1440}}}}}
            """,
        ).jsonObject
        val p = Post.fromData(gqlPostData(node))
        assertEquals("abc", p.id)
        assertEquals("iPhone 18 Pro review", p.title)
        assertEquals("iphone", p.subreddit)
        assertEquals("someone", p.author)
        assertEquals(120, p.score)
        assertEquals(45, p.numComments)
        assertEquals(1_791_073_571_000L, p.createdUtc) // 2026-10-04T00:26:11Z
        assertTrue(p.permalink.endsWith("/comments/abc/iphone_18_pro_review/"))
    }

    @Test
    fun `search pages end without a cursor`() {
        val data = AppJson.parseToJsonElement(
            """{"search":{"general":{"communities":{"edges":[{"node":{"name":"iphone"}}],
               "pageInfo":{"endCursor":"Mg==","hasNextPage":false}}}}}""",
        ).jsonObject
        val (nodes, next) = gqlSearch(data, "communities")
        assertEquals(1, nodes.size)
        assertNull(next)
    }
}
