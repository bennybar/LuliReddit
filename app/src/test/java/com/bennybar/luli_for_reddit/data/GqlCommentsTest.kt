package com.bennybar.luli_for_reddit.data

import com.bennybar.luli_for_reddit.core.AppJson
import com.bennybar.luli_for_reddit.core.arr
import com.bennybar.luli_for_reddit.core.get
import com.bennybar.luli_for_reddit.model.Comment
import com.bennybar.luli_for_reddit.model.Post
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class GqlCommentsTest {
    private fun comment(id: String, author: String, markdown: String, extra: String = "") =
        """{"__typename":"Comment","id":"$id","authorInfo":{"name":"$author"},
            "content":{"markdown":"$markdown"},"score":5,"createdAt":"2026-10-04T00:26:11.575000+0000",
            "permalink":"/r/pics/comments/abc/a_post/${id.removePrefix("t1_")}/"$extra}"""

    // PostComments' forest: a flat, depth-first list.
    private val trees = AppJson.parseToJsonElement(
        """[
          {"depth":0,"parentId":"t3_abc","node":${comment("t1_c1", "alice", "Hello", """,
             "isOP":true,"isStickied":true,"distinguishedAs":"MODERATOR","voteState":"UP","isSaved":true,
             "authorFlair":{"text":"Mod","richtext":"[{\"e\":\"text\",\"t\":\"Mod\"}]"}""")}},
          {"depth":1,"parentId":"t1_c1","node":${comment("t1_c2", "bob", "Reply")}},
          {"depth":2,"parentId":"t1_c2","more":{"count":4,"cursor":"cur-deep"}},
          {"depth":0,"parentId":"t3_abc","node":{"__typename":"DeletedComment","createdAt":"2026-10-04T00:26:11+0000"}},
          {"depth":1,"parentId":"t1_gone","node":${comment("t1_c3", "carol", "Under a deleted one", ""","voteState":"DOWN"""")}},
          {"depth":0,"parentId":"t3_abc","more":{"count":30,"cursor":"cur-top"}}
        ]""",
    ).jsonArray

    private val post = buildJsonObject {
        put("id", "abc"); put("name", "t3_abc"); put("title", "A post"); put("author", "alice"); put("subreddit", "pics")
        put("permalink", "/r/pics/comments/abc/a_post/")
    }

    @Test
    fun `a comment forest becomes the thread's comment tree`() {
        val body = gqlThreadData(post, trees)
        assertEquals("abc", Post.fromData(body[0]["data"]["children"][0]["data"]!!).id)
        val top = body[1]["data"]["children"].arr()!!.map { Comment.fromChild(it, 0) }
        assertEquals(listOf("c1", "gone", "more_t3_abc"), top.map { it.id })

        val c1 = top[0]
        assertEquals("alice", c1.author)
        assertEquals("Hello", c1.body)
        assertEquals(5, c1.score)
        assertEquals(1_791_073_571_000L, c1.createdUtc)
        assertEquals("moderator", c1.distinguished)
        assertTrue(c1.stickied && c1.saved)
        assertEquals(true, c1.likes)
        assertEquals("Mod", c1.authorFlair?.parts?.single()?.text)
        assertEquals("t3_abc", c1.parentId)

        val c2 = c1.replies.single()
        assertEquals(1, c2.depth)
        assertEquals("t1_c1", c2.parentId)
        val deep = c2.replies.single()
        assertTrue(deep.isMore)
        assertEquals(2, deep.depth)
        assertEquals(4, deep.moreCount)
        assertEquals("t1_c2", deep.parentId)
        assertEquals(listOf("${GQL_MORE}t1_c2 cur-deep"), deep.moreChildren)

        // The deleted comment gets its id back from its reply.
        val gone = top[1]
        assertEquals("[deleted]", gone.author)
        assertEquals("[deleted]", gone.body)
        assertEquals("t1_gone", gone.fullname)
        assertEquals(false, gone.replies.single().likes)

        val more = top[2]
        assertTrue(more.isMore)
        assertEquals(30, more.moreCount)
        assertEquals("t3_abc", more.parentId)
        assertEquals(listOf("${GQL_MORE}t3_abc cur-top"), more.moreChildren)
    }

    @Test
    fun `a loaded more comes flat, rooted where the more row was`() {
        // The page after cursor cur-deep: depths continue from where it sat.
        val page = AppJson.parseToJsonElement(
            """[
              {"depth":2,"node":${comment("t1_d1", "dan", "One")}},
              {"depth":3,"parentId":"t1_d1","node":${comment("t1_d2", "erin", "Two")}},
              {"depth":2,"parentId":"t1_c2","more":{"count":2,"cursor":"cur-next"}}
            ]""",
        ).jsonArray
        // Rooted at the row's parent even where Reddit leaves parentId out.
        val flat = gqlCommentThings(page, "t3_abc", moreParent = "t1_c2").map { Comment.fromChild(it, 2) }
        assertEquals(listOf("t1_c2", "t1_d1", "t1_c2"), flat.map { it.parentId })
        assertEquals(listOf("${GQL_MORE}t1_c2 cur-next"), flat.last().moreChildren)
    }

    @Test
    fun `focused threads and more use PostComments' variables`() {
        val vars = postCommentsVariables("t3_abc", "qa", "c9", null)
        assertEquals(JsonPrimitive("QA"), vars["sortType"])
        assertEquals(JsonPrimitive("t1_c9"), vars["focusedCommentContext"]["commentId"])
        assertNull(vars["after"])
        assertEquals(JsonPrimitive("cur"), postCommentsVariables("t3_abc", "confidence", null, "cur")["after"])
    }

    private fun richtext(document: String, media: String = "[]") = buildJsonObject {
        put("richtext", """{"document":$document}""")
        put("richtextMedia", AppJson.parseToJsonElement(media))
    }

    @Test
    fun `the source markdown wins over richtext`() {
        val content = AppJson.parseToJsonElement("""{"markdown":"**hi**","richtext":"{\"document\":[]}"}""").jsonObject
        assertEquals("**hi**", gqlMarkdown(content, "c1"))
    }

    @Test
    fun `richtext becomes markdown`() {
        val md = gqlMarkdown(
            richtext(
                """[
                  {"e":"h","l":2,"c":[{"e":"text","t":"Title"}]},
                  {"e":"par","c":[{"e":"text","t":"bold italic struck 2*3","f":[[1,0,4],[2,5,6],[8,12,6]]},
                    {"e":"link","u":"https://example.com/a (b)","t":"a link"},{"e":"text","t":" "},
                    {"e":"spoilertext","c":[{"e":"text","t":"secret"}]},{"e":"text","t":" in "},
                    {"e":"r/","t":"pics","l":false},{"e":"br"},{"e":"text","t":"x","f":[[64,0,1]]},
                    {"e":"text","t":"e=mc2","f":[[32,4,1]]}]},
                  {"e":"blockquote","c":[{"e":"par","c":[{"e":"text","t":"quoted"}]},{"e":"par","c":[{"e":"text","t":"more"}]}]},
                  {"e":"list","o":true,"c":[{"e":"li","c":[{"e":"par","c":[{"e":"text","t":"one"}]}]},
                    {"e":"li","c":[{"e":"par","c":[{"e":"text","t":"two"}]},{"e":"list","o":false,"c":[{"e":"li","c":[{"e":"par","c":[{"e":"text","t":"sub"}]}]}]}]}]},
                  {"e":"code","c":[{"e":"raw","t":"val x = 1"},{"e":"raw","t":"  *y*"}]},
                  {"e":"hr"},
                  {"e":"par","c":[{"e":"gif","id":"giphy|abc123|downsized"}]},
                  {"e":"img","id":"img1"},
                  {"e":"table","h":[{"a":"L","c":[{"e":"text","t":"A"}]},{"c":[{"e":"text","t":"B"}]}],
                    "c":[[{"c":[{"e":"text","t":"1"}]},{"c":[{"e":"text","t":"2"}]}]]}
                ]""",
                """[{"id":"img1","url":"https://i.redd.it/full.png","large":{"url":"https://preview.redd.it/large.png"}}]""",
            ),
            "c1",
        )
        assertEquals(
            listOf(
                "## Title",
                "**bold** *italic* ~~struck~~ 2\\*3[a link](https://example.com/a%20%28b%29) >!secret!< in r/pics  \n`x`e=mc^(2)",
                "> quoted\n>\n> more",
                "1. one\n2. two\n   \n   - sub",
                "```\nval x = 1\n  *y*\n```",
                "---",
                "https://media.giphy.com/media/abc123/giphy.webp",
                "https://preview.redd.it/large.png",
                "| A | B |\n| :-- | --- |\n| 1 | 2 |",
            ).joinToString("\n\n"),
            md,
        )
    }

    @Test
    fun `formatting skips whitespace and counts code points`() {
        // "😀 wow": the emoji is one code point, so " wow ok" is 1 to 8.
        val md = gqlMarkdown(richtext("""[{"e":"par","c":[{"e":"text","t":"😀 wow ok","f":[[1,1,7]]}]}]"""), "c1")
        assertEquals("😀 **wow ok**", md.trimEnd())
    }
}
