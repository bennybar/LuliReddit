package com.bennybar.luli_for_reddit.feature.markdown

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.takeOrElse
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.BaselineShift
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import coil3.compose.AsyncImage
import com.bennybar.luli_for_reddit.nav.LocalNavigator

/**
 * Reddit-flavoured markdown: paragraphs, headings, lists, quotes
 * (accent bar), code, tables, links (LocalNavigator.openLink by default),
 * `>!spoilers!<` (tap to reveal), `^superscript` / `^(words)`, strikethrough.
 *
 * Parsing is cached ([RedditMarkdownParser.parse]); inline text is built
 * into one AnnotatedString per paragraph with LinkAnnotations, so links and
 * spoilers don't break the line.
 */
@Composable
fun RedditMarkdown(
    text: String,
    modifier: Modifier = Modifier,
    fontSize: TextUnit = 15.sp,
    color: Color = Color.Unspecified,
    maxLines: Int = Int.MAX_VALUE,
    selectable: Boolean = false,
    onLinkClick: ((String) -> Unit)? = null,
) {
    val doc = remember(text) { RedditMarkdownParser.parse(text) }
    val nav = LocalNavigator.current
    val cs = MaterialTheme.colorScheme
    val typo = MaterialTheme.typography
    val textColor = color.takeOrElse { LocalContentColor.current }
    var revealed by remember(text) { mutableStateOf(emptySet<Int>()) }
    val onLink: (String) -> Unit = onLinkClick ?: { nav.openLink(it) }

    val ctx = MdContext(
        base = typo.bodyMedium.copy(fontSize = fontSize, lineHeight = 1.45.em, color = textColor),
        fontSize = fontSize,
        textColor = textColor,
        link = cs.primary,
        codeBg = cs.surfaceContainerHighest,
        quoteBg = cs.surfaceContainerHighest,
        quoteBar = cs.primary,
        quoteText = cs.onSurfaceVariant,
        spoiler = cs.onSurfaceVariant,
        revealedBg = cs.surfaceContainerHighest,
        border = cs.outlineVariant,
        headings = listOf(typo.headlineSmall, typo.titleLarge, typo.titleMedium, typo.bodyLarge, typo.bodyLarge, typo.bodyLarge),
        revealed = revealed,
        onReveal = { revealed = revealed + it },
        onLink = onLink,
    )

    if (maxLines != Int.MAX_VALUE) {
        // Previews: one text block, ellipsized.
        val flat = remember(doc) { flattenInlines(doc.blocks) }
        val s = remember(flat, revealed, textColor, cs.primary, fontSize) { ctx.annotate(flat) }
        Text(
            s,
            modifier,
            style = ctx.base,
            maxLines = maxLines,
            overflow = TextOverflow.Ellipsis,
        )
        return
    }
    if (selectable) {
        SelectionContainer(modifier) { Blocks(doc.blocks, ctx, Modifier) }
    } else {
        Blocks(doc.blocks, ctx, modifier)
    }
}

@Immutable
private class MdContext(
    val base: TextStyle,
    val fontSize: TextUnit,
    val textColor: Color,
    val link: Color,
    val codeBg: Color,
    val quoteBg: Color,
    val quoteBar: Color,
    val quoteText: Color,
    val spoiler: Color,
    val revealedBg: Color,
    val border: Color,
    val headings: List<TextStyle>,
    val revealed: Set<Int>,
    val onReveal: (Int) -> Unit,
    val onLink: (String) -> Unit,
) {
    fun withColor(c: Color) = MdContext(
        base.copy(color = c), fontSize, c, link, codeBg, quoteBg, quoteBar, quoteText, spoiler, revealedBg, border,
        headings, revealed, onReveal, onLink,
    )

    fun annotate(inlines: List<MdInline>, size: TextUnit = fontSize): AnnotatedString = buildAnnotatedString {
        for (r in inlines) {
            var s = SpanStyle()
            if (r.has(MdStyle.BOLD)) s = s.merge(SpanStyle(fontWeight = FontWeight.Bold))
            if (r.has(MdStyle.ITALIC)) s = s.merge(SpanStyle(fontStyle = FontStyle.Italic))
            if (r.has(MdStyle.STRIKE)) s = s.merge(SpanStyle(textDecoration = TextDecoration.LineThrough))
            if (r.has(MdStyle.CODE)) {
                s = s.merge(SpanStyle(fontFamily = FontFamily.Monospace, background = codeBg, fontSize = size * 0.9f))
            }
            if (r.has(MdStyle.SUP)) s = s.merge(SpanStyle(fontSize = size * 0.75f, baselineShift = BaselineShift.Superscript))
            val hiddenSpoiler = r.spoiler >= 0 && r.spoiler !in revealed
            when {
                // Same colour for text and background: a solid block until tapped.
                hiddenSpoiler -> {
                    s = s.merge(SpanStyle(color = spoiler, background = spoiler))
                    val idx = r.spoiler
                    withLink(LinkAnnotation.Clickable("spoiler$idx") { onReveal(idx) }) { withStyle(s) { append(r.text) } }
                }
                r.link != null -> {
                    if (r.spoiler >= 0) s = s.merge(SpanStyle(background = revealedBg))
                    val href = r.link
                    withLink(
                        LinkAnnotation.Clickable(href, TextLinkStyles(SpanStyle(color = link))) { onLink(href) },
                    ) { withStyle(s) { append(r.text) } }
                }
                else -> {
                    if (r.spoiler >= 0) s = s.merge(SpanStyle(background = revealedBg))
                    withStyle(s) { append(r.text) }
                }
            }
        }
    }
}

@Composable
private fun Blocks(blocks: List<MdBlock>, ctx: MdContext, modifier: Modifier) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        for (b in blocks) Block(b, ctx)
    }
}

@Composable
private fun Block(b: MdBlock, ctx: MdContext) {
    when (b) {
        is MdBlock.Paragraph -> {
            val s = remember(b, ctx.revealed, ctx.textColor, ctx.link, ctx.fontSize) { ctx.annotate(b.inlines) }
            Text(s, style = ctx.base)
        }
        is MdBlock.Heading -> {
            val style = ctx.headings[(b.level - 1).coerceIn(0, 5)].copy(color = ctx.textColor)
            val s = remember(b, ctx.revealed, ctx.textColor, ctx.link, style.fontSize) { ctx.annotate(b.inlines, style.fontSize) }
            Text(s, style = style)
        }
        is MdBlock.Quote -> {
            // Reddit-style blockquote: left accent bar + subtle background,
            // readable text (the old light-blue box was low-contrast in dark mode).
            val bar = ctx.quoteBar
            Box(
                Modifier
                    .fillMaxWidth()
                    .background(ctx.quoteBg)
                    .drawBehind { drawRect(bar, Offset.Zero, Size(3.dp.toPx(), size.height)) }
                    .padding(start = 12.dp, top = 6.dp, end = 12.dp, bottom = 6.dp),
            ) {
                Blocks(b.blocks, ctx.withColor(ctx.quoteText), Modifier)
            }
        }
        is MdBlock.ListBlock -> {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                b.items.forEachIndexed { i, item ->
                    Row {
                        Text(
                            if (b.ordered) "${b.start + i}." else "•",
                            Modifier.widthIn(min = 22.dp).padding(end = 6.dp),
                            style = ctx.base,
                            textAlign = TextAlign.End,
                        )
                        Blocks(item, ctx, Modifier.weight(1f))
                    }
                }
            }
        }
        is MdBlock.CodeBlock -> {
            Box(
                Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(8.dp))
                    .background(ctx.codeBg)
                    .horizontalScroll(rememberScrollState())
                    .padding(8.dp),
            ) {
                Text(b.code, style = ctx.base.copy(fontFamily = FontFamily.Monospace, fontSize = ctx.fontSize * 0.9f), softWrap = false)
            }
        }
        is MdBlock.Table -> Table(b, ctx)
        is MdBlock.ImageBlock -> {
            if (b.url.startsWith("http")) {
                // At its own size, one image pixel per dp like Flutter's Image (an
                // emote stays small), shrunk to fit the width.
                var size by remember(b.url) { mutableStateOf<Size?>(null) }
                val sz = size
                AsyncImage(
                    model = b.url,
                    contentDescription = b.alt,
                    contentScale = ContentScale.Fit,
                    onSuccess = { size = it.painter.intrinsicSize },
                    modifier = Modifier
                        .then(
                            if (sz != null && sz.width > 0f && sz.height > 0f) {
                                Modifier
                                    .widthIn(max = sz.width.dp)
                                    .fillMaxWidth()
                                    .heightIn(max = 400.dp)
                                    .aspectRatio(sz.width / sz.height)
                            } else {
                                Modifier.fillMaxWidth().heightIn(max = 400.dp)
                            },
                        )
                        .clip(RoundedCornerShape(12.dp))
                        .clickable { ctx.onLink(b.url) },
                )
            } else if (b.alt.isNotEmpty()) {
                Text(b.alt, style = ctx.base)
            }
        }
        MdBlock.Rule -> HorizontalDivider(color = ctx.border)
    }
}

/** Column-major so each column is as wide as its widest cell; cells don't wrap (the table scrolls). */
@Composable
private fun Table(t: MdBlock.Table, ctx: MdContext) {
    val cols = maxOf(t.header.size, t.rows.maxOfOrNull { it.size } ?: 0)
    Row(
        Modifier
            .horizontalScroll(rememberScrollState())
            .clip(RoundedCornerShape(8.dp))
            .border(1.dp, ctx.border, RoundedCornerShape(8.dp)),
    ) {
        for (c in 0 until cols) {
            Column(Modifier.width(IntrinsicSize.Max)) {
                val align = when (t.align.getOrNull(c)) { 0 -> TextAlign.Center; 1 -> TextAlign.End; else -> TextAlign.Start }
                Cell(t.header.getOrNull(c).orEmpty(), ctx, header = true, align = align)
                for (row in t.rows) Cell(row.getOrNull(c).orEmpty(), ctx, header = false, align = align)
            }
        }
    }
}

@Composable
private fun Cell(inlines: List<MdInline>, ctx: MdContext, header: Boolean, align: TextAlign) {
    val s = remember(inlines, ctx.revealed, ctx.textColor, ctx.link, ctx.fontSize) { ctx.annotate(inlines) }
    Text(
        s,
        Modifier
            .fillMaxWidth()
            .then(if (header) Modifier.background(ctx.codeBg) else Modifier)
            .border(0.5.dp, ctx.border)
            .padding(horizontal = 10.dp, vertical = 6.dp),
        style = ctx.base.copy(fontWeight = if (header) FontWeight.Bold else ctx.base.fontWeight, textAlign = align),
        softWrap = false,
    )
}

/** All inline runs, blocks separated by newlines (for maxLines previews). */
private fun flattenInlines(blocks: List<MdBlock>): List<MdInline> {
    val out = mutableListOf<MdInline>()
    fun nl() {
        if (out.isNotEmpty()) out.add(MdInline("\n"))
    }
    fun walk(bs: List<MdBlock>) {
        for (b in bs) {
            when (b) {
                is MdBlock.Paragraph -> { nl(); out.addAll(b.inlines) }
                is MdBlock.Heading -> { nl(); out.addAll(b.inlines.map { it.copy(style = it.style or MdStyle.BOLD) }) }
                is MdBlock.Quote -> walk(b.blocks)
                is MdBlock.ListBlock -> b.items.forEachIndexed { i, item ->
                    nl()
                    out.add(MdInline(if (b.ordered) "${b.start + i}. " else "• "))
                    val before = out.size
                    walk(item)
                    // The item's first paragraph sits on the bullet's line.
                    if (out.size > before && out[before].text == "\n") out.removeAt(before)
                }
                is MdBlock.CodeBlock -> { nl(); out.add(MdInline(b.code, MdStyle.CODE)) }
                is MdBlock.Table -> (listOf(b.header) + b.rows).forEach { row ->
                    nl()
                    row.forEachIndexed { i, cell -> if (i > 0) out.add(MdInline(" | ")); out.addAll(cell) }
                }
                is MdBlock.ImageBlock -> { nl(); out.add(MdInline(b.alt.ifEmpty { b.url }, link = b.url)) }
                MdBlock.Rule -> {}
            }
        }
    }
    walk(blocks)
    return out
}
