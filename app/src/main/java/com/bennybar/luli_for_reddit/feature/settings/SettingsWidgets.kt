package com.bennybar.luli_for_reddit.feature.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bennybar.luli_for_reddit.ui.Overlays
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** A primary-coloured section header ("Appearance", "Feed", …). */
@Composable
internal fun SectionHeader(title: String, subtitle: String? = null) {
    Column(Modifier.fillMaxWidth().padding(start = 16.dp, top = if (subtitle == null) 16.dp else 18.dp, end = 16.dp, bottom = 4.dp)) {
        Text(
            title,
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.primary,
            fontWeight = FontWeight.Bold,
        )
        if (subtitle != null) {
            Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

private val clearItem @Composable get() = ListItemDefaults.colors(containerColor = Color.Transparent)

/** A settings row (the Flutter ListTile). [onClick] null = not tappable. */
@Composable
internal fun SettingTile(
    title: String,
    subtitle: String? = null,
    icon: ImageVector? = null,
    enabled: Boolean = true,
    titleColor: Color? = null,
    iconTint: Color? = null,
    leadingSpacer: Boolean = false,
    trailing: (@Composable () -> Unit)? = null,
    onClick: (() -> Unit)? = null,
) {
    ListItem(
        modifier = Modifier
            .then(if (onClick != null) Modifier.clickable(enabled = enabled, onClick = onClick) else Modifier)
            .alpha(if (enabled) 1f else 0.38f),
        colors = clearItem,
        leadingContent = when {
            icon != null -> ({ Icon(icon, null, tint = iconTint ?: MaterialTheme.colorScheme.onSurfaceVariant) })
            leadingSpacer -> ({ Spacer(Modifier.size(24.dp)) })
            else -> null
        },
        headlineContent = { Text(title, color = titleColor ?: Color.Unspecified) },
        supportingContent = subtitle?.let { { Text(it) } },
        trailingContent = trailing,
    )
}

/** A settings switch row (the Flutter SwitchListTile). [onChange] null = disabled. */
@Composable
internal fun SwitchTile(
    title: String,
    subtitle: String? = null,
    icon: ImageVector? = null,
    checked: Boolean,
    accent: Color? = null,
    titleWeight: FontWeight? = null,
    onChange: ((Boolean) -> Unit)?,
) {
    val enabled = onChange != null
    ListItem(
        modifier = Modifier
            .clickable(enabled = enabled) { onChange?.invoke(!checked) }
            .alpha(if (enabled) 1f else 0.38f),
        colors = clearItem,
        leadingContent = icon?.let { { Icon(it, null, tint = accent ?: MaterialTheme.colorScheme.onSurfaceVariant) } },
        headlineContent = { Text(title, color = accent ?: Color.Unspecified, fontWeight = titleWeight) },
        supportingContent = subtitle?.let { { Text(it, color = accent ?: Color.Unspecified) } },
        trailingContent = {
            Switch(
                checked = checked,
                onCheckedChange = onChange,
                enabled = enabled,
                colors = if (accent != null) {
                    SwitchDefaults.colors(checkedTrackColor = accent, checkedThumbColor = MaterialTheme.colorScheme.onError)
                } else SwitchDefaults.colors(),
            )
        },
    )
}

/**
 * A modal bottom sheet for [Overlays.show]: [close] animates it away, then
 * reports the result. Taps are ignored for the first 300ms so the gesture
 * that opened it can't fall through onto an item (Flutter's TapGuard).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun <T> OverlaySheet(done: (T?) -> Unit, content: @Composable ColumnScope.(close: (T?) -> Unit) -> Unit) {
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val scope = rememberCoroutineScope()
    var guard by remember { mutableStateOf(true) }
    LaunchedEffect(Unit) {
        delay(300)
        guard = false
    }
    val close: (T?) -> Unit = { r ->
        if (!guard) scope.launch { state.hide() }.invokeOnCompletion { done(r) }
    }
    ModalBottomSheet(onDismissRequest = { done(null) }, sheetState = state) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).navigationBarsPadding()) {
            content(close)
        }
    }
}

/** One choice in a picker sheet. */
internal class PickOption<T>(
    val value: T,
    val label: String,
    val subtitle: String? = null,
    val icon: ImageVector? = null,
)

/**
 * A single-choice sheet. [radio] = radio buttons (Flutter RadioListTile),
 * else a trailing check on the current one. Null when dismissed.
 */
internal suspend fun <T> pickOption(options: List<PickOption<T>>, current: T?, radio: Boolean = true): T? =
    Overlays.show<PickOption<T>> { done ->
        OverlaySheet<PickOption<T>>(done) { close ->
            for (o in options) {
                val selected = o.value == current
                ListItem(
                    modifier = Modifier.clickable { close(o) },
                    colors = clearItem,
                    leadingContent = if (radio) ({ RadioButton(selected = selected, onClick = { close(o) }) }) else null,
                    headlineContent = { Text(o.label) },
                    supportingContent = o.subtitle?.let { { Text(it) } },
                    trailingContent = when {
                        !radio && selected -> ({ Icon(Icons.Rounded.Check, null) })
                        radio && o.icon != null -> ({ Icon(o.icon, null) })
                        else -> null
                    },
                )
            }
            Spacer(Modifier.height(8.dp))
        }
    }?.value

/** A yes/no dialog. True if confirmed. */
internal suspend fun confirmDialog(
    title: String,
    text: String,
    confirm: String,
    cancel: String = "Cancel",
): Boolean = Overlays.show<Boolean> { done ->
    AlertDialog(
        onDismissRequest = { done(false) },
        title = { Text(title) },
        text = { Text(text) },
        dismissButton = { TextButton(onClick = { done(false) }) { Text(cancel) } },
        confirmButton = { Button(onClick = { done(true) }) { Text(confirm) } },
    )
} == true

/** An info dialog with a single [close] button. */
internal suspend fun infoDialog(title: String, text: String, close: String = "Close") {
    Overlays.show<Unit> { done ->
        AlertDialog(
            onDismissRequest = { done(null) },
            title = { Text(title) },
            text = { Column(Modifier.verticalScroll(rememberScrollState())) { Text(text) } },
            confirmButton = { TextButton(onClick = { done(null) }) { Text(close) } },
        )
    }
}

/** What a text-entry dialog returned. */
internal sealed interface TextResult {
    data class Save(val text: String) : TextResult
    data object Remove : TextResult
}

/**
 * A single-field dialog. [secret] hides the text; [removable] adds a
 * "Remove" action. Null when cancelled.
 */
internal suspend fun textDialog(
    title: String,
    initial: String = "",
    hint: String? = null,
    note: String? = null,
    secret: Boolean = false,
    removable: Boolean = false,
    keyboardType: KeyboardType = KeyboardType.Text,
): TextResult? = Overlays.show<TextResult> { done ->
    var text by remember { mutableStateOf(initial) }
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { focus.requestFocus() }
    AlertDialog(
        onDismissRequest = { done(null) },
        title = { Text(title) },
        text = {
            Column {
                TextField(
                    value = text,
                    onValueChange = { text = it },
                    singleLine = true,
                    placeholder = hint?.let { { Text(it) } },
                    visualTransformation = if (secret) PasswordVisualTransformation() else VisualTransformation.None,
                    keyboardOptions = KeyboardOptions(
                        keyboardType = if (secret) KeyboardType.Password else keyboardType,
                        autoCorrectEnabled = false,
                    ),
                    shape = RoundedCornerShape(18.dp),
                    colors = TextFieldDefaults.colors(
                        focusedIndicatorColor = Color.Transparent,
                        unfocusedIndicatorColor = Color.Transparent,
                    ),
                    modifier = Modifier.fillMaxWidth().focusRequester(focus),
                )
                if (note != null) {
                    Spacer(Modifier.height(8.dp))
                    Text(note, fontSize = 12.sp)
                }
            }
        },
        dismissButton = {
            androidx.compose.foundation.layout.Row {
                if (removable) TextButton(onClick = { done(TextResult.Remove) }) { Text("Remove") }
                TextButton(onClick = { done(null) }) { Text("Cancel") }
            }
        },
        confirmButton = { Button(onClick = { done(TextResult.Save(text)) }) { Text("Save") } },
    )
}
