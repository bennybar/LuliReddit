package com.bennybar.luli_for_reddit.model

import com.bennybar.luli_for_reddit.core.AppJson
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Port of test/post_video_detection_test.dart. */
class PostVideoDetectionTest {
    private fun post(json: String) = Post.fromData(AppJson.parseToJsonElement(json))

    @Test
    fun `a crossposted v_redd_it video is a video, not a link`() {
        // Shape of a real crosspost: no media of its own, the video on the parent.
        val p = post(
            """
            {
              "id": "x1",
              "title": "Crossposted clip",
              "subreddit": "funny",
              "url": "https://v.redd.it/abc123",
              "domain": "v.redd.it",
              "is_video": false,
              "media": null,
              "crosspost_parent_list": [
                {
                  "subreddit": "videos",
                  "is_video": true,
                  "media": {
                    "reddit_video": {
                      "hls_url": "https://v.redd.it/abc123/HLSPlaylist.m3u8?a=1",
                      "fallback_url": "https://v.redd.it/abc123/DASH_720.mp4"
                    }
                  }
                }
              ]
            }
            """,
        )
        assertEquals(PostType.VIDEO, p.type)
        assertEquals("https://v.redd.it/abc123/HLSPlaylist.m3u8?a=1", p.hlsUrl)
        assertEquals("https://v.redd.it/abc123/DASH_720.mp4", p.fallbackVideoUrl)
    }

    @Test
    fun `a crossposted gallery is a gallery`() {
        val p = post(
            """
            {
              "id": "x2",
              "title": "Crossposted gallery",
              "url": "https://www.reddit.com/gallery/g1",
              "crosspost_parent_list": [
                {
                  "gallery_data": { "items": [ { "media_id": "m1" } ] },
                  "media_metadata": {
                    "m1": { "s": { "u": "https://preview.redd.it/m1.jpg", "x": 800, "y": 600 } }
                  }
                }
              ]
            }
            """,
        )
        assertEquals(PostType.GALLERY, p.type)
        assertEquals("https://preview.redd.it/m1.jpg", p.gallery.single().url)
    }

    @Test
    fun `a bare v_redd_it link with no metadata gets its HLS stream`() {
        val p = post("""{ "id": "x3", "title": "Bare link", "url": "https://v.redd.it/zzz999", "domain": "v.redd.it" }""")
        assertEquals(PostType.VIDEO, p.type)
        assertEquals("https://v.redd.it/zzz999/HLSPlaylist.m3u8", p.hlsUrl)
    }

    @Test
    fun `an ordinary link is still a link`() {
        val p = post("""{ "id": "x4", "title": "Article", "url": "https://example.com/story", "domain": "example.com" }""")
        assertEquals(PostType.LINK, p.type)
        assertNull(p.hlsUrl)
    }
}
