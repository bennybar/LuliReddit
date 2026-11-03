package com.bennybar.luli_for_reddit.feature.compose

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.sp

/*
 * Reddit's length limits, in characters: it refuses anything longer, so the
 * composers count down and block sending past them instead.
 */
/** Comments, replies and messages. */
const val COMMENT_LIMIT = 10_000
const val POST_BODY_LIMIT = 40_000
const val TITLE_LIMIT = 300

/** Characters as Reddit counts them (code points: an emoji is one, not two UTF-16 units). */
fun redditLength(text: String): Int = text.codePointCount(0, text.length)

/** "9100 / 10000" once [text] is within 10% of [limit], null before that. */
fun lengthCounter(text: String, limit: Int): String? {
    val count = redditLength(text)
    return if (count * 10 >= limit * 9) "$count / $limit" else null
}

/** The counter under a field, in the error colour once over the limit; nothing while far from it. */
@Composable
fun LengthCounter(text: String, limit: Int, modifier: Modifier = Modifier) {
    val label = lengthCounter(text, limit) ?: return
    val cs = MaterialTheme.colorScheme
    Text(
        label,
        modifier.fillMaxWidth(),
        fontSize = 12.sp,
        textAlign = TextAlign.End,
        color = if (redditLength(text) > limit) cs.error else cs.onSurfaceVariant,
    )
}
