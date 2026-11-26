@file:OptIn(androidx.compose.material3.ExperimentalMaterial3ExpressiveApi::class)

package com.bennybar.luli_for_reddit.feature.settings

import com.bennybar.luli_for_reddit.feature.feed.MenuGroup
import com.bennybar.luli_for_reddit.ui.switchThumb
import com.bennybar.luli_for_reddit.ui.subredditName
import androidx.compose.material3.ButtonDefaults
import androidx.compose.ui.semantics.Role
import androidx.compose.foundation.selection.toggleable
import com.bennybar.luli_for_reddit.app
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.ui.Alignment
import androidx.compose.foundation.layout.Row
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
import androidx.compose.material.icons.rounded.Visibility
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
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
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.material3.FilterChip
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
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
    leading: (@Composable () -> Unit)? = null,
) {
    ListItem(
        modifier = Modifier
            .then(if (onClick != null) Modifier.clickable(enabled = enabled, onClick = onClick) else Modifier)
            .alpha(if (enabled) 1f else 0.38f),
        colors = clearItem,
        leadingContent = when {
            leading != null -> leading
            icon != null -> ({ Icon(icon, null, tint = iconTint ?: MaterialTheme.colorScheme.onSurfaceVariant) })
            leadingSpacer -> ({ Spacer(Modifier.size(24.dp)) })
            else -> null
        },
        content = { Text(title, color = titleColor ?: Color.Unspecified) },
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
        // The whole row is the switch (screen readers hear "on / off").
        modifier = Modifier
            .toggleable(value = checked, enabled = enabled, role = Role.Switch) { onChange?.invoke(it) }
            .alpha(if (enabled) 1f else 0.38f),
        colors = clearItem,
        leadingContent = icon?.let { { Icon(it, null, tint = accent ?: MaterialTheme.colorScheme.onSurfaceVariant) } },
        content = { Text(title, color = accent ?: Color.Unspecified, fontWeight = titleWeight) },
        supportingContent = subtitle?.let { { Text(it, color = accent ?: Color.Unspecified) } },
        trailingContent = {
            Switch(
                checked = checked,
                onCheckedChange = null, // the row handles it
                thumbContent = switchThumb(checked),
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
 * A single-choice sheet, as every menu (#181): the options in one group, the current one a
 * tinted pill with a check, each with its icon when it has one. Null when dismissed.
 */
internal suspend fun <T> pickOption(options: List<PickOption<T>>, current: T?): T? =
    Overlays.show<PickOption<T>> { done ->
        OverlaySheet<PickOption<T>>(done) { close ->
            MenuGroup {
                for (o in options) item(o.label, o.icon, o.subtitle, selected = o.value == current) { close(o) }
            }
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
        dismissButton = { TextButton(onClick = { done(false) }, shapes = ButtonDefaults.shapes()) { Text(cancel) } },
        confirmButton = { Button(onClick = { done(true) }, shapes = ButtonDefaults.shapes()) { Text(confirm) } },
    )
} == true

/** An info dialog with a single [close] button. */
internal suspend fun infoDialog(title: String, text: String, close: String = "Close") {
    Overlays.show<Unit> { done ->
        AlertDialog(
            onDismissRequest = { done(null) },
            title = { Text(title) },
            text = { Column(Modifier.verticalScroll(rememberScrollState())) { Text(text) } },
            confirmButton = { TextButton(onClick = { done(null) }, shapes = ButtonDefaults.shapes()) { Text(close) } },
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
                if (removable) TextButton(onClick = { done(TextResult.Remove) }, shapes = ButtonDefaults.shapes()) { Text("Remove") }
                TextButton(onClick = { done(null) }, shapes = ButtonDefaults.shapes()) { Text("Cancel") }
            }
        },
        confirmButton = { Button(onClick = { done(TextResult.Save(text)) }, shapes = ButtonDefaults.shapes()) { Text("Save") } },
    )
}

/** The subreddits hidden from the front page ("Hide r/… for 7 days"), each with Unhide. */
internal fun showHiddenSubsDialog() {
    Overlays.launch { done ->
        val subs by app.hiddenHomeSubs.ids.collectAsStateWithLifecycle()
        AlertDialog(
            onDismissRequest = done,
            title = { Text("Hidden subreddits") },
            text = {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    if (subs.isEmpty()) Text("None. Hide one from a post's ⋮ menu or a swipe; it comes back after 7 days.")
                    for (sub in subs.sorted()) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(subredditName(sub), Modifier.weight(1f))
                            TextButton(onClick = { app.hiddenHomeSubs.remove(sub) }, shapes = ButtonDefaults.shapes()) { Text("Unhide") }
                        }
                    }
                }
            },
            confirmButton = { TextButton(onClick = done, shapes = ButtonDefaults.shapes()) { Text("Done") } },
        )
    }
}

/** One choice of an [InlineChoice]: its value, label and optional icon. */
internal class Choice<T>(val value: T, val label: String, val icon: ImageVector? = null)

/**
 * A setting picked right on the page (Appearance, under its pinned preview): segmented
 * buttons for up to four short options, else a scrolling row of chips. Picking doesn't
 * leave the page, so options can be tried one after another while the preview follows.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun <T> InlineChoice(
    title: String,
    icon: ImageVector?,
    choices: List<Choice<T>>,
    selected: T,
    subtitle: String? = null,
    onSelect: (T) -> Unit,
) {
    val cs = MaterialTheme.colorScheme
    Column(Modifier.fillMaxWidth().padding(top = 12.dp, bottom = 12.dp)) {
        Row(Modifier.padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            if (icon != null) {
                Icon(icon, null, tint = cs.onSurfaceVariant)
                Spacer(Modifier.size(16.dp))
            }
            Column {
                Text(title, style = MaterialTheme.typography.bodyLarge)
                if (subtitle != null) Text(subtitle, style = MaterialTheme.typography.bodyMedium, color = cs.onSurfaceVariant)
            }
        }
        Spacer(Modifier.height(10.dp))
        val segmented = choices.size <= 4 && choices.all { it.label.length <= 10 && it.icon == null }
        if (segmented) {
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
                choices.forEachIndexed { i, c ->
                    SegmentedButton(
                        selected = c.value == selected,
                        onClick = { onSelect(c.value) },
                        shape = SegmentedButtonDefaults.itemShape(i, choices.size),
                        // The chosen one in the accent, as the chips below.
                        colors = SegmentedButtonDefaults.colors(activeContainerColor = cs.primary, activeContentColor = cs.onPrimary),
                        modifier = Modifier.semantics { contentDescription = "$title: ${c.label}" },
                    ) { Text(c.label, maxLines = 1) }
                }
            }
        } else {
            LazyRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                contentPadding = PaddingValues(horizontal = 16.dp),
            ) {
                items(choices.size) { i ->
                    val c = choices[i]
                    FilterChip(
                        selected = c.value == selected,
                        onClick = { onSelect(c.value) },
                        label = { Text(c.label, maxLines = 1) },
                        leadingIcon = c.icon?.let { ic -> { Icon(ic, null, Modifier.size(18.dp)) } },
                        colors = androidx.compose.material3.FilterChipDefaults.filterChipColors(
                            selectedContainerColor = cs.primary,
                            selectedLabelColor = cs.onPrimary,
                            selectedLeadingIconColor = cs.onPrimary,
                        ),
                        modifier = Modifier.semantics { contentDescription = "$title: ${c.label}" },
                    )
                }
            }
        }
    }
}

/**
 * A sub-heading on a settings page (Appearance's Text, Posts…), between its row groups.
 * [onPreview]: a small Preview button at its end (Appearance's groups, #288).
 */
@Composable
internal fun SettingsSubheading(text: String, onPreview: (() -> Unit)? = null) {
    Row(
        Modifier.fillMaxWidth().padding(start = 32.dp, top = if (onPreview != null) 6.dp else 16.dp, end = 16.dp, bottom = if (onPreview != null) 0.dp else 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text,
            Modifier.weight(1f),
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        if (onPreview != null) {
            TextButton(onClick = onPreview, contentPadding = PaddingValues(horizontal = 12.dp)) {
                Icon(Icons.Rounded.Visibility, null, Modifier.size(18.dp))
                Text("Preview", Modifier.padding(start = 6.dp))
            }
        }
    }
}
