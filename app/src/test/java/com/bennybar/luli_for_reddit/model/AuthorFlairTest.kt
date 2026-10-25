package com.bennybar.luli_for_reddit.model

import com.bennybar.luli_for_reddit.core.AppJson
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AuthorFlairTest {
    private fun flair(json: String) = authorFlairOf(AppJson.parseToJsonElement(json))

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
}
