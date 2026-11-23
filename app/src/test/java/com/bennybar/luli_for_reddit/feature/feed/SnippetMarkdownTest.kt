package com.bennybar.luli_for_reddit.feature.feed

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SnippetMarkdownTest {
    private val cover = Color.Gray
    private fun md(s: String) = snippetMarkdown(s, cover)

    /** The text under each style: what's bold, italic… */
    private fun styled(s: String, pick: (androidx.compose.ui.text.SpanStyle) -> Boolean): List<String> {
        val a = md(s)
        return a.spanStyles.filter { pick(it.item) }.map { a.text.substring(it.start, it.end) }
    }

    @Test fun boldItalicStrikeDrawnWithoutTheirMarks() {
        val s = "A **big** day, *really* and ~~not~~ __this__"
        assertEquals("A big day, really and not this", md(s).text)
        assertEquals(listOf("big", "this"), styled(s) { it.fontWeight == FontWeight.Bold })
        assertEquals(listOf("really"), styled(s) { it.fontStyle == FontStyle.Italic })
        assertEquals(listOf("not"), styled(s) { it.textDecoration == TextDecoration.LineThrough })
    }

    @Test fun spoilersAreCovered_escapedOrNot() {
        for (s in listOf("It was >!the butler!< all along", "It was &gt;!the butler!&lt; all along")) {
            assertEquals("It was the butler all along", md(s).text)
            assertEquals(listOf("the butler"), styled(s) { it.background == cover && it.color == cover })
        }
    }

    @Test fun linksShowTheirWords_headingsAndQuotesLoseTheirMarks() {
        assertEquals("See this page", md("See [this page](https://example.com)").text)
        assertEquals("Title\nquoted text", md("## Title\n> quoted text").text)
        assertEquals(listOf("Title"), styled("## Title\nbody") { it.fontWeight == FontWeight.Bold })
    }

    @Test fun plainTextAndLoneMarksStayAsTyped() {
        assertEquals("snake_case_name and 2 * 3 * 4", md("snake_case_name and 2 * 3 * 4").text)
        assertEquals("a ** b", md("a ** b").text)
        assertEquals("5 > 3 & 1 < 2", md("5 &gt; 3 &amp; 1 &lt; 2").text)
        assertTrue(md("nothing here").spanStyles.isEmpty())
    }

    @Test fun backslashEscapes() {
        assertEquals("*not italic*", md("\\*not italic\\*").text)
    }
}
