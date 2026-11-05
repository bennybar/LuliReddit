package com.bennybar.luli_for_reddit.model

import com.bennybar.luli_for_reddit.core.AppJson
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CrosspostAndStubTest {
    @Test
    fun `a crosspost of a text post shows the original's text but stays a link post`() {
        val p = Post.fromData(
            AppJson.parseToJsonElement(
                """
                {
                  "id": "x2", "title": "Audio book app suggestion.", "subreddit": "audiobookshelf",
                  "url": "/r/audiobooks/comments/abc/audio_book_app_suggestion/", "is_self": false, "selftext": "",
                  "crosspost_parent_list": [
                    { "id": "abc", "subreddit": "audiobooks", "is_self": true, "selftext": "Can you suggest a good app?",
                      "url": "https://www.reddit.com/r/audiobooks/comments/abc/audio_book_app_suggestion/" }
                  ]
                }
                """.trimIndent(),
            ),
        )
        assertEquals(PostType.SELF, p.type)
        assertEquals("Can you suggest a good app?", p.selftext)
        assertEquals("audiobooks", p.crosspostFrom)
        assertEquals("abc", p.crosspostId)
        assertFalse("not editable as the user's own text", p.isSelf)
    }

    // A crosspost of a profile post, as a listing sends it when it leaves out
    // `crosspost_parent_list`: only the original's fullname and permalink.
    private val child = """
        { "id": "x9", "name": "t3_x9", "title": "Dumb prize indeed...", "subreddit": "WinStupidPrizes",
          "subreddit_name_prefixed": "r/WinStupidPrizes", "author": "jackal-molotov", "score": 120, "num_comments": 14,
          "permalink": "/r/WinStupidPrizes/comments/x9/dumb_prize_indeed/", "is_self": false, "selftext": "",
          "domain": "reddit.com", "url": "/user/jackal-molotov/comments/1xoodhe/deserved/",
          "crosspost_parent": "t3_1xoodhe" }
    """.trimIndent()
    private val parent = """
        { "id": "1xoodhe", "name": "t3_1xoodhe", "title": "Deserved", "subreddit": "u_jackal-molotov",
          "is_self": false, "is_video": true, "domain": "v.redd.it", "url": "https://v.redd.it/abc123",
          "post_hint": "hosted:video", "thumbnail": "https://b.thumbs.redditmedia.com/t.jpg",
          "media": { "reddit_video": { "hls_url": "https://v.redd.it/abc123/HLSPlaylist.m3u8", "fallback_url": "https://v.redd.it/abc123/CMAF_720.mp4" } },
          "preview": { "images": [ { "source": { "url": "https://preview.redd.it/p.jpg", "width": 720, "height": 1280 }, "resolutions": [] } ] } }
    """.trimIndent()

    @Test
    fun `a crosspost without its parent list is recognised by crosspost_parent`() {
        val p = Post.fromData(AppJson.parseToJsonElement(child))
        assertEquals("t3_1xoodhe", p.crosspostParent)
        assertNull(p.crosspostId)
        assertTrue(p.missingCrosspostParent)
        assertEquals(PostType.LINK, p.type)
    }

    @Test
    fun `merging the fetched parent gives the same post as the parent list`() {
        val c = AppJson.parseToJsonElement(child)
        val par = AppJson.parseToJsonElement(parent)
        val withList = AppJson.parseToJsonElement(child.trimEnd().removeSuffix("}") + ""","crosspost_parent_list": [$parent] }""")
        val merged = Post.fromData(Post.withCrosspostParent(c, par))
        assertEquals(Post.fromData(withList), merged)
        assertFalse(merged.missingCrosspostParent)
        assertEquals(PostType.VIDEO, merged.type)
        assertEquals("https://v.redd.it/abc123/HLSPlaylist.m3u8", merged.hlsUrl)
        assertEquals("https://preview.redd.it/p.jpg", merged.previewUrl)
        assertEquals("u_jackal-molotov", merged.crosspostFrom)
        assertEquals("1xoodhe", merged.crosspostId)
        // The crosspost's own title, place, author and counts stay.
        assertEquals("Dumb prize indeed...", merged.title)
        assertEquals("WinStupidPrizes", merged.subreddit)
        assertEquals("jackal-molotov", merged.author)
        assertEquals(120, merged.score)
        assertEquals(14, merged.numComments)
    }

    // A "repost": a link post whose url is a share link to the profile post.
    private val shareChild = """
        { "id": "y7", "name": "t3_y7", "title": "Dumb prize indeed...", "subreddit": "WinStupidPrizes",
          "author": "jackal-molotov", "score": 88, "num_comments": 9, "is_self": false, "selftext": "",
          "domain": "reddit.com", "url": "https://www.reddit.com/u/jackal-molotov/s/EsXFnpHs3G" }
    """.trimIndent()

    @Test
    fun `a link post to a share link is flagged for its original`() {
        val p = Post.fromData(AppJson.parseToJsonElement(shareChild))
        assertEquals(PostType.LINK, p.type)
        assertTrue(p.shareLink)
        assertTrue("joins the per-page by_id batch once resolved", p.missingCrosspostParent)
        assertNull(p.crosspostParent)
        // Not share links: a permalink, another site, a crosspost.
        assertFalse(Post.fromData(AppJson.parseToJsonElement(child)).shareLink)
        assertFalse(Post.fromData(AppJson.parseToJsonElement(shareChild.replace("www.reddit.com/u/jackal-molotov/s/EsXFnpHs3G", "example.com/a/b/s/c"))).shareLink)
    }

    @Test
    fun `a resolved share link merges into a crosspost of the original`() {
        // What resolveShareLink returns for it; its post id is the one fetched in the page's batch.
        val route = com.bennybar.luli_for_reddit.core.redditPostRoute("https://www.reddit.com/user/jackal-molotov/comments/1xoodhe/deserved/")
        val fullname = "t3_${route!!.postId}"
        assertEquals("t3_1xoodhe", fullname)
        val merged = Post.fromData(Post.withCrosspostParent(AppJson.parseToJsonElement(shareChild), AppJson.parseToJsonElement(parent), fullname))
        assertFalse(merged.shareLink)
        assertFalse(merged.missingCrosspostParent)
        assertEquals(PostType.VIDEO, merged.type)
        assertEquals("https://v.redd.it/abc123/HLSPlaylist.m3u8", merged.hlsUrl)
        assertEquals("u_jackal-molotov", merged.crosspostFrom)
        assertEquals("1xoodhe", merged.crosspostId)
        assertEquals(fullname, merged.crosspostParent)
        assertEquals("Dumb prize indeed...", merged.title)
        assertEquals("WinStupidPrizes", merged.subreddit)
        assertEquals("jackal-molotov", merged.author)
        assertEquals(88, merged.score)
        assertEquals(9, merged.numComments)
    }

    @Test
    fun `continue-this-thread stubs get unique ids`() {
        fun stub(parent: String) = Comment.fromChild(
            AppJson.parseToJsonElement(
                """{"kind": "more", "data": {"id": "_", "name": "t1__", "parent_id": "$parent", "count": 0, "children": []}}""",
            ),
            9,
        )
        val a = stub("t1_aaa")
        val b = stub("t1_bbb")
        assertNotEquals(a.fullname, b.fullname)
        assertEquals("t1_aaa", a.parentId)
        assertEquals(emptyList<String>(), a.moreChildren)
    }
}
