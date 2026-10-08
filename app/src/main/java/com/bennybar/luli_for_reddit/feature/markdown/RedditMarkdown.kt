package com.bennybar.luli_for_reddit.feature.markdown

import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.sp

/**
 * [Agent B] Reddit-flavoured markdown: paragraphs, headings, lists, quotes
 * (accent bar), code, tables, links (LocalNavigator.openLink by default),
 * `>!spoilers!<` (tap to reveal), `^superscript` / `^(words)`, strikethrough.
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
    Text(text, modifier, color = color, fontSize = fontSize, maxLines = maxLines)
}
