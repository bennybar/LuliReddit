package com.bennybar.luli_for_reddit.core

import android.net.Uri
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class MediaLinksTest {
    private fun texts(s: List<BodySegment>) = s.map { if (it is BodySegment.Text) "T:${it.markdown}" else "M:${(it as BodySegment.Media).uri}" }

    @Test
    fun `a paragraph that is only a media link becomes media in place`() {
        val body = "Look at this\n\nhttps://preview.redd.it/abc.png?width=640&s=x\n\nThat's it"
        assertEquals(
            listOf("T:Look at this", "M:https://preview.redd.it/abc.png?width=640&s=x", "T:That's it"),
            texts(bodySegments(body, emptyMap(), 10)),
        )
    }

    @Test
    fun `markdown link to an image counts as a lone media paragraph`() {
        val body = "[image](https://i.redd.it/xyz.jpg)"
        assertEquals(listOf("M:https://i.redd.it/xyz.jpg"), texts(bodySegments(body, emptyMap(), 10)))
    }

    @Test
    fun `uploaded media refs resolve from media_metadata`() {
        val body = "before ![img](abc123) after"
        val segs = texts(bodySegments(body, mapOf("abc123" to "https://i.redd.it/abc123.png"), 10))
        assertEquals(listOf("T:before", "M:https://i.redd.it/abc123.png", "T:after"), segs)
    }

    @Test
    fun `media inside a sentence follows its paragraph and plain links stay text`() {
        val body = "see https://i.redd.it/a.jpg here and https://example.com"
        assertEquals(
            listOf("T:see https://i.redd.it/a.jpg here and https://example.com", "M:https://i.redd.it/a.jpg"),
            texts(bodySegments(body, emptyMap(), 10)),
        )
    }

    @Test
    fun `media count is capped`() {
        val body = (1..5).joinToString("\n\n") { "https://i.redd.it/$it.jpg" }
        assertEquals(2, bodySegments(body, emptyMap(), 2).count { it is BodySegment.Media })
    }

    @Test
    fun `an embedded reddit video link is its v-redd-it video`() {
        val u = Uri.parse("https://reddit.com/link/pdnkxg6/video/pom8yboslath1/player")
        assertEquals("https://v.redd.it/pom8yboslath1", inlineRedditVideo(u).toString())
        assertNull(inlineRedditVideo(Uri.parse("https://www.reddit.com/r/videos/comments/abc/x/")))
        assertEquals(
            "https://v.redd.it/pom8yboslath1/HLSPlaylist.m3u8",
            resolveVideoUrl("https://reddit.com/link/pdnkxg6/video/pom8yboslath1/player"),
        )
        assertEquals("https://v.redd.it/abc/HLSPlaylist.m3u8", resolveVideoUrl("https://v.redd.it/abc"))
        assertEquals("https://i.imgur.com/a.mp4", resolveVideoUrl("https://i.imgur.com/a.gifv"))
    }
}
