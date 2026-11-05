package com.bennybar.luli_for_reddit.feature.feed

import com.bennybar.luli_for_reddit.model.GalleryImage
import com.bennybar.luli_for_reddit.model.Post
import com.bennybar.luli_for_reddit.model.PostType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Browse media (#103): which posts it shows, where it starts, when it pages. */
class MediaBrowserTest {
    private fun post(
        id: String,
        type: PostType,
        url: String = "https://i.redd.it/$id.jpg",
        hls: String? = null,
        gallery: List<GalleryImage> = emptyList(),
    ) = Post(
        id = id,
        fullname = "t3_$id",
        title = id,
        subreddit = "pics",
        subredditPrefixed = "r/pics",
        author = "someone",
        score = 1,
        numComments = 0,
        upvoteRatio = 1.0,
        createdUtc = 0,
        permalink = "",
        url = url,
        domain = "",
        type = type,
        hlsUrl = hls,
        gallery = gallery,
    )

    @Test
    fun `images, gifs, galleries and playable videos are media`() {
        assertTrue(isBrowsableMedia(post("a", PostType.IMAGE)))
        assertTrue(isBrowsableMedia(post("b", PostType.GIF)))
        assertTrue(isBrowsableMedia(post("c", PostType.GALLERY, gallery = listOf(GalleryImage("https://i.redd.it/1.jpg")))))
        assertTrue(isBrowsableMedia(post("d", PostType.VIDEO, url = "https://v.redd.it/d", hls = "https://v.redd.it/d/HLSPlaylist.m3u8")))
        assertTrue(isBrowsableMedia(post("e", PostType.VIDEO, url = "https://www.redgifs.com/watch/somegif")))
    }

    @Test
    fun `text, links, empty galleries and external embeds are skipped`() {
        assertFalse(isBrowsableMedia(post("a", PostType.SELF)))
        assertFalse(isBrowsableMedia(post("b", PostType.LINK, url = "https://example.com")))
        assertFalse(isBrowsableMedia(post("c", PostType.GALLERY)))
        assertFalse(isBrowsableMedia(post("d", PostType.VIDEO, url = "https://www.youtube.com/watch?v=x")))
    }

    private val feed = listOf(
        post("t1", PostType.SELF),
        post("i1", PostType.IMAGE),
        post("t2", PostType.SELF),
        post("l1", PostType.LINK, url = "https://example.com"),
        post("i2", PostType.IMAGE),
        post("t3", PostType.SELF),
    )

    @Test
    fun `starts at the first media post at or below the top post`() {
        assertEquals(0, mediaStartIndex(feed, "t1")) // i1
        assertEquals(0, mediaStartIndex(feed, "i1")) // i1 itself
        assertEquals(1, mediaStartIndex(feed, "t2")) // i2
        assertEquals(1, mediaStartIndex(feed, "l1"))
    }

    @Test
    fun `no media below the top post starts on the loading page`() {
        assertEquals(2, mediaStartIndex(feed, "t3")) // == media count
    }

    @Test
    fun `an unknown or missing top post starts at the beginning`() {
        assertEquals(0, mediaStartIndex(feed, null))
        assertEquals(0, mediaStartIndex(feed, "gone"))
        assertEquals(0, mediaStartIndex(emptyList(), "t1"))
    }

    @Test
    fun `loads a few pages before the end, never while loading or at the feed's end`() {
        val p = MediaPaging()
        assertFalse(p.shouldLoad(page = 5, mediaCount = 20, hasMore = true, loadingMore = false))
        assertFalse(p.shouldLoad(page = 17, mediaCount = 20, hasMore = false, loadingMore = false))
        assertFalse(p.shouldLoad(page = 17, mediaCount = 20, hasMore = true, loadingMore = true))
        assertTrue(p.shouldLoad(page = 17, mediaCount = 20, hasMore = true, loadingMore = false))
        // The page brought media: the count of barren pages stays at zero.
        assertTrue(p.shouldLoad(page = 27, mediaCount = 30, hasMore = true, loadingMore = false))
        assertEquals(0, p.barren)
    }

    @Test
    fun `stops after several pages in a row with no media`() {
        val p = MediaPaging()
        var requests = 0
        repeat(20) { if (p.shouldLoad(page = 9, mediaCount = 10, hasMore = true, loadingMore = false)) requests++ }
        // The first request, then MAX_BARREN - 1 more that each brought nothing.
        assertEquals(MediaPaging.MAX_BARREN, requests)
        assertEquals(MediaPaging.MAX_BARREN, p.barren)
    }

    @Test
    fun `a page with media resets the barren count`() {
        val p = MediaPaging()
        p.shouldLoad(page = 9, mediaCount = 10, hasMore = true, loadingMore = false)
        p.shouldLoad(page = 9, mediaCount = 10, hasMore = true, loadingMore = false)
        assertEquals(1, p.barren)
        assertTrue(p.shouldLoad(page = 9, mediaCount = 12, hasMore = true, loadingMore = false))
        assertEquals(0, p.barren)
    }
}
