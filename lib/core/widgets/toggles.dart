import 'package:flutter/material.dart';

import '../theme/motion.dart';

/// A tappable surface whose corners spring between shapes as Material 3
/// Expressive's buttons do: [shape] gives the corners for the pressed state
/// and the caller's own state (checked…). Only this button rebuilds while
/// it springs.
class ShapeButton extends StatefulWidget {
  const ShapeButton({
    super.key,
    required this.shape,
    required this.color,
    required this.onTap,
    required this.child,
  });
  final BorderRadius Function(bool pressed) shape;
  final Color color;
  final VoidCallback? onTap;
  final Widget child;

  @override
  State<ShapeButton> createState() => _ShapeButtonState();
}

class _ShapeButtonState extends State<ShapeButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<BorderRadius?>(
      tween: BorderRadiusTween(end: widget.shape(_pressed)),
      duration: Motion.fastSpatial.duration,
      curve: Motion.fastSpatial,
      builder: (context, radius, child) => TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: widget.color),
        duration: Motion.defaultEffects.duration,
        curve: Motion.defaultEffects,
        builder: (context, color, child) => Material(
          color: color,
          // The spring overshoots a little (under 10% of the change), so
          // corners stay positive between the shapes used here.
          shape: RoundedRectangleBorder(borderRadius: radius!),
          clipBehavior: Clip.antiAlias,
          animationDuration: Duration.zero,
          child: child,
        ),
        child: child,
      ),
      child: InkWell(
        onTap: widget.onTap,
        onHighlightChanged: (v) => setState(() => _pressed = v),
        child: widget.child,
      ),
    );
  }
}

/// Material 3 Expressive's toggle button (Join, Follow): round when off,
/// squarer (12) when on, tighter (8) while pressed; it reads as on/off.
/// [tonal]: the filled tonal variant.
class ToggleButton extends StatelessWidget {
  const ToggleButton({
    super.key,
    required this.checked,
    required this.onChanged,
    required this.child,
    this.tonal = false,
  });
  final bool checked;
  final ValueChanged<bool>? onChanged;
  final Widget child;
  final bool tonal;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = onChanged != null;
    final Color bg, fg;
    if (!enabled) {
      bg = cs.onSurface.withValues(alpha: 0.1);
      fg = cs.onSurface.withValues(alpha: 0.38);
    } else if (tonal) {
      bg = checked ? cs.secondary : cs.secondaryContainer;
      fg = checked ? cs.onSecondary : cs.onSecondaryContainer;
    } else {
      bg = checked ? cs.primary : cs.surfaceContainer;
      fg = checked ? cs.onPrimary : cs.onSurfaceVariant;
    }
    return Semantics(
      container: true,
      toggled: checked,
      button: true,
      enabled: enabled,
      child: ShapeButton(
        color: bg,
        shape: (pressed) =>
            BorderRadius.circular(pressed ? 8 : (checked ? 12 : 20)),
        onTap: enabled ? () => onChanged!(!checked) : null,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          child: DefaultTextStyle.merge(
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: fg, fontWeight: FontWeight.w500),
            child: IconTheme.merge(
                data: IconThemeData(color: fg, size: 18), child: child),
          ),
        ),
      ),
    );
  }
}

/// An on/off icon (save, favourite…) as a real Material 3 toggle: screen
/// readers hear its state, and its shape changes with it (round → squarer
/// when on). [tonal]: on a filled tonal container, for filters.
class ToggleIcon extends StatelessWidget {
  const ToggleIcon({
    super.key,
    required this.checked,
    required this.onChanged,
    required this.on,
    required this.off,
    required this.description,
    this.tonal = false,
    this.size = 40,
  });
  final bool checked;
  final ValueChanged<bool> onChanged;
  final IconData on;
  final IconData off;
  final String description;
  final bool tonal;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final Color bg, fg;
    if (tonal) {
      bg = checked ? cs.secondaryContainer : cs.surfaceContainerHighest;
      fg = checked ? cs.onSecondaryContainer : cs.onSurfaceVariant;
    } else {
      bg = cs.primary.withValues(alpha: 0);
      fg = checked ? cs.primary : cs.onSurfaceVariant;
    }
    return Semantics(
      container: true,
      toggled: checked,
      button: true,
      label: description,
      child: Tooltip(
        message: description,
        excludeFromSemantics: true,
        child: Padding(
          // 48 to tap, as an IconButton.
          padding: EdgeInsets.all((48 - size).clamp(0.0, 8.0) / 2),
          child: ShapeButton(
            color: bg,
            shape: (pressed) => BorderRadius.circular(
                pressed ? 8 : (checked ? 12 : size / 2)),
            onTap: () => onChanged(!checked),
            child: SizedBox.square(
              dimension: size,
              child: Icon(checked ? on : off, color: fg, size: 24),
            ),
          ),
        ),
      ),
    );
  }
}
