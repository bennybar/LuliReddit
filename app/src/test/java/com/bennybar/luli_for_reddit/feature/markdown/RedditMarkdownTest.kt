package com.bennybar.luli_for_reddit.feature.markdown

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Port of test/reddit_markdown_test.dart (on the parsed model) plus the toolbar edits. */
class RedditMarkdownTest {
    private fun runs(doc: MdDocument): List<MdInline> =
        doc.blocks.flatMap { b -> (b as? MdBlock.Paragraph)?.inlines ?: emptyList() }

    @Test
    fun `spoiler stays inline, hidden until tapped`() {
        val doc = RedditMarkdownParser.parseUncached("Ending: >!he dies!< sadly.")
        assertEquals(1, doc.blocks.size)
        val p = doc.blocks.single() as MdBlock.Paragraph
        assertEquals("Ending: he dies sadly.", p.inlines.joinToString("") { it.text })
        val spoiler = p.inlines.single { it.text == "he dies" }
        assertEquals(0, spoiler.spoiler) // tappable (revealed by index in the renderer)
        assertEquals(1, doc.spoilerCount)
        assertTrue(p.inlines.filter { it.text != "he dies" }.all { it.spoiler == -1 })
    }

    @Test
    fun `spoiler at line start is not a blockquote`() {
        val doc = RedditMarkdownParser.parseUncached(">!secret!<")
        assertTrue(doc.blocks.none { it is MdBlock.Quote })
        assertTrue(runs(doc).any { it.text == "secret" && it.spoiler == 0 })
    }

    @Test
    fun `a real quote is still a quote`() {
        val doc = RedditMarkdownParser.parseUncached("> quoted\n\nafter")
        assertTrue(doc.blocks.first() is MdBlock.Quote)
        assertTrue(doc.blocks[1] is MdBlock.Paragraph)
    }

    @Test
    fun `superscript, both forms`() {
        val doc = RedditMarkdownParser.parseUncached("x^2 and ^(tiny words) end")
        val sups = runs(doc).filter { it.has(MdStyle.SUP) }
        assertEquals(listOf("2", "tiny words"), sups.map { it.text })
        assertEquals("x2 and tiny words end", runs(doc).joinToString("") { it.text })
    }

    @Test
    fun `inline styles, links and autolinks`() {
        val doc = RedditMarkdownParser.parseUncached("**b** *i* ~~s~~ `c` [t](https://a.com) https://b.com")
        val r = runs(doc)
        assertTrue(r.single { it.text == "b" }.has(MdStyle.BOLD))
        assertTrue(r.single { it.text == "i" }.has(MdStyle.ITALIC))
        assertTrue(r.single { it.text == "s" }.has(MdStyle.STRIKE))
        assertTrue(r.single { it.text == "c" }.has(MdStyle.CODE))
        assertEquals("https://a.com", r.single { it.text == "t" }.link)
        assertEquals("https://b.com", r.single { it.text == "https://b.com" }.link)
    }

    @Test
    fun `lists, code blocks and tables`() {
        val doc = RedditMarkdownParser.parseUncached(
            "1. one\n2. two\n\n```\ncode\n```\n\n| a | b |\n|:-:|--:|\n| 1 | 2 |",
        )
        val list = doc.blocks[0] as MdBlock.ListBlock
        assertTrue(list.ordered)
        assertEquals(2, list.items.size)
        assertEquals("code", (doc.blocks[1] as MdBlock.CodeBlock).code)
        val table = doc.blocks[2] as MdBlock.Table
        assertEquals(listOf("a", "b"), table.header.map { c -> c.joinToString("") { it.text } })
        assertEquals(listOf(0, 1), table.align)
        assertEquals(1, table.rows.size)
    }

    @Test
    fun `soft breaks are spaces, hard breaks newlines`() {
        val doc = RedditMarkdownParser.parseUncached("a\nb  \nc")
        assertEquals("a b\nc", runs(doc).joinToString("") { it.text })
    }

    @Test
    fun `toolbar wraps the selection or a placeholder`() {
        assertEquals(MdEdit("say **hi**", 6, 8), mdWrap("say hi", 4, 6, "**", "**"))
        assertEquals(MdEdit("x**bold**", 3, 7), mdWrap("x", 1, 1, "**", "**", "bold"))
        // No valid selection: acts at the end.
        assertEquals(MdEdit("x`code`", 2, 6), mdWrap("x", -1, -1, "`", "`", "code"))
    }

    @Test
    fun `toolbar prefixes each selected line`() {
        assertEquals(MdEdit("> a\n> b\nc", 7, 7), mdLinePrefix("a\nb\nc", 0, 3, "> "))
        assertEquals(MdEdit("a\n- b", 5, 5), mdLinePrefix("a\nb", 3, 3, "- "))
    }
}
