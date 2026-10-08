package com.bennybar.luli_for_reddit.feature.inbox

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.FormatListBulleted
import androidx.compose.material.icons.rounded.Code
import androidx.compose.material.icons.rounded.FormatBold
import androidx.compose.material.icons.rounded.FormatItalic
import androidx.compose.material.icons.rounded.FormatQuote
import androidx.compose.material.icons.rounded.FormatStrikethrough
import androidx.compose.material.icons.rounded.GifBox
import androidx.compose.material.icons.rounded.Link
import androidx.compose.material.icons.rounded.Person
import androidx.compose.material.icons.automirrored.rounded.Subject
import androidx.compose.material.icons.rounded.VisibilityOff
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.dp
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.core.AppJson
import com.bennybar.luli_for_reddit.core.get
import com.bennybar.luli_for_reddit.core.net.uploadToCatbox
import com.bennybar.luli_for_reddit.core.str
import com.bennybar.luli_for_reddit.feature.auth.BloomTextField
import com.bennybar.luli_for_reddit.feature.compose.AttachmentControls
import com.bennybar.luli_for_reddit.feature.compose.MediaAttachment
import com.bennybar.luli_for_reddit.feature.compose.showGiphyPicker
import com.bennybar.luli_for_reddit.nav.LocalNavigator
import kotlinx.coroutines.launch
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

private const val DRAFT_KEY = "compose_msg"

/** A new private message, to [to] when given. The draft survives leaving the screen. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ComposeMessageScreen(to: String?) {
    val nav = LocalNavigator.current
    val scope = rememberCoroutineScope()
    // Restore the saved draft (the recipient only if none was given).
    val draft = remember {
        runCatching { app.drafts.get(DRAFT_KEY)?.let { AppJson.parseToJsonElement(it) } }.getOrNull()
    }
    var toField by remember {
        mutableStateOf(TextFieldValue(if (to.isNullOrEmpty()) draft["to"].str() ?: "" else to))
    }
    var subject by remember { mutableStateOf(TextFieldValue(draft["subject"].str() ?: "")) }
    var body by remember { mutableStateOf(TextFieldValue(draft["body"].str() ?: "")) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var media by remember { mutableStateOf<MediaAttachment?>(null) }

    fun saveDraft() = app.drafts.save(
        DRAFT_KEY,
        buildJsonObject {
            put("to", toField.text)
            put("subject", subject.text)
            put("body", body.text)
        }.toString(),
    )

    fun send() {
        val recipient = toField.text.trim().removePrefix("/").removePrefix("u/")
        val subj = subject.text.trim()
        var text = body.text.trim()
        val m = media
        if (recipient.isEmpty() || subj.isEmpty() || (text.isEmpty() && m == null)) {
            error = "Recipient, subject and a message or attachment are required."
            return
        }
        busy = true
        error = null
        scope.launch {
            try {
                if (m != null) {
                    // Reddit messages are markdown-text only, so host on Catbox + link.
                    val url = uploadToCatbox(m.bytes, m.filename)
                    text = if (text.isEmpty()) url else "$text\n\n$url"
                }
                app.repository.composeMessage(to = recipient, subject = subj, text = text)
                app.drafts.clear(DRAFT_KEY)
                nav.showSnackbar("Message sent")
                nav.pop()
            } catch (e: Exception) {
                busy = false
                error = (e.message ?: e.toString()).removePrefix("Exception: ")
            }
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("New message", style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Bold)) },
                navigationIcon = {
                    IconButton(onClick = { nav.pop() }) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Back") }
                },
                actions = {
                    Button(onClick = ::send, enabled = !busy, modifier = Modifier.padding(end = 8.dp)) {
                        if (busy) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp) else Text("Send")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                    scrolledContainerColor = MaterialTheme.colorScheme.surface,
                ),
            )
        },
    ) { padding ->
        LazyColumn(
            Modifier.fillMaxSize().padding(padding).imePadding(),
            contentPadding = PaddingValues(16.dp),
        ) {
            item {
                BloomTextField(
                    value = toField,
                    onValueChange = { toField = it; saveDraft() },
                    label = "To",
                    prefix = "u/",
                    leadingIcon = { Icon(Icons.Rounded.Person, null) },
                    plain = true,
                )
                Spacer(Modifier.height(12.dp))
                BloomTextField(
                    value = subject,
                    onValueChange = { subject = it; saveDraft() },
                    label = "Subject",
                    leadingIcon = { Icon(Icons.AutoMirrored.Rounded.Subject, null) },
                )
                Spacer(Modifier.height(12.dp))
                BloomTextField(
                    value = body,
                    onValueChange = { body = it; saveDraft() },
                    label = "Message (Markdown)",
                    singleLine = false,
                    minLines = 6,
                    maxLines = 14,
                )
                MarkdownToolbar(body) { body = it; saveDraft() }
                Spacer(Modifier.height(4.dp))
                AttachmentControls(
                    media = media,
                    onChanged = {
                        media = it
                        error = null
                    },
                    onError = { error = it },
                    catboxForImages = true,
                    leading = {
                        IconButton(onClick = {
                            scope.launch {
                                val gif = showGiphyPicker() ?: return@launch
                                val t = body.text
                                val next = if (t.isBlank()) gif else "${t.trimEnd()}\n\n$gif"
                                body = TextFieldValue(next, TextRange(next.length))
                                saveDraft()
                            }
                        }) { Icon(Icons.Rounded.GifBox, "GIF") }
                    },
                )
                error?.let {
                    Spacer(Modifier.height(8.dp))
                    Text(it, color = MaterialTheme.colorScheme.error)
                }
            }
        }
    }
}

/**
 * A compact formatting toolbar for a Markdown field. Wraps the current
 * selection (or inserts a placeholder at the caret) with Reddit-flavoured
 * markdown, selecting the inner text so typing replaces the placeholder.
 */
@Composable
private fun MarkdownToolbar(value: TextFieldValue, onChange: (TextFieldValue) -> Unit) {
    fun wrap(left: String, right: String, placeholder: String) {
        val text = value.text
        val start = value.selection.min.coerceIn(0, text.length)
        val end = value.selection.max.coerceIn(0, text.length)
        val selected = if (start == end) placeholder else text.substring(start, end)
        val newText = text.replaceRange(start, end, "$left$selected$right")
        onChange(TextFieldValue(newText, TextRange(start + left.length, start + left.length + selected.length)))
    }

    // Prefixes each selected line (or the caret's line) with [prefix].
    fun linePrefix(prefix: String) {
        val text = value.text
        val selStart = value.selection.min.coerceIn(0, text.length)
        val selEnd = value.selection.max.coerceIn(0, text.length)
        val lineStart = if (selStart == 0) 0 else text.lastIndexOf('\n', selStart - 1) + 1
        val lineEnd = text.indexOf('\n', selEnd).let { if (it == -1) text.length else it }
        val updated = text.substring(lineStart, lineEnd).split('\n').joinToString("\n") { "$prefix$it" }
        onChange(TextFieldValue(text.replaceRange(lineStart, lineEnd, updated), TextRange(lineStart + updated.length)))
    }

    val buttons: List<Triple<ImageVector, String, () -> Unit>> = listOf(
        Triple(Icons.Rounded.FormatBold, "Bold") { wrap("**", "**", "bold") },
        Triple(Icons.Rounded.FormatItalic, "Italic") { wrap("*", "*", "italic") },
        Triple(Icons.Rounded.FormatStrikethrough, "Strikethrough") { wrap("~~", "~~", "text") },
        Triple(Icons.Rounded.Link, "Link") { wrap("[", "](https://)", "text") },
        Triple(Icons.Rounded.FormatQuote, "Quote") { linePrefix("> ") },
        Triple(Icons.AutoMirrored.Rounded.FormatListBulleted, "List") { linePrefix("- ") },
        Triple(Icons.Rounded.VisibilityOff, "Spoiler") { wrap(">!", "!<", "spoiler") },
        Triple(Icons.Rounded.Code, "Code") { wrap("`", "`", "code") },
    )
    LazyRow(Modifier.height(40.dp), horizontalArrangement = Arrangement.Start) {
        items(buttons.size) { i ->
            val (icon, tip, action) = buttons[i]
            IconButton(onClick = action) {
                Icon(icon, tip, Modifier.size(20.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}
