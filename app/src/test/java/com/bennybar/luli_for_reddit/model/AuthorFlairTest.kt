package com.bennybar.luli_for_reddit.model

import com.bennybar.luli_for_reddit.core.AppJson
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AuthorFlairTest {
    private fun flair(json: String) = flairOf(AppJson.parseToJsonElement(json), "author")

    @Test
    fun `richtext keeps text and emoji in order`() {
        val f = flair("""{"author_flair_richtext":[{"e":"emoji","a":":watch:","u":"https://emoji.redditmedia.com/w.png"},{"e":"text","t":" Galaxy Watch Ultra "}],"author_flair_text":":watch: Galaxy Watch Ultra"}""")!!
        assertEquals(listOf(FlairPart(emojiUrl = "https://emoji.redditmedia.com/w.png"), FlairPart(text = " Galaxy Watch Ultra")), f.parts)
        assertEquals("Galaxy Watch Ultra", f.text)
    }

    @Test
    fun `emoji-only flair is kept (it has images)`() {
        val f = flair("""{"author_flair_richtext":[{"e":"emoji","a":":x:","u":"https://e/x.png"}],"author_flair_text":":x:"}""")!!
        assertEquals(listOf(FlairPart(emojiUrl = "https://e/x.png")), f.parts)
    }

    @Test
    fun `plain text loses its emoji codes`() {
        assertEquals("Moderator", flair("""{"author_flair_text":":mod: Moderator"}""")!!.text)
    }

    @Test
    fun `no flair is null`() {
        assertNull(flair("""{"author_flair_text":null}"""))
        assertNull(flair("""{"author_flair_text":":x:"}"""))
    }

    private fun linkFlair(json: String) = flairOf(AppJson.parseToJsonElement(json), "link")

    @Test
    fun `a post's flair keeps its images (#56)`() {
        val f = linkFlair("""{"link_flair_richtext":[{"e":"emoji","a":":a16:","u":"https://emoji.redditmedia.com/a.png"},{"e":"text","t":" Android 16"}],"link_flair_text":":a16: Android 16"}""")!!
        assertEquals(listOf(FlairPart(emojiUrl = "https://emoji.redditmedia.com/a.png"), FlairPart(text = " Android 16")), f.parts)
    }

    @Test
    fun `plain flair text loses its emoji codes`() {
        assertEquals("Discussion", linkFlair("""{"link_flair_text":":Discussion: Discussion"}""")!!.text)
        assertEquals("Help me", linkFlair("""{"link_flair_text":":q:  Help   :x_y-1: me"}""")!!.text)
        assertEquals("10:30 AM", linkFlair("""{"link_flair_text":"10:30 AM"}""")!!.text)
        assertNull(linkFlair("""{"link_flair_text":":star:"}"""))
    }
}
