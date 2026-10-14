package com.bennybar.luli_for_reddit.feature.compose

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.content.MediaType
import androidx.compose.foundation.content.consume
import androidx.compose.foundation.content.contentReceiver
import androidx.compose.foundation.content.hasMediaType
import androidx.compose.foundation.text.input.TextFieldState
import androidx.compose.foundation.text.input.rememberTextFieldState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.TextFieldValue
import kotlinx.coroutines.launch

/**
 * A [TextFieldState] kept in step with [value] both ways. Only the
 * state-based text fields can take GIFs and stickers from the keyboard, while
 * the composers (and the Markdown toolbar) work on a [TextFieldValue].
 */
@Composable
fun rememberMirroredState(value: TextFieldValue, onValueChange: (TextFieldValue) -> Unit): TextFieldState {
    val state = rememberTextFieldState(value.text, value.selection)
    // The last value the field itself reported: its echo must not be written
    // back, or a fast typist's newer letters get replaced by the older text.
    val fromField = remember { arrayOf(value) }
    // Edits from outside the field (toolbar, GIF button, cleared after send).
    LaunchedEffect(value.text, value.selection) {
        val own = fromField[0]
        if (value.text == own.text && value.selection == own.selection) return@LaunchedEffect
        if (state.text.toString() != value.text || state.selection != value.selection) {
            state.edit {
                replace(0, length, value.text)
                selection = value.selection
            }
        }
    }
    // Typing in the field.
    val latestOnChange by rememberUpdatedState(onValueChange)
    LaunchedEffect(state) {
        snapshotFlow { state.text.toString() to state.selection }.collect { (text, selection) ->
            val own = fromField[0]
            if (text != own.text || selection != own.selection) {
                val v = TextFieldValue(text, selection)
                fromField[0] = v
                latestOnChange(v)
            }
        }
    }
    return state
}

/**
 * Takes images, GIFs and stickers sent by the keyboard (Gboard, Samsung
 * Keyboard…) as an attachment, like one picked from the gallery.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun keyboardMediaReceiver(onMedia: (MediaAttachment) -> Unit, onError: (String) -> Unit): Modifier {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    return Modifier.contentReceiver { content ->
        if (!content.hasMediaType(MediaType.Image)) return@contentReceiver content
        var uri: android.net.Uri? = null
        val rest = content.consume { item -> if (uri == null && item.uri != null) { uri = item.uri; true } else false }
        uri?.let { u ->
            scope.launch {
                try {
                    onMedia(readAttachment(context, u, isVideo = false))
                } catch (e: Exception) {
                    onError((e.message ?: e.toString()).removePrefix("Exception: "))
                }
            }
        }
        rest
    }
}
