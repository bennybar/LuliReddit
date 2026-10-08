package com.bennybar.luli_for_reddit.feature.markdown

import androidx.compose.runtime.Immutable
import org.commonmark.ext.autolink.AutolinkExtension
import org.commonmark.ext.gfm.strikethrough.Strikethrough
import org.commonmark.ext.gfm.strikethrough.StrikethroughExtension
import org.commonmark.ext.gfm.tables.TableBlock
import org.commonmark.ext.gfm.tables.TableBody
import org.commonmark.ext.gfm.tables.TableCell
import org.commonmark.ext.gfm.tables.TableHead
import org.commonmark.ext.gfm.tables.TableRow
import org.commonmark.ext.gfm.tables.TablesExtension
import org.commonmark.node.BlockQuote
import org.commonmark.node.BulletList
import org.commonmark.node.Code
import org.commonmark.node.Emphasis
import org.commonmark.node.FencedCodeBlock
import org.commonmark.node.HardLineBreak
import org.commonmark.node.Heading
import org.commonmark.node.HtmlBlock
import org.commonmark.node.HtmlInline
import org.commonmark.node.Image
import org.commonmark.node.IndentedCodeBlock
import org.commonmark.node.Link
import org.commonmark.node.ListItem
import org.commonmark.node.Node
import org.commonmark.node.OrderedList
import org.commonmark.node.Paragraph
import org.commonmark.node.SoftLineBreak
import org.commonmark.node.StrongEmphasis
import org.commonmark.node.Text
import org.commonmark.node.ThematicBreak
import org.commonmark.parser.Parser

/*
 * Reddit-flavoured markdown, parsed into a small immutable model that the
 * Compose renderer ([RedditMarkdown]) draws. Kept free of Android/Compose UI
 * so it can be unit-tested on the JVM and cached across recompositions.
 */

/** Inline style bits for [MdInline.style]. */
object MdStyle {
    const val BOLD = 1
    const val ITALIC = 2
    const val STRIKE = 4
    const val CODE = 8
    const val SUP = 16
}

/** A run of inline text with one style. [spoiler] is the spoiler's index in the document (-1 = none). */
@Immutable
data class MdInline(val text: String, val style: Int = 0, val link: String? = null, val spoiler: Int = -1) {
    fun has(bit: Int) = style and bit != 0
}

@Immutable
sealed interface MdBlock {
    data class Paragraph(val inlines: List<MdInline>) : MdBlock
    data class Heading(val level: Int, val inlines: List<MdInline>) : MdBlock
    data class Quote(val blocks: List<MdBlock>) : MdBlock
    data class ListBlock(val ordered: Boolean, val start: Int, val items: List<List<MdBlock>>) : MdBlock
    data class CodeBlock(val code: String) : MdBlock
    /** [align]: -1 left/none, 0 center, 1 right, per column. */
    data class Table(val header: List<List<MdInline>>, val rows: List<List<List<MdInline>>>, val align: List<Int>) : MdBlock
    data class ImageBlock(val url: String, val alt: String) : MdBlock
    data object Rule : MdBlock
}

@Immutable
data class MdDocument(val blocks: List<MdBlock>, val spoilerCount: Int)

object RedditMarkdownParser {
    // `>!` at the start of a line would be parsed as a blockquote before any
    // inline syntax runs, so spoilers are swapped for private-use markers first.
    private const val OPEN = ''
    private const val CLOSE = ''
    private val spoilerRe = Regex(">!(.+?)!<")

    // `^(several words)` or `^word`, as Reddit renders them.
    private val supRe = Regex("""\^\(([^)\n]+)\)|\^([^\s^()]+)""")

    private val parser: Parser = Parser.builder()
        .extensions(listOf(TablesExtension.create(), StrikethroughExtension.create(), AutolinkExtension.create()))
        .build()

    // Parsing is cheap but a long thread re-binds hundreds of rows while
    // scrolling; keep recent results (keyed by the raw text).
    private val cache = object : LinkedHashMap<String, MdDocument>(256, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, MdDocument>?) = size > 600
    }

    /** Parses (or returns the cached parse of) [text]. Thread-safe. */
    fun parse(text: String): MdDocument {
        synchronized(cache) { cache[text]?.let { return it } }
        val doc = parseUncached(text)
        synchronized(cache) { cache[text] = doc }
        return doc
    }

    fun parseUncached(text: String): MdDocument {
        val src = if (text.contains(">!")) spoilerRe.replace(text) { "$OPEN${it.groupValues[1]}$CLOSE" } else text
        val root = parser.parse(src)
        val b = Builder()
        return MdDocument(b.blocks(root), b.spoilers)
    }

    private class Builder {
        var spoilers = 0
        private var inSpoiler = -1

        fun blocks(parent: Node): List<MdBlock> {
            val out = mutableListOf<MdBlock>()
            var n = parent.firstChild
            while (n != null) {
                block(n, out)
                n = n.next
            }
            return out
        }

        private fun block(n: Node, out: MutableList<MdBlock>) {
            when (n) {
                is Paragraph -> {
                    // Images show as images, also mid-text (`text ![](url) text`,
                    // as flutter_markdown does): the paragraph is split into
                    // text runs around them.
                    val kids = children(n)
                    if (kids.none { it is Image }) {
                        val inl = inlines(kids)
                        if (inl.isNotEmpty()) out.add(MdBlock.Paragraph(inl))
                    } else {
                        var run = mutableListOf<Node>()
                        fun flush() {
                            val inl = inlines(run)
                            if (inl.isNotEmpty()) out.add(MdBlock.Paragraph(inl))
                            run = mutableListOf()
                        }
                        for (k in kids) {
                            if (k is Image) {
                                flush()
                                out.add(MdBlock.ImageBlock(k.destination, altOf(k)))
                            } else {
                                run.add(k)
                            }
                        }
                        flush()
                    }
                }
                is Heading -> out.add(MdBlock.Heading(n.level, inlines(children(n))))
                is BlockQuote -> out.add(MdBlock.Quote(blocks(n)))
                is BulletList -> out.add(MdBlock.ListBlock(false, 1, children(n).filterIsInstance<ListItem>().map { blocks(it) }))
                is OrderedList -> out.add(
                    MdBlock.ListBlock(true, n.markerStartNumber ?: 1, children(n).filterIsInstance<ListItem>().map { blocks(it) }),
                )
                is FencedCodeBlock -> out.add(MdBlock.CodeBlock(n.literal.trimEnd('\n')))
                is IndentedCodeBlock -> out.add(MdBlock.CodeBlock(n.literal.trimEnd('\n')))
                is ThematicBreak -> out.add(MdBlock.Rule)
                is HtmlBlock -> out.add(MdBlock.Paragraph(textRuns(n.literal.trim(), 0, null)))
                is TableBlock -> out.add(table(n))
                else -> if (n.firstChild != null) out.addAll(blocks(n))
            }
        }

        private fun table(t: TableBlock): MdBlock.Table {
            var header: List<List<MdInline>> = emptyList()
            val rows = mutableListOf<List<List<MdInline>>>()
            var align: List<Int> = emptyList()
            for (section in children(t)) {
                for (row in children(section).filterIsInstance<TableRow>()) {
                    val cells = children(row).filterIsInstance<TableCell>()
                    val content = cells.map { inlines(children(it)) }
                    if (section is TableHead) {
                        header = content
                        align = cells.map {
                            when (it.alignment) {
                                TableCell.Alignment.CENTER -> 0
                                TableCell.Alignment.RIGHT -> 1
                                else -> -1
                            }
                        }
                    } else if (section is TableBody) {
                        rows.add(content)
                    }
                }
            }
            return MdBlock.Table(header, rows, align)
        }

        /** Inline runs of [nodes] (a block's children, or a slice of them). */
        fun inlines(nodes: List<Node>): List<MdInline> {
            val out = mutableListOf<MdInline>()
            for (n in nodes) walkNode(n, 0, null, out)
            // Trim the paragraph's outer whitespace and merge equal runs.
            val merged = mutableListOf<MdInline>()
            for (r in out) {
                val last = merged.lastOrNull()
                if (last != null && last.style == r.style && last.link == r.link && last.spoiler == r.spoiler) {
                    merged[merged.size - 1] = last.copy(text = last.text + r.text)
                } else {
                    merged.add(r)
                }
            }
            if (merged.isNotEmpty()) {
                merged[0] = merged[0].copy(text = merged[0].text.trimStart())
                val li = merged.size - 1
                merged[li] = merged[li].copy(text = merged[li].text.trimEnd())
            }
            return merged.filter { it.text.isNotEmpty() }
        }

        private fun walk(parent: Node, style: Int, link: String?, out: MutableList<MdInline>) {
            var n = parent.firstChild
            while (n != null) {
                walkNode(n, style, link, out)
                n = n.next
            }
        }

        private fun walkNode(n: Node, style: Int, link: String?, out: MutableList<MdInline>) {
            when (n) {
                is Text -> out.addAll(textRuns(n.literal, style, link))
                is Code -> out.add(MdInline(n.literal, style or MdStyle.CODE, link, inSpoiler))
                is Emphasis -> walk(n, style or MdStyle.ITALIC, link, out)
                is StrongEmphasis -> walk(n, style or MdStyle.BOLD, link, out)
                is Strikethrough -> walk(n, style or MdStyle.STRIKE, link, out)
                is Link -> walk(n, style, n.destination, out)
                // An image nested in a link or emphasis: its alt text, linking to the image.
                is Image -> out.add(MdInline(altOf(n).ifEmpty { n.destination }, style, n.destination, inSpoiler))
                is SoftLineBreak -> out.add(MdInline(" ", style, link, inSpoiler))
                is HardLineBreak -> out.add(MdInline("\n", style, link, inSpoiler))
                is HtmlInline -> out.addAll(textRuns(n.literal, style, link))
                else -> walk(n, style, link, out)
            }
        }

        /** Splits on spoiler markers and superscripts. */
        fun textRuns(text: String, style: Int, link: String?): List<MdInline> {
            val out = mutableListOf<MdInline>()
            val sb = StringBuilder()
            fun flush() {
                if (sb.isEmpty()) return
                supRuns(sb.toString(), style, link, inSpoiler, out)
                sb.setLength(0)
            }
            for (ch in text) {
                when (ch) {
                    OPEN -> {
                        flush()
                        inSpoiler = spoilers++
                    }
                    CLOSE -> {
                        flush()
                        inSpoiler = -1
                    }
                    else -> sb.append(ch)
                }
            }
            flush()
            return out
        }

        private fun supRuns(text: String, style: Int, link: String?, spoiler: Int, out: MutableList<MdInline>) {
            if (!text.contains('^')) {
                out.add(MdInline(text, style, link, spoiler))
                return
            }
            var i = 0
            for (m in supRe.findAll(text)) {
                if (m.range.first > i) out.add(MdInline(text.substring(i, m.range.first), style, link, spoiler))
                val inner = m.groups[1]?.value ?: m.groups[2]!!.value
                out.add(MdInline(inner, style or MdStyle.SUP, link, spoiler))
                i = m.range.last + 1
            }
            if (i < text.length) out.add(MdInline(text.substring(i), style, link, spoiler))
        }

        private fun altOf(img: Image): String {
            val sb = StringBuilder()
            var c = img.firstChild
            while (c != null) {
                if (c is Text) sb.append(c.literal)
                c = c.next
            }
            return sb.toString()
        }

        private fun children(n: Node): List<Node> {
            val out = mutableListOf<Node>()
            var c = n.firstChild
            while (c != null) {
                out.add(c)
                c = c.next
            }
            return out
        }
    }
}

/** The document's text as one plain string (paragraphs on new lines). */
fun MdDocument.plainText(): String = buildString {
    fun inl(l: List<MdInline>) = l.joinToString("") { it.text }
    fun walk(blocks: List<MdBlock>) {
        for (b in blocks) {
            when (b) {
                is MdBlock.Paragraph -> appendLine(inl(b.inlines))
                is MdBlock.Heading -> appendLine(inl(b.inlines))
                is MdBlock.Quote -> walk(b.blocks)
                is MdBlock.ListBlock -> b.items.forEach { walk(it) }
                is MdBlock.CodeBlock -> appendLine(b.code)
                is MdBlock.Table -> (listOf(b.header) + b.rows).forEach { row -> appendLine(row.joinToString(" | ") { inl(it) }) }
                is MdBlock.ImageBlock -> appendLine(b.alt)
                MdBlock.Rule -> {}
            }
        }
    }
    walk(blocks)
}.trimEnd()
