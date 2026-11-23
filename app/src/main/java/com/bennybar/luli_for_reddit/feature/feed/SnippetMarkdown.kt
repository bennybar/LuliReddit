package com.bennybar.luli_for_reddit.feature.feed

import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withStyle
import com.bennybar.luli_for_reddit.model.Post

/** [Post.snippet] drawn, worked out once per post (and theme). */
@Composable
fun rememberSnippet(p: Post): AnnotatedString {
    val cover = MaterialTheme.colorScheme.onSurfaceVariant
    return remember(p.snippet, cover) { snippetMarkdown(p.snippet, cover) }
}

/**
 * A post's text as a feed shows it, a few lines (#241): the inline markdown drawn
 * (bold, italic, strikethrough, code, spoilers covered in [spoiler]) instead of its
 * `**` and `>!` showing; links as their words, headings bold, quote marks dropped.
 * Not the thread's full markdown: a cheap pass for a few lines. Pure, so it's tested.
 */
fun snippetMarkdown(text: String, spoiler: Color): AnnotatedString = buildAnnotatedString {
    val decoded = text.replace("&lt;", "<").replace("&gt;", ">").replace("&amp;", "&")
    decoded.split('\n').forEachIndexed { n, raw ->
        if (n > 0) append('\n')
        var line = raw
        val heading = Regex("^#{1,6}\\s+").find(line)
        if (heading != null) line = line.substring(heading.range.last + 1)
        // A quote's "> " (not a spoiler's ">!").
        while (line.startsWith(">") && !line.startsWith(">!")) line = line.removePrefix(">").trimStart()
        if (heading != null) withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { inline(line, spoiler) } else inline(line, spoiler)
    }
}

private fun AnnotatedString.Builder.inline(s: String, spoiler: Color) {
    var i = 0
    fun closing(token: String, from: Int): Int {
        val end = s.indexOf(token, from)
        return if (end > from && !s[from].isWhitespace() && !s[end - 1].isWhitespace()) end else -1
    }
    while (i < s.length) {
        val c = s[i]
        when {
            c == '\\' && i + 1 < s.length && !s[i + 1].isLetterOrDigit() -> { append(s[i + 1]); i += 2; continue }
            s.startsWith(">!", i) -> {
                val end = s.indexOf("!<", i + 2)
                if (end > i + 2) {
                    withStyle(SpanStyle(color = spoiler, background = spoiler)) { inline(s.substring(i + 2, end), spoiler) }
                    i = end + 2; continue
                }
            }
            s.startsWith("**", i) || s.startsWith("__", i) || s.startsWith("~~", i) -> {
                val token = s.substring(i, i + 2)
                val end = closing(token, i + 2)
                if (end > 0) {
                    val style = if (token == "~~") SpanStyle(textDecoration = TextDecoration.LineThrough) else SpanStyle(fontWeight = FontWeight.Bold)
                    withStyle(style) { inline(s.substring(i + 2, end), spoiler) }
                    i = end + 2; continue
                }
            }
            c == '`' -> {
                val end = s.indexOf('`', i + 1)
                if (end > i + 1) {
                    withStyle(SpanStyle(fontFamily = FontFamily.Monospace)) { append(s.substring(i + 1, end)) }
                    i = end + 1; continue
                }
            }
            // _italic_ only between words' edges, so snake_case stays as typed.
            c == '*' || (c == '_' && (i == 0 || !s[i - 1].isLetterOrDigit())) -> {
                val end = closing(c.toString(), i + 1)
                if (end > 0 && (c == '*' || end + 1 >= s.length || !s[end + 1].isLetterOrDigit())) {
                    withStyle(SpanStyle(fontStyle = FontStyle.Italic)) { inline(s.substring(i + 1, end), spoiler) }
                    i = end + 1; continue
                }
            }
            c == '[' -> {
                val mid = s.indexOf("](", i + 1)
                val end = if (mid > i) s.indexOf(')', mid + 2) else -1
                if (end > 0) { inline(s.substring(i + 1, mid), spoiler); i = end + 1; continue }
            }
        }
        append(c)
        i++
    }
}
