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

    private fun node(extra: String) = AppJson.parseToJsonElement(
        """
        {"__typename":"SubredditPost","id":"t3_abc","postTitle":"A post","authorInfo":{"name":"someone"},
         "subreddit":{"name":"pics","prefixedName":"r/pics","styles":{"icon":"https://styles.redditmedia.com/icon.png?width=256"}},
         "score":10,"commentCount":2,"createdAt":"2026-10-04T00:26:11.575000+0000",
         "permalink":"/r/pics/comments/abc/a_post/",$extra}
        """,
    ).jsonObject

    @Test
    fun `a gallery keeps every image`() {
        val p = Post.fromData(
            gqlPostData(
                node(
                    """"url":"https://www.reddit.com/gallery/abc","gallery":{"items":[
                       {"media":{"url":"https://i.redd.it/1.jpg","width":800,"height":600}},
                       {"media":{"url":"https://i.redd.it/2.jpg","width":600,"height":800}}]}""",
                ),
            ),
        )
        assertEquals(listOf("https://i.redd.it/1.jpg", "https://i.redd.it/2.jpg"), p.gallery.map { it.url })
        assertEquals(800, p.gallery.first().width)
        assertEquals("https://styles.redditmedia.com/icon.png", p.subredditIcon)
    }

    @Test
    fun `a video gets its stream, a GIF its mp4`() {
        val video = Post.fromData(
            gqlPostData(node(""""url":"https://v.redd.it/xyz","media":{"streaming":{"hlsUrl":"https://v.redd.it/xyz/HLSPlaylist.m3u8"}}""")),
        )
        assertEquals("https://v.redd.it/xyz/HLSPlaylist.m3u8", video.hlsUrl)
        val gif = Post.fromData(
            gqlPostData(
                node(
                    """"url":"https://i.redd.it/a.gif","media":{
                       "still":{"source":{"url":"https://p/a.png","dimensions":{"width":400,"height":300}}},
                       "animated":{"mp4_source":{"url":"https://p/a.mp4"}}}""",
                ),
            ),
        )
        assertEquals("https://p/a.mp4", gif.gifMp4Url)
        assertEquals("https://p/a.png", gif.previewUrl)
    }

    @Test
    fun `a crosspost carries the original post`() {
        val p = Post.fromData(
            gqlPostData(
                node(
                    """"url":"/r/other/comments/orig/","crosspostRoot":{"post":{"__typename":"SubredditPost",
                       "id":"t3_orig","subreddit":{"name":"other"},"url":"https://i.redd.it/o.jpg",
                       "media":{"still":{"source":{"url":"https://p/o.jpg","dimensions":{"width":10,"height":10}}}}}}""",
                ),
            ),
        )
        assertEquals("other", p.crosspostFrom)
    }

    @Test
    fun `only posts count`() {
        assertTrue(gqlIsPost(AppJson.parseToJsonElement("""{"__typename":"SubredditPost"}""")))
        assertTrue(!gqlIsPost(AppJson.parseToJsonElement("""{"__typename":"UnavailablePost"}""")))
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
