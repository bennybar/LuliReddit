package com.bennybar.luli_for_reddit.model

import com.bennybar.luli_for_reddit.core.AppJson
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
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
                    { "subreddit": "audiobooks", "is_self": true, "selftext": "Can you suggest a good app?",
                      "url": "https://www.reddit.com/r/audiobooks/comments/abc/audio_book_app_suggestion/" }
                  ]
                }
                """.trimIndent(),
            ),
        )
        assertEquals(PostType.SELF, p.type)
        assertEquals("Can you suggest a good app?", p.selftext)
        assertEquals("audiobooks", p.crosspostFrom)
        assertFalse("not editable as the user's own text", p.isSelf)
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
