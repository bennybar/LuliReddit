package com.bennybar.luli_for_reddit.feature.settings

import android.app.WallpaperManager
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.ArrowUpward
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Colorize
import androidx.compose.material.icons.rounded.DarkMode
import androidx.compose.material.icons.rounded.Wallpaper
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.nav.LocalNavigator
import com.bennybar.luli_for_reddit.settings.PaletteStyle
import com.bennybar.luli_for_reddit.settings.Settings
import com.bennybar.luli_for_reddit.settings.ThemeMode
import com.bennybar.luli_for_reddit.ui.theme.AppTheme
import com.bennybar.luli_for_reddit.ui.theme.isAppInDarkTheme
import kotlinx.coroutines.launch

/** The accent presets: Bloom lavender (the default) first. */
internal val ACCENT_SWATCHES = listOf(
    0xFF6750A4L, // Bloom lavender (default)
    0xFFEA4335L, // red
    0xFFFF7043L, // orange
    0xFFFFB300L, // amber
    0xFF34A853L, // green
    0xFF00897BL, // teal
    0xFF1E88E5L, // blue
    0xFF8E24AAL, // purple
    0xFFD81B60L, // pink
)

/** Settings → Theme & colours (#114): light or dark, the accent, the palette style, with a live preview. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ThemeColorsScreen() {
    val nav = LocalNavigator.current
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Theme & colours") },
                navigationIcon = { IconButton(onClick = { nav.pop() }) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Back") } },
            )
        },
    ) { padding ->
        LazyColumn(
            Modifier.fillMaxSize(),
            contentPadding = PaddingValues(top = padding.calculateTopPadding(), bottom = padding.calculateBottomPadding() + 24.dp),
        ) {
            item("content") { ThemeColorsContent() }
        }
    }
}

/** The page's controls, also the setup's Look step. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ThemeColorsContent() {
    val s by app.settings.state.collectAsStateWithLifecycle()
    val ctrl = app.settings
    val cs = MaterialTheme.colorScheme
    val dark = isAppInDarkTheme(s)
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    // The wallpaper's main colour, for the style previews when its colours are on.
    val wallpaper = remember {
        runCatching { WallpaperManager.getInstance(context).getWallpaperColors(WallpaperManager.FLAG_SYSTEM)?.primaryColor?.toArgb() }.getOrNull()
    }
    val seed = if (s.useDynamicColor && wallpaper != null) wallpaper.toLong() and 0xFFFFFFFFL else s.seedColor

    Column(Modifier.padding(horizontal = 16.dp)) {
        ThemePreview()

        Heading("Mode")
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
            val modes = listOf(ThemeMode.SYSTEM to "System", ThemeMode.LIGHT to "Light", ThemeMode.DARK to "Dark")
            modes.forEachIndexed { i, (mode, label) ->
                SegmentedButton(
                    selected = s.themeMode == mode,
                    onClick = { ctrl.setThemeMode(mode) },
                    shape = SegmentedButtonDefaults.itemShape(i, modes.size),
                ) { Text(label) }
            }
        }
        SwitchTile("AMOLED black", "Pure black surfaces in dark mode", Icons.Rounded.DarkMode, s.amoled, onChange = ctrl::setAmoled)

        Heading("Colour")
        SwitchTile("Wallpaper colours", "Take the colours from your wallpaper", Icons.Rounded.Wallpaper, s.useDynamicColor, onChange = ctrl::setUseDynamicColor)
        if (!s.useDynamicColor) {
            FlowRow(
                Modifier.fillMaxWidth().padding(top = 4.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                for (c in ACCENT_SWATCHES) {
                    SchemeSwatch(c, dark, s.paletteStyle, selected = s.seedColor == c) { ctrl.setSeedColor(c) }
                }
                // Any colour (#84): the last one picked, or a colour wheel until there is one.
                val custom = s.customSeedColor ?: s.seedColor.takeIf { it !in ACCENT_SWATCHES }
                val customSelected = s.seedColor !in ACCENT_SWATCHES
                val pick: () -> Unit = { scope.launch { pickCustomColor(custom ?: s.seedColor)?.let(ctrl::setCustomSeedColor) } }
                if (custom != null) {
                    Box(contentAlignment = Alignment.Center) {
                        SchemeSwatch(custom, dark, s.paletteStyle, selected = customSelected, onClick = pick)
                        if (!customSelected) Icon(Icons.Rounded.Colorize, "Custom colour", tint = Color.White)
                    }
                } else {
                    Box(
                        Modifier.size(56.dp).background(cs.surfaceContainerHighest, CircleShape).clickable(onClick = pick),
                        contentAlignment = Alignment.Center,
                    ) { Icon(Icons.Rounded.Colorize, "Custom colour") }
                }
            }
            HexField(s.seedColor) { ctrl.setCustomSeedColor(it) }
        }

        Heading("Palette style")
        Text(
            "How the colour spreads through the app, as in Android's own wallpaper styles.",
            style = MaterialTheme.typography.bodySmall,
            color = cs.onSurfaceVariant,
        )
        Spacer(Modifier.height(10.dp))
        LazyRow(horizontalArrangement = Arrangement.spacedBy(14.dp), contentPadding = PaddingValues(bottom = 8.dp)) {
            items(PaletteStyle.entries) { style ->
                Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.width(72.dp)) {
                    SchemeSwatch(seed, dark, style, selected = s.paletteStyle == style) { ctrl.setPaletteStyle(style) }
                    Spacer(Modifier.height(6.dp))
                    Text(style.label, style = MaterialTheme.typography.labelMedium, maxLines = 1)
                }
            }
        }
    }
}

@Composable
private fun Heading(text: String) {
    Text(
        text,
        Modifier.padding(top = 22.dp, bottom = 8.dp),
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.primary,
    )
}

/**
 * A colour as the scheme it makes, like Android's wallpaper styles: the top half its
 * primary, the bottom halves its secondary and tertiary. Ringed when it's the one in use.
 */
@Composable
private fun SchemeSwatch(seed: Long, dark: Boolean, style: PaletteStyle, selected: Boolean, size: Dp = 56.dp, onClick: () -> Unit) {
    val scheme = remember(seed, dark, style) { AppTheme.fromSeed(Color(seed.toInt()), dark, style) }
    val ring = MaterialTheme.colorScheme.onSurface
    Box(
        Modifier
            .size(size)
            .border(BorderStroke(if (selected) 3.dp else 0.dp, if (selected) ring else Color.Transparent), CircleShape)
            .padding(if (selected) 5.dp else 0.dp)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Canvas(Modifier.fillMaxSize()) {
            val r = this.size.minDimension / 2
            drawCircle(scheme.surfaceContainerHigh, r)
            drawArc(scheme.primary, 180f, 180f, true, Offset.Zero, Size(r * 2, r * 2))
            drawArc(scheme.secondary, 90f, 90f, true, Offset.Zero, Size(r * 2, r * 2))
            drawArc(scheme.tertiary, 0f, 90f, true, Offset.Zero, Size(r * 2, r * 2))
        }
        if (selected) Icon(Icons.Rounded.Check, null, tint = if (scheme.primary.luminance() > 0.5f) Color.Black else Color.White)
    }
}

/** Type a colour as #RRGGBB (#114); a full, valid one is applied at once. */
@Composable
private fun HexField(seed: Long, onColor: (Long) -> Unit) {
    fun hexOf(c: Long) = "#%06X".format(c and 0xFFFFFF)
    var text by remember { mutableStateOf(hexOf(seed)) }
    // Follow a swatch picked above, unless the field already says that colour.
    LaunchedEffect(seed) { if (parseHex(text) != seed) text = hexOf(seed) }
    OutlinedTextField(
        value = text,
        onValueChange = { v ->
            text = v.take(7)
            parseHex(text)?.let { if (it != seed) onColor(it) }
        },
        label = { Text("Hex colour") },
        singleLine = true,
        isError = text.length == 7 && parseHex(text) == null,
        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters),
        modifier = Modifier.fillMaxWidth().padding(top = 14.dp),
        shape = RoundedCornerShape(18.dp),
    )
}

/** "#RRGGBB" (or without the #) as an opaque ARGB colour; null unless it's exactly that. */
internal fun parseHex(text: String): Long? {
    val h = text.trim().removePrefix("#")
    if (h.length != 6 || !h.all { it.isDigit() || it.lowercaseChar() in 'a'..'f' }) return null
    return 0xFF000000L or h.toLong(16)
}

/** A small post in the colours being picked, so a choice shows before it's made elsewhere. */
@Composable
private fun ThemePreview() {
    val cs = MaterialTheme.colorScheme
    Column(
        Modifier
            .fillMaxWidth()
            .padding(top = 8.dp)
            .background(cs.surfaceContainerLow, RoundedCornerShape(28.dp))
            .padding(16.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(32.dp).background(cs.primaryContainer, CircleShape), contentAlignment = Alignment.Center) {
                Text("r", color = cs.onPrimaryContainer, fontWeight = FontWeight.Bold)
            }
            Spacer(Modifier.width(10.dp))
            Column {
                Text("r/earthporn", style = MaterialTheme.typography.labelLarge)
                Text("5h", style = MaterialTheme.typography.labelSmall, color = cs.onSurfaceVariant)
            }
            Spacer(Modifier.weight(1f))
            Text(
                "OC",
                Modifier.background(cs.tertiaryContainer, RoundedCornerShape(8.dp)).padding(horizontal = 8.dp, vertical = 2.dp),
                color = cs.onTertiaryContainer,
                fontSize = 12.sp,
            )
        }
        Spacer(Modifier.height(10.dp))
        Text("Morning fog over the lake, after a week of rain", style = MaterialTheme.typography.titleMedium)
        Spacer(Modifier.height(10.dp))
        Box(Modifier.fillMaxWidth().height(72.dp).background(cs.secondaryContainer, RoundedCornerShape(16.dp)))
        Spacer(Modifier.height(12.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Button(onClick = {}, contentPadding = PaddingValues(horizontal = 14.dp)) {
                Icon(Icons.Rounded.ArrowUpward, null, Modifier.size(18.dp))
                Spacer(Modifier.width(4.dp))
                Text("4.2k")
            }
            FilledTonalButton(onClick = {}) { Text("Comments") }
        }
    }
}

/** "Follow system · Lavender · Tonal spot": the Settings row's summary. */
internal fun themeSummary(s: Settings): String {
    val mode = when (s.themeMode) {
        ThemeMode.SYSTEM -> "Follow system"
        ThemeMode.LIGHT -> "Light"
        ThemeMode.DARK -> "Dark"
    }
    val colour = if (s.useDynamicColor) "Wallpaper colours" else "#%06X".format(s.seedColor and 0xFFFFFF)
    return "$mode · $colour · ${s.paletteStyle.label}"
}
