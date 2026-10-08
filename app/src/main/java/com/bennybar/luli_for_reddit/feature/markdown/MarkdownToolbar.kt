package com.bennybar.luli_for_reddit.feature.markdown

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.FormatListBulleted
import androidx.compose.material.icons.rounded.Code
import androidx.compose.material.icons.rounded.FormatBold
import androidx.compose.material.icons.rounded.FormatItalic
import androidx.compose.material.icons.rounded.FormatQuote
import androidx.compose.material.icons.rounded.FormatStrikethrough
import androidx.compose.material.icons.rounded.Link
import androidx.compose.material.icons.rounded.VisibilityOff
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.PlainTooltip
import androidx.compose.material3.Text
import androidx.compose.material3.TooltipAnchorPosition
import androidx.compose.material3.TooltipBox
import androidx.compose.material3.TooltipDefaults
import androidx.compose.material3.rememberTooltipState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.dp

/** A text edit result: new text + selection. */
data class MdEdit(val text: String, val selStart: Int, val selEnd: Int)

/**
 * Wraps the selection (or inserts [placeholder] at the caret) with [left]/[right]
 * and selects the inner text so the user can keep typing over it. An invalid
 * selection (-1) acts at the end of the text.
 */
fun mdWrap(text: String, selStart: Int, selEnd: Int, left: String, right: String, placeholder: String = ""): MdEdit {
    val valid = selStart >= 0 && selEnd >= 0
    val start = if (valid) minOf(selStart, selEnd).coerceAtMost(text.length) else text.length
    val end = if (valid) maxOf(selStart, selEnd).coerceAtMost(text.length) else text.length
    val selected = if (start == end) placeholder else text.substring(start, end)
    val newText = text.replaceRange(start, end, "$left$selected$right")
    return MdEdit(newText, start + left.length, start + left.length + selected.length)
}

/** Prefixes each selected line (or the caret's line) with [prefix]; caret goes to the block's end. */
fun mdLinePrefix(text: String, selStart: Int, selEnd: Int, prefix: String): MdEdit {
    val valid = selStart >= 0 && selEnd >= 0
    val start = if (valid) minOf(selStart, selEnd).coerceAtMost(text.length) else text.length
    val end = if (valid) maxOf(selStart, selEnd).coerceAtMost(text.length) else text.length
    val lineStart = if (start == 0) 0 else text.lastIndexOf('\n', start - 1) + 1
    var lineEnd = text.indexOf('\n', end)
    if (lineEnd == -1) lineEnd = text.length
    val updated = text.substring(lineStart, lineEnd).split('\n').joinToString("\n") { "$prefix$it" }
    val newText = text.replaceRange(lineStart, lineEnd, updated)
    val caret = lineStart + updated.length
    return MdEdit(newText, caret, caret)
}

/** Long-press tooltip over an icon button (Flutter's `IconButton(tooltip:)`). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun IconTooltip(text: String, content: @Composable () -> Unit) {
    TooltipBox(
        positionProvider = TooltipDefaults.rememberTooltipPositionProvider(TooltipAnchorPosition.Above),
        tooltip = { PlainTooltip { Text(text) } },
        state = rememberTooltipState(),
        content = content,
    )
}

private fun TextFieldValue.apply(e: MdEdit) = TextFieldValue(e.text, TextRange(e.selStart, e.selEnd))

/**
 * A compact formatting toolbar for a Markdown text field. Wraps the current
 * selection (or inserts placeholders at the caret) with Reddit-flavored
 * markdown. Place it directly above/below the field sharing its value.
 */
@Composable
fun MarkdownToolbar(value: TextFieldValue, onValueChange: (TextFieldValue) -> Unit, modifier: Modifier = Modifier) {
    val tint = MaterialTheme.colorScheme.onSurfaceVariant
    fun wrap(l: String, r: String, ph: String) =
        onValueChange(value.apply(mdWrap(value.text, value.selection.start, value.selection.end, l, r, ph)))
    fun prefix(p: String) =
        onValueChange(value.apply(mdLinePrefix(value.text, value.selection.start, value.selection.end, p)))

    @Composable
    fun btn(icon: ImageVector, tip: String, onClick: () -> Unit) {
        IconTooltip(tip) {
            IconButton(onClick = onClick, modifier = Modifier.size(40.dp)) {
                Icon(icon, contentDescription = tip, tint = tint, modifier = Modifier.size(20.dp))
            }
        }
    }

    Row(modifier.height(40.dp).horizontalScroll(rememberScrollState())) {
        btn(Icons.Rounded.FormatBold, "Bold") { wrap("**", "**", "bold") }
        btn(Icons.Rounded.FormatItalic, "Italic") { wrap("*", "*", "italic") }
        btn(Icons.Rounded.FormatStrikethrough, "Strikethrough") { wrap("~~", "~~", "text") }
        btn(Icons.Rounded.Link, "Link") { wrap("[", "](https://)", "text") }
        btn(Icons.Rounded.FormatQuote, "Quote") { prefix("> ") }
        btn(Icons.AutoMirrored.Rounded.FormatListBulleted, "List") { prefix("- ") }
        btn(Icons.Rounded.VisibilityOff, "Spoiler") { wrap(">!", "!<", "spoiler") }
        btn(Icons.Rounded.Code, "Code") { wrap("`", "`", "code") }
    }
}
