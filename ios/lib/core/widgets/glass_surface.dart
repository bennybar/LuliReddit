import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';

/// True when the platform should use the iOS 26 "Liquid Glass" treatment.
bool get useLiquidGlass => Platform.isIOS;

/// A translucent, blurred "liquid glass" surface for chrome (nav bar, search
/// pill, sheets) on iOS. On other platforms it renders a solid Material using
/// [fallbackColor] so the Material 3 "Bloom" look is preserved.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    required this.borderRadius,
    this.fallbackColor,
    this.blur = 24,
    this.tintOpacity,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final Color? fallbackColor;
  final double blur;

  /// Tint opacity override (1.0 = opaque). Higher = more readable over busy
  /// content, less see-through. Defaults to a frosted ~0.7/0.82.
  final double? tintOpacity;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    if (!useLiquidGlass) {
      return Material(
        color: fallbackColor ?? cs.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: borderRadius),
        clipBehavior: Clip.antiAlias,
        child: child,
      );
    }

    // The tint (this is what controls see-through). NOTE: BoxDecoration ignores
    // `color` when a `gradient` is set, so the tint must live in the gradient.
    final tint =
        cs.surface.withValues(alpha: tintOpacity ?? (dark ? 0.7 : 0.82));
    // Soft specular sheen at the top, painted *over* the tint.
    final sheenTop =
        Color.alphaBlend(Colors.white.withValues(alpha: dark ? 0.10 : 0.22), tint);

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            border: Border.all(
              color: Colors.white.withValues(alpha: dark ? 0.14 : 0.55),
              width: 1,
            ),
            // Gradient carries BOTH the tint and the sheen (opaque at the
            // configured tintOpacity; 1.0 = fully solid like Telegram).
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [sheenTop, tint],
            ),
          ),
          // InkWell children need a Material ancestor for ripples.
          child: Material(type: MaterialType.transparency, child: child),
        ),
      ),
    );
  }
}
