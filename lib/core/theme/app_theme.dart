import 'package:flutter/material.dart';

/// Upvote / downvote accent colors, exposed as a theme extension so vote
/// controls can read brightness-correct colors.
@immutable
class VoteColors extends ThemeExtension<VoteColors> {
  const VoteColors({required this.up, required this.down});
  final Color up;
  final Color down;

  @override
  VoteColors copyWith({Color? up, Color? down}) =>
      VoteColors(up: up ?? this.up, down: down ?? this.down);

  @override
  VoteColors lerp(ThemeExtension<VoteColors>? other, double t) {
    if (other is! VoteColors) return this;
    return VoteColors(
      up: Color.lerp(up, other.up, t)!,
      down: Color.lerp(down, other.down, t)!,
    );
  }
}

/// Material 3 Expressive theme — the **"Bloom"** variant (calm lavender palette,
/// framed filled cards) paired with the **"Pop"** floating pill navigation
/// (rendered by the home shell). Supports light/dark (device or in-app), an
/// optional custom accent, dynamic (wallpaper) color, and AMOLED black.
class AppTheme {
  AppTheme._();

  /// Bloom primary — also the default accent. When the chosen accent equals
  /// this, the exact Bloom tonal palette is used (rather than a seeded one).
  static const Color seed = Color(0xFF6750A4);

  // ---- Exact Bloom tonal palettes (from the design's token system) ----
  static const ColorScheme bloomLight = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF6750A4),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFEADDFF),
    onPrimaryContainer: Color(0xFF21005D),
    secondary: Color(0xFF625B71),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFE8DEF8),
    onSecondaryContainer: Color(0xFF1D192B),
    tertiary: Color(0xFF7D5260),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFFFD8E4),
    onTertiaryContainer: Color(0xFF31111D),
    error: Color(0xFFB3261E),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFF9DEDC),
    onErrorContainer: Color(0xFF410E0B),
    surface: Color(0xFFFEF7FF),
    onSurface: Color(0xFF1D1B20),
    onSurfaceVariant: Color(0xFF49454F),
    outline: Color(0xFF79747E),
    outlineVariant: Color(0xFFCAC4D0),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF7F2FA),
    surfaceContainer: Color(0xFFF3EDF7),
    surfaceContainerHigh: Color(0xFFECE6F0),
    surfaceContainerHighest: Color(0xFFE6E0E9),
    surfaceDim: Color(0xFFDED8E1),
    surfaceBright: Color(0xFFFEF7FF),
    inverseSurface: Color(0xFF322F35),
    onInverseSurface: Color(0xFFF5EFF7),
    inversePrimary: Color(0xFFD0BCFF),
    scrim: Color(0xFF000000),
    shadow: Color(0xFF000000),
  );

  static const ColorScheme bloomDark = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFD0BCFF),
    onPrimary: Color(0xFF381E72),
    primaryContainer: Color(0xFF4F378B),
    onPrimaryContainer: Color(0xFFEADDFF),
    secondary: Color(0xFFCCC2DC),
    onSecondary: Color(0xFF332D41),
    secondaryContainer: Color(0xFF4A4458),
    onSecondaryContainer: Color(0xFFE8DEF8),
    tertiary: Color(0xFFEFB8C8),
    onTertiary: Color(0xFF492532),
    tertiaryContainer: Color(0xFF633B48),
    onTertiaryContainer: Color(0xFFFFD8E4),
    error: Color(0xFFF2B8B5),
    onError: Color(0xFF601410),
    errorContainer: Color(0xFF8C1D18),
    onErrorContainer: Color(0xFFF9DEDC),
    surface: Color(0xFF141218),
    onSurface: Color(0xFFE6E0E9),
    onSurfaceVariant: Color(0xFFCAC4D0),
    outline: Color(0xFF938F99),
    outlineVariant: Color(0xFF49454F),
    surfaceContainerLowest: Color(0xFF0F0D13),
    surfaceContainerLow: Color(0xFF1D1B20),
    surfaceContainer: Color(0xFF211F26),
    surfaceContainerHigh: Color(0xFF2B2930),
    surfaceContainerHighest: Color(0xFF36343B),
    surfaceDim: Color(0xFF141218),
    surfaceBright: Color(0xFF3B383E),
    inverseSurface: Color(0xFFE6E0E9),
    onInverseSurface: Color(0xFF322F35),
    inversePrimary: Color(0xFF6750A4),
    scrim: Color(0xFF000000),
    shadow: Color(0xFF000000),
  );

  static const _voteLight = VoteColors(up: Color(0xFFD93900), down: Color(0xFF605BFF));
  static const _voteDark = VoteColors(up: Color(0xFFFF7E54), down: Color(0xFFBFC0FF));

  static ColorScheme _baseScheme(
      ColorScheme? dynamicScheme, Color seed, Brightness brightness) {
    if (dynamicScheme != null) return dynamicScheme;
    if (seed.toARGB32() == AppTheme.seed.toARGB32()) {
      return brightness == Brightness.light ? bloomLight : bloomDark;
    }
    return ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
  }

  static ThemeData light(ColorScheme? dynamicScheme, {Color seed = AppTheme.seed}) =>
      _build(_baseScheme(dynamicScheme, seed, Brightness.light), Brightness.light);

  static ThemeData dark(
    ColorScheme? dynamicScheme, {
    Color seed = AppTheme.seed,
    bool amoled = false,
  }) {
    var scheme = _baseScheme(dynamicScheme, seed, Brightness.dark);
    if (amoled) {
      // True-black background (great for OLED) with slightly lifted containers
      // so cards/nav stay legible against the black.
      scheme = scheme.copyWith(
        surface: Colors.black,
        surfaceDim: Colors.black,
        surfaceContainerLowest: Colors.black,
        surfaceContainerLow: const Color(0xFF121214),
        surfaceContainer: const Color(0xFF161618),
        surfaceContainerHigh: const Color(0xFF1D1D20),
        surfaceContainerHighest: const Color(0xFF242428),
      );
    }
    return _build(scheme, Brightness.dark);
  }

  static ThemeData _build(ColorScheme scheme, Brightness brightness) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      scaffoldBackgroundColor: scheme.surface,
      extensions: [brightness == Brightness.light ? _voteLight : _voteDark],
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: false,
        elevation: 0,
        titleTextStyle: base.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
      // Bloom: framed, filled cards (surfaceContainerLow), large 28px radius.
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(28)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        indicatorColor: scheme.secondaryContainer,
        elevation: 0,
        height: 72,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        indicatorShape: const StadiumBorder(),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 52),
          shape: const StadiumBorder(),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: const StadiumBorder(),
        side: BorderSide.none,
        backgroundColor: scheme.surfaceContainerHigh,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        elevation: 2,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.5),
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
