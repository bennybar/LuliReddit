package com.bennybar.luli_for_reddit.feature.compose

import com.bennybar.luli_for_reddit.core.AppJson
import com.bennybar.luli_for_reddit.data.RedditRepository
import com.bennybar.luli_for_reddit.model.Flair
import com.bennybar.luli_for_reddit.model.FlairPart
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FlairPickerTest {
    private fun template(json: String) = Flair.fromJson(AppJson.parseToJsonElement(json))

    @Test
    fun `link_flair_v2 template keeps colours, editable and emoji`() {
        val f = template(
            """{"id":"abc","text":":star: Discussion","text_editable":true,"background_color":"#FF4500","text_color":"light",
               "type":"richtext","richtext":[{"e":"emoji","a":":star:","u":"https://emoji.redditmedia.com/s.png"},{"e":"text","t":" Discussion"}]}""",
        )
        assertEquals("abc", f.id)
        assertEquals(":star: Discussion", f.text)
        assertTrue(f.editable)
        assertEquals(0xFF4500, f.backgroundColor)
        assertTrue(f.lightText)
        assertEquals(listOf(FlairPart(emojiUrl = "https://emoji.redditmedia.com/s.png"), FlairPart(text = " Discussion")), f.label!!.parts)
    }

    @Test
    fun `plain template without colour`() {
        val f = template("""{"id":"x","text":"Meta","text_editable":false,"background_color":"","text_color":"dark","richtext":[]}""")
        assertFalse(f.editable)
        assertNull(f.backgroundColor)
        assertFalse(f.lightText)
        assertEquals("Meta", f.label!!.text)
    }

    @Test
    fun `transparent background reads as none`() {
        assertNull(template("""{"id":"x","text":"A","background_color":"transparent"}""").backgroundColor)
    }

    private val flairs = listOf(
        Flair("1", "Question"),
        Flair("2", ":star: Discussion", label = com.bennybar.luli_for_reddit.model.UserFlair(listOf(FlairPart(emojiUrl = "u"), FlairPart(text = " Discussion")))),
        Flair("3", "Bug report"),
    )

    @Test
    fun `blank search shows every flair`() {
        assertEquals(flairs, filterFlairs(flairs, "  "))
    }

    @Test
    fun `search matches words in any case, not emoji codes`() {
        assertEquals(listOf("2"), filterFlairs(flairs, "disc").map { it.id })
        assertEquals(listOf("3"), filterFlairs(flairs, " BUG ").map { it.id })
        assertEquals(emptyList<String>(), filterFlairs(flairs, "star").map { it.id })
    }

    @Test
    fun `selectflair form for a post flair`() {
        assertEquals(
            mapOf("api_type" to "json", "link" to "t3_p1", "flair_template_id" to "1"),
            RedditRepository.postFlairForm("t3_p1", Flair("1", "Question")),
        )
    }

    @Test
    fun `selectflair form sends your text only for an editable flair`() {
        assertEquals(
            mapOf("api_type" to "json", "link" to "t3_p1", "flair_template_id" to "2", "text" to "My words"),
            RedditRepository.postFlairForm("t3_p1", Flair("2", "My words", editable = true)),
        )
    }

    @Test
    fun `selectflair form without a template removes the flair`() {
        assertEquals(mapOf("api_type" to "json", "link" to "t3_p1"), RedditRepository.postFlairForm("t3_p1", null))
    }
}
