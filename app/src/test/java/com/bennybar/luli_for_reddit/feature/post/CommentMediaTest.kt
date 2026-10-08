package com.bennybar.luli_for_reddit.feature.post

import com.bennybar.luli_for_reddit.core.AppJson
import com.bennybar.luli_for_reddit.core.isGifUrl
import com.bennybar.luli_for_reddit.core.isImageUrl
import com.bennybar.luli_for_reddit.core.splitMediaRefs
import com.bennybar.luli_for_reddit.model.Comment
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Port of test/comment_media_test.dart. */
class CommentMediaTest {
    @Test
    fun `a GIF-only comment resolves its giphy media (issue 13)`() {
        val c = Comment.fromChild(
            AppJson.parseToJsonElement(
                """
                {"kind": "t1", "data": {
                  "id": "c1", "name": "t1_c1", "author": "mrsir1987",
                  "body": "![gif](giphy|3o7btPCcdNniyf0ArS|downsized)",
                  "score": 6100, "created_utc": 1700000000,
                  "media_metadata": {
                    "giphy|3o7btPCcdNniyf0ArS|downsized": {
                      "status": "valid", "e": "AnimatedImage", "m": "image/gif",
                      "s": {"y": 200,
                            "gif": "https://external-preview.redd.it/abc.gif?width=200&amp;height=200&amp;s=x",
                            "mp4": "https://external-preview.redd.it/abc.gif?format=mp4&amp;s=y",
                            "x": 200},
                      "t": "giphy", "id": "giphy|3o7btPCcdNniyf0ArS|downsized"
                    },
                    "emote|t5_2qh1i|1234": {
                      "status": "valid", "e": "Image",
                      "s": {"u": "https://reddit-econ.example/emote.png"}
                    }
                  }
                }}
                """.trimIndent(),
            ),
            0,
        )

        assertEquals(listOf("giphy|3o7btPCcdNniyf0ArS|downsized"), c.media.keys.toList())
        val (text, media) = splitMediaRefs(c.body, c.media)
        assertTrue(text.isEmpty())
        assertEquals("https://external-preview.redd.it/abc.gif?width=200&height=200&s=x", media.single().toString())
        assertTrue(isImageUrl(media.single()))
        assertTrue(isGifUrl(media.single()))
    }

    @Test
    fun `text around a media ref is kept, unknown refs are left alone`() {
        val (text, media) = splitMediaRefs(
            "lol ![gif](giphy|a) and ![img](missing)",
            mapOf("giphy|a" to "https://i.redd.it/a.gif"),
        )
        assertEquals("lol  and ![img](missing)", text)
        assertEquals("https://i.redd.it/a.gif", media.single().toString())
    }
}
