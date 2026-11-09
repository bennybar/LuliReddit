package com.bennybar.luli_for_reddit.feature.compose

import com.bennybar.luli_for_reddit.ui.SearchIcon
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bennybar.luli_for_reddit.feature.feed.Tile
import com.bennybar.luli_for_reddit.feature.feed.rememberFlairText
import com.bennybar.luli_for_reddit.feature.post.BloomFieldShape
import com.bennybar.luli_for_reddit.feature.post.bloomFieldColors
import com.bennybar.luli_for_reddit.feature.settings.TextResult
import com.bennybar.luli_for_reddit.feature.settings.textDialog
import com.bennybar.luli_for_reddit.model.Flair
import com.bennybar.luli_for_reddit.model.FlairPart
import com.bennybar.luli_for_reddit.model.UserFlair
import com.bennybar.luli_for_reddit.ui.Overlays

/** What the post flair picker returned: [flair] null is "No flair"; an editable one carries your text. */
data class LinkFlairPick(val flair: Flair?)

/** Reddit's longest flair text. */
private const val FLAIR_TEXT_LIMIT = 64

/** The flairs whose words contain [query] (any case); all of them for a blank query. */
fun filterFlairs(flairs: List<Flair>, query: String): List<Flair> {
    val q = query.trim()
    if (q.isEmpty()) return flairs
    return flairs.filter { (it.label?.text ?: it.text).contains(q, ignoreCase = true) }
}

/**
 * Picks a post flair in r/[subreddit] (#87, #88): a searchable sheet of the
 * flairs as their own coloured chips, "No flair", a check on [current]; an
 * editable flair then asks for its text. Null when cancelled.
 */
@OptIn(ExperimentalMaterial3Api::class)
suspend fun pickLinkFlair(subreddit: String, flairs: List<Flair>, current: Flair?): LinkFlairPick? {
    val picked = Overlays.show<LinkFlairPick> { done ->
        val cs = MaterialTheme.colorScheme
        var query by remember { mutableStateOf("") }
        val shown = remember(query) { filterFlairs(flairs, query) }
        // Expanded: a long list needs the room, and the search field stays above the keyboard.
        ModalBottomSheet(onDismissRequest = { done(null) }, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
            Column(Modifier.navigationBarsPadding()) {
                Text(
                    "Flair in r/$subreddit",
                    Modifier.padding(start = 20.dp, top = 4.dp, end = 20.dp, bottom = 8.dp),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                )
                TextField(
                    value = query,
                    onValueChange = { query = it },
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                    placeholder = { Text("Search flairs") },
                    leadingIcon = { Icon(SearchIcon, null) },
                    singleLine = true,
                    shape = BloomFieldShape,
                    colors = bloomFieldColors(),
                )
                LazyColumn(Modifier.padding(top = 8.dp, bottom = 8.dp)) {
                    if (query.isBlank()) {
                        item(key = "none") {
                            Tile(
                                title = { Text("No flair") },
                                trailing = { if (current == null) Icon(Icons.Rounded.CheckCircle, null, tint = cs.primary) },
                                onClick = { done(LinkFlairPick(null)) },
                            )
                        }
                    }
                    items(shown, key = { it.id }) { f ->
                        Tile(
                            title = { FlairTemplateChip(f) },
                            subtitle = if (f.editable) ({ Text("You can change the text") }) else null,
                            trailing = { if (f.id == current?.id) Icon(Icons.Rounded.CheckCircle, null, tint = cs.primary) },
                            onClick = { done(LinkFlairPick(f)) },
                        )
                    }
                    if (shown.isEmpty()) {
                        item(key = "empty") {
                            Text("No flair matches", Modifier.padding(20.dp), color = cs.onSurfaceVariant)
                        }
                    }
                }
            }
        }
    } ?: return null
    val f = picked.flair
    if (f == null || !f.editable) return picked
    val r = textDialog(
        "Flair text",
        initial = current?.takeIf { it.id == f.id }?.text ?: f.text,
        note = "Up to $FLAIR_TEXT_LIMIT characters",
    ) as? TextResult.Save ?: return null
    val text = r.text.trim().take(FLAIR_TEXT_LIMIT).ifEmpty { f.text }
    // The chip shows your words now, not the template's.
    return LinkFlairPick(f.copy(text = text, label = UserFlair(listOf(FlairPart(text = text)))))
}

/** A post flair as Reddit styles it: its background colour and light or dark text, emoji inline. */
@Composable
fun FlairTemplateChip(f: Flair) {
    val cs = MaterialTheme.colorScheme
    val bg = f.backgroundColor?.let { Color(0xFF000000 or it.toLong()) }
    val fg = when {
        bg == null -> cs.onSurfaceVariant
        f.lightText -> Color.White
        else -> Color(0xFF1C1B1F)
    }
    val label = f.label
    val modifier = Modifier.widthIn(max = 280.dp).background(bg ?: cs.surfaceContainerHighest, RoundedCornerShape(8.dp)).padding(horizontal = 10.dp, vertical = 4.dp)
    if (label == null) {
        Text(f.text, modifier, fontSize = 13.sp, color = fg, maxLines = 2, overflow = TextOverflow.Ellipsis)
    } else {
        val (text, emoji) = rememberFlairText(label)
        Text(text, modifier, fontSize = 13.sp, color = fg, maxLines = 2, overflow = TextOverflow.Ellipsis, inlineContent = emoji)
    }
}
