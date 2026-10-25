package com.bennybar.luli_for_reddit.model

import com.bennybar.luli_for_reddit.core.AppJson
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AuthorFlairTest {
    private fun flair(json: String) = authorFlairOf(AppJson.parseToJsonElement(json))

    @Test
    fun `richtext keeps the text parts, drops emoji`() {
        assertEquals("Galaxy Watch Ultra", flair("""{"author_flair_richtext":[{"e":"emoji","a":":watch:","u":"https://x"},{"e":"text","t":" Galaxy Watch Ultra "}],"author_flair_text":":watch: Galaxy Watch Ultra"}"""))
    }

    @Test
    fun `plain text loses its emoji codes`() {
        assertEquals("Moderator", flair("""{"author_flair_text":":mod: Moderator"}"""))
    }

    @Test
    fun `none or only emoji is no flair`() {
        assertNull(flair("""{"author_flair_text":null}"""))
        assertNull(flair("""{"author_flair_richtext":[{"e":"emoji","a":":x:"}],"author_flair_text":":x:"}"""))
    }
}
