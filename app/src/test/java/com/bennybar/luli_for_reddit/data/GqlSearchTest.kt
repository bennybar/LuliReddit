package com.bennybar.luli_for_reddit.data

import com.bennybar.luli_for_reddit.core.AppJson
import com.bennybar.luli_for_reddit.core.get
import com.bennybar.luli_for_reddit.core.str
import com.bennybar.luli_for_reddit.model.Post
import com.bennybar.luli_for_reddit.model.RedditUser
import com.bennybar.luli_for_reddit.model.Subreddit
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
        assertEquals("orig", p.crosspostId)
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

    @Test
    fun `a feed page's post ids skip ads, its cursor is the last post`() {
        val data = AppJson.parseToJsonElement(
            """{"subredditV3":{"elements":{"edges":[
               {"node":{"__typename":"CellGroup","groupId":"t3_a","id":"x"}},
               {"node":{"__typename":"CellGroup","groupId":"t3_ad","adPayload":{"impressionId":"1"}}},
               {"node":{"__typename":"CellGroup","groupId":"t3_a"}},
               {"node":{"__typename":"CellGroup","id":"t3_b"}},
               {"node":{"__typename":"CellGroup","groupId":"carousel_1"}}]}}}""",
        ).jsonObject
        assertEquals(listOf("t3_a", "t3_b"), gqlFeedPostIds(data))
        val (operation, _, vars) = gqlFeedQuery("pics", PostSort.TOP, TopTime.WEEK, "t3_b")!!
        assertEquals("SubredditFeedSdui", operation)
        assertEquals("pics", vars["subredditName"].str())
        assertEquals("TOP", vars["sort"].str())
        assertEquals("WEEK", vars["time"].str())
        assertEquals("dDNfYg==", vars["after"].str()) // base64("t3_b")
    }

    @Test
    fun `each feed picks its query`() {
        assertEquals("HomeFeedSdui", gqlFeedQuery(null, PostSort.BEST, TopTime.DAY, null)!!.first)
        assertEquals("PopularFeedSdui", gqlFeedQuery("popular", PostSort.HOT, TopTime.DAY, null)!!.first)
        assertEquals("AllFeedSdui", gqlFeedQuery("All", PostSort.RISING, TopTime.DAY, null)!!.first)
        val home = gqlFeedQuery(null, PostSort.NEWEST, TopTime.DAY, null)!!.third
        assertEquals("NEW", home["sort"].str())
        assertNull(home["time"])
        assertNull(home["after"])
        assertNull(gqlFeedQuery("pics+news", PostSort.HOT, TopTime.DAY, null))
    }

    @Test
    fun `search results carry their icons (GraphQL)`() {
        val sub = Subreddit.fromData(
            gqlSubredditData(
                AppJson.parseToJsonElement(
                    """{"__typename":"Subreddit","name":"pics","styles":{"icon":"https://styles.redditmedia.com/p.png"}}""",
                ).jsonObject,
            ),
        )
        assertEquals("https://styles.redditmedia.com/p.png", sub.iconUrl)
        val legacy = Subreddit.fromData(
            gqlSubredditData(AppJson.parseToJsonElement("""{"name":"old","styles":{"legacyIcon":{"url":"https://b.thumbs/o.png"}}}""").jsonObject),
        )
        assertEquals("https://b.thumbs/o.png", legacy.iconUrl)
        val user = RedditUser.fromData(
            gqlUserData(
                AppJson.parseToJsonElement(
                    """{"__typename":"Redditor","name":"spez","icon":{"url":"https://styles.redditmedia.com/i.png?width=256&s=x"},
                       "snoovatarIcon":{"url":"https://i.redd.it/snoo.png"},"karma":{"total":5}}""",
                ).jsonObject,
            ),
        )
        assertEquals("https://styles.redditmedia.com/i.png", user.iconUrl)
        val snoo = RedditUser.fromData(
            gqlUserData(AppJson.parseToJsonElement("""{"name":"a","snoovatarIcon":{"url":"https://i.redd.it/snoo.png"}}""").jsonObject),
        )
        assertEquals("https://i.redd.it/snoo.png", snoo.iconUrl)
        // SearchPeople: only the sized icons (#168).
        val sized = RedditUser.fromData(
            gqlUserData(AppJson.parseToJsonElement("""{"name":"c","icon_128":{"url":"https://styles.redditmedia.com/t5_1/styles/profileIcon_x.png?width=128&s=y"}}""").jsonObject),
        )
        assertEquals("https://styles.redditmedia.com/t5_1/styles/profileIcon_x.png", sized.iconUrl)
        assertNull(RedditUser.fromData(gqlUserData(AppJson.parseToJsonElement("""{"name":"b"}""").jsonObject)).iconUrl)
    }

    @Test
    fun `search results carry their icons (REST)`() {
        val sub = Subreddit.fromData(
            AppJson.parseToJsonElement(
                """{"display_name":"pics","community_icon":"https://styles.redditmedia.com/c.png?width=256&amp;s=abc","icon_img":""}""",
            ),
        )
        assertEquals("https://styles.redditmedia.com/c.png?width=256&s=abc", sub.iconUrl)
        val iconOnly = Subreddit.fromData(AppJson.parseToJsonElement("""{"display_name":"x","community_icon":"","icon_img":"https://b.thumbs/x.png"}"""))
        assertEquals("https://b.thumbs/x.png", iconOnly.iconUrl)
        assertNull(Subreddit.fromData(AppJson.parseToJsonElement("""{"display_name":"y","community_icon":"","icon_img":""}""")).iconUrl)
        val user = RedditUser.fromData(
            AppJson.parseToJsonElement("""{"name":"spez","icon_img":"https://styles.redditmedia.com/u.png?width=256&amp;s=1"}"""),
        )
        assertEquals("https://styles.redditmedia.com/u.png", user.iconUrl)
    }
}
