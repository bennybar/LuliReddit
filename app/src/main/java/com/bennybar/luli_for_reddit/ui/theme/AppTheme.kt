package com.bennybar.luli_for_reddit.ui.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.MaterialExpressiveTheme
import androidx.compose.material3.MotionScheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.ExperimentalTextApi
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bennybar.luli_for_reddit.R
import com.bennybar.luli_for_reddit.settings.AppFont
import com.bennybar.luli_for_reddit.settings.Settings
import com.bennybar.luli_for_reddit.settings.ThemeMode
import com.materialkolor.hct.Hct
import com.materialkolor.scheme.DynamicScheme
import com.materialkolor.scheme.SchemeTonalSpot

/** Upvote / downvote accent colors, brightness-correct. */
@Immutable
data class VoteColors(val up: Color, val down: Color)

val LocalVoteColors = staticCompositionLocalOf { AppTheme.voteLight }

/**
 * Material 3 Expressive theme — the **"Bloom"** variant (calm lavender
 * palette, framed filled cards) paired with the **"Pop"** floating pill
 * navigation (drawn by the home shell). Supports light/dark (device or
 * in-app), a custom accent, dynamic (wallpaper) color and AMOLED black.
 */
object AppTheme {
    /** Bloom primary — the default accent. */
    val seed = Color(0xFF6750A4)

    val bloomLight = lightColorScheme(
        primary = Color(0xFF6750A4), onPrimary = Color(0xFFFFFFFF),
        primaryContainer = Color(0xFFEADDFF), onPrimaryContainer = Color(0xFF21005D),
        secondary = Color(0xFF625B71), onSecondary = Color(0xFFFFFFFF),
        secondaryContainer = Color(0xFFE8DEF8), onSecondaryContainer = Color(0xFF1D192B),
        tertiary = Color(0xFF7D5260), onTertiary = Color(0xFFFFFFFF),
        tertiaryContainer = Color(0xFFFFD8E4), onTertiaryContainer = Color(0xFF31111D),
        error = Color(0xFFB3261E), onError = Color(0xFFFFFFFF),
        errorContainer = Color(0xFFF9DEDC), onErrorContainer = Color(0xFF410E0B),
        background = Color(0xFFFEF7FF), onBackground = Color(0xFF1D1B20),
        surface = Color(0xFFFEF7FF), onSurface = Color(0xFF1D1B20),
        surfaceVariant = Color(0xFFE7E0EC), onSurfaceVariant = Color(0xFF49454F),
        outline = Color(0xFF79747E), outlineVariant = Color(0xFFCAC4D0),
        surfaceContainerLowest = Color(0xFFFFFFFF), surfaceContainerLow = Color(0xFFF7F2FA),
        surfaceContainer = Color(0xFFF3EDF7), surfaceContainerHigh = Color(0xFFECE6F0),
        surfaceContainerHighest = Color(0xFFE6E0E9), surfaceDim = Color(0xFFDED8E1),
        surfaceBright = Color(0xFFFEF7FF), inverseSurface = Color(0xFF322F35),
        inverseOnSurface = Color(0xFFF5EFF7), inversePrimary = Color(0xFFD0BCFF),
        scrim = Color(0xFF000000), surfaceTint = Color(0xFF6750A4),
    )

    val bloomDark = darkColorScheme(
        primary = Color(0xFFD0BCFF), onPrimary = Color(0xFF381E72),
        primaryContainer = Color(0xFF4F378B), onPrimaryContainer = Color(0xFFEADDFF),
        secondary = Color(0xFFCCC2DC), onSecondary = Color(0xFF332D41),
        secondaryContainer = Color(0xFF4A4458), onSecondaryContainer = Color(0xFFE8DEF8),
        tertiary = Color(0xFFEFB8C8), onTertiary = Color(0xFF492532),
        tertiaryContainer = Color(0xFF633B48), onTertiaryContainer = Color(0xFFFFD8E4),
        error = Color(0xFFF2B8B5), onError = Color(0xFF601410),
        errorContainer = Color(0xFF8C1D18), onErrorContainer = Color(0xFFF9DEDC),
        background = Color(0xFF141218), onBackground = Color(0xFFE6E0E9),
        surface = Color(0xFF141218), onSurface = Color(0xFFE6E0E9),
        surfaceVariant = Color(0xFF49454F), onSurfaceVariant = Color(0xFFCAC4D0),
        outline = Color(0xFF938F99), outlineVariant = Color(0xFF49454F),
        surfaceContainerLowest = Color(0xFF0F0D13), surfaceContainerLow = Color(0xFF1D1B20),
        surfaceContainer = Color(0xFF211F26), surfaceContainerHigh = Color(0xFF2B2930),
        surfaceContainerHighest = Color(0xFF36343B), surfaceDim = Color(0xFF141218),
        surfaceBright = Color(0xFF3B383E), inverseSurface = Color(0xFFE6E0E9),
        inverseOnSurface = Color(0xFF322F35), inversePrimary = Color(0xFF6750A4),
        scrim = Color(0xFF000000), surfaceTint = Color(0xFFD0BCFF),
    )

    val voteLight = VoteColors(up = Color(0xFFD93900), down = Color(0xFF605BFF))
    val voteDark = VoteColors(up = Color(0xFFFF7E54), down = Color(0xFFBFC0FF))

    /** Flutter's ColorScheme.fromSeed: Material's tonal-spot scheme. */
    fun fromSeed(seed: Color, dark: Boolean): ColorScheme {
        val s: DynamicScheme = SchemeTonalSpot(Hct.fromInt(seed.toArgbInt()), dark, 0.0)
        fun c(argb: Int) = Color(argb)
        val base = if (dark) darkColorScheme() else lightColorScheme()
        return base.copy(
            primary = c(s.primary), onPrimary = c(s.onPrimary),
            primaryContainer = c(s.primaryContainer), onPrimaryContainer = c(s.onPrimaryContainer),
            secondary = c(s.secondary), onSecondary = c(s.onSecondary),
            secondaryContainer = c(s.secondaryContainer), onSecondaryContainer = c(s.onSecondaryContainer),
            tertiary = c(s.tertiary), onTertiary = c(s.onTertiary),
            tertiaryContainer = c(s.tertiaryContainer), onTertiaryContainer = c(s.onTertiaryContainer),
            error = c(s.error), onError = c(s.onError),
            errorContainer = c(s.errorContainer), onErrorContainer = c(s.onErrorContainer),
            background = c(s.background), onBackground = c(s.onBackground),
            surface = c(s.surface), onSurface = c(s.onSurface),
            surfaceVariant = c(s.surfaceVariant), onSurfaceVariant = c(s.onSurfaceVariant),
            outline = c(s.outline), outlineVariant = c(s.outlineVariant),
            surfaceContainerLowest = c(s.surfaceContainerLowest), surfaceContainerLow = c(s.surfaceContainerLow),
            surfaceContainer = c(s.surfaceContainer), surfaceContainerHigh = c(s.surfaceContainerHigh),
            surfaceContainerHighest = c(s.surfaceContainerHighest), surfaceDim = c(s.surfaceDim),
            surfaceBright = c(s.surfaceBright), inverseSurface = c(s.inverseSurface),
            inverseOnSurface = c(s.inverseOnSurface), inversePrimary = c(s.inversePrimary),
            scrim = c(s.scrim), surfaceTint = c(s.primary),
        )
    }

    private fun Color.toArgbInt(): Int =
        ((alpha * 255).toInt() shl 24) or ((red * 255).toInt() shl 16) or ((green * 255).toInt() shl 8) or (blue * 255).toInt()

    val jakarta = FontFamily(
        Font(R.font.plus_jakarta_sans_400, FontWeight.Normal),
        Font(R.font.plus_jakarta_sans_500, FontWeight.Medium),
        Font(R.font.plus_jakarta_sans_600, FontWeight.SemiBold),
        Font(R.font.plus_jakarta_sans_700, FontWeight.Bold),
    )
    val unbounded = FontFamily(
        Font(R.font.unbounded_600, FontWeight.SemiBold),
        Font(R.font.unbounded_700, FontWeight.Bold),
    )

    /**
     * Optional bundled font: Plus Jakarta Sans for text, Unbounded for
     * display/headline. Unbounded runs wide, so those sizes step down a little.
     */
    /** Google Sans (OFL), one variable file subset to Latin/Greek/Cyrillic/Hebrew; weight axis 400–700. */
    @OptIn(ExperimentalTextApi::class)
    val googleSans = FontFamily(
        listOf(FontWeight.Normal, FontWeight.Medium, FontWeight.SemiBold, FontWeight.Bold).map { w ->
            Font(R.font.google_sans, w, variationSettings = FontVariation.Settings(FontVariation.weight(w.weight)))
        },
    )

    fun typography(font: AppFont): Typography {
        val t = Typography()
        if (font == AppFont.ROBOTO) return t
        if (font == AppFont.GOOGLE_SANS) {
            // Material's type scale was drawn for Google Sans: keep its sizes and weights.
            fun TextStyle.g() = copy(fontFamily = googleSans)
            return t.copy(
                displayLarge = t.displayLarge.g(), displayMedium = t.displayMedium.g(), displaySmall = t.displaySmall.g(),
                headlineLarge = t.headlineLarge.g(), headlineMedium = t.headlineMedium.g(), headlineSmall = t.headlineSmall.g(),
                titleLarge = t.titleLarge.g(), titleMedium = t.titleMedium.g(), titleSmall = t.titleSmall.g(),
                bodyLarge = t.bodyLarge.g(), bodyMedium = t.bodyMedium.g(), bodySmall = t.bodySmall.g(),
                labelLarge = t.labelLarge.g(), labelMedium = t.labelMedium.g(), labelSmall = t.labelSmall.g(),
            )
        }
        fun TextStyle.j() = copy(fontFamily = jakarta)
        fun wide(s: TextStyle, w: FontWeight, size: Int, height: Int) =
            s.copy(fontFamily = unbounded, fontWeight = w, fontSize = size.sp, lineHeight = height.sp)
        return t.copy(
            displayLarge = wide(t.displayLarge, FontWeight.Bold, 52, 56),
            displayMedium = wide(t.displayMedium, FontWeight.Bold, 40, 46),
            displaySmall = wide(t.displaySmall, FontWeight.Bold, 32, 38),
            headlineLarge = wide(t.headlineLarge, FontWeight.SemiBold, 26, 32),
            headlineMedium = wide(t.headlineMedium, FontWeight.SemiBold, 22, 28),
            headlineSmall = wide(t.headlineSmall, FontWeight.SemiBold, 19, 26),
            titleLarge = t.titleLarge.j(), titleMedium = t.titleMedium.j(), titleSmall = t.titleSmall.j(),
            bodyLarge = t.bodyLarge.j(), bodyMedium = t.bodyMedium.j(), bodySmall = t.bodySmall.j(),
            labelLarge = t.labelLarge.j(), labelMedium = t.labelMedium.j(), labelSmall = t.labelSmall.j(),
        )
    }

    /** Bloom: cards radius 28; chips/buttons are stadiums (set per component). */
    val shapes = Shapes(
        extraSmall = RoundedCornerShape(8.dp),
        small = RoundedCornerShape(12.dp),
        medium = RoundedCornerShape(16.dp),
        large = RoundedCornerShape(20.dp),
        extraLarge = RoundedCornerShape(28.dp),
    )
}

/** Resolves the effective color scheme for [settings]. */
@Composable
fun rememberColorScheme(settings: Settings, dark: Boolean): ColorScheme {
    val context = LocalContext.current
    return remember(settings.useDynamicColor, settings.seedColor, settings.amoled, dark) {
        var scheme = when {
            settings.useDynamicColor && Build.VERSION.SDK_INT >= 31 ->
                if (dark) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
            settings.seedColor == Settings.DEFAULT_SEED -> if (dark) AppTheme.bloomDark else AppTheme.bloomLight
            else -> AppTheme.fromSeed(Color(settings.seedColor.toInt()), dark)
        }
        if (dark && settings.amoled) {
            // True-black background with slightly lifted containers so
            // cards/nav stay legible against the black.
            scheme = scheme.copy(
                background = Color.Black,
                surface = Color.Black,
                surfaceDim = Color.Black,
                surfaceContainerLowest = Color.Black,
                surfaceContainerLow = Color(0xFF121214),
                surfaceContainer = Color(0xFF161618),
                surfaceContainerHigh = Color(0xFF1D1D20),
                surfaceContainerHighest = Color(0xFF242428),
            )
        }
        scheme
    }
}

@Composable
fun isAppInDarkTheme(settings: Settings): Boolean = when (settings.themeMode) {
    ThemeMode.SYSTEM -> isSystemInDarkTheme()
    ThemeMode.LIGHT -> false
    ThemeMode.DARK -> true
}

/**
 * The app theme. Also applies the global text-size setting, which (as in the
 * Flutter build) replaces the system font scale.
 */
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun IlayTheme(settings: Settings, content: @Composable () -> Unit) {
    val dark = isAppInDarkTheme(settings)
    val scheme = rememberColorScheme(settings, dark)
    val density = LocalDensity.current
    MaterialExpressiveTheme(
        colorScheme = scheme,
        typography = remember(settings.appFont) { AppTheme.typography(settings.appFont) },
        shapes = AppTheme.shapes,
        motionScheme = MotionScheme.expressive(),
    ) {
        CompositionLocalProvider(
            LocalVoteColors provides if (dark) AppTheme.voteDark else AppTheme.voteLight,
            LocalDensity provides Density(density.density, settings.textScale.toFloat()),
            content = content,
        )
    }
}
