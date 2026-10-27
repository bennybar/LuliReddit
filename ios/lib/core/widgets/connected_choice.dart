import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';

import 'toggles.dart';

/// The gap between connected buttons (M3 Expressive's ConnectedSpaceBetween).
const double connectedGap = 2;

/// M3 Expressive's connected button corners for item [i] of [count]: round
/// ends, tight ([inner], 8; 4 while pressed) inner corners. [height]: the
/// button's height.
BorderRadiusDirectional connectedRadius(int i, int count,
    {double height = 40, double inner = 8}) {
  final round = Radius.circular(height / 2);
  final tight = Radius.circular(inner);
  return BorderRadiusDirectional.horizontal(
    start: i == 0 ? round : tight,
    end: i == count - 1 ? round : tight,
  );
}

/// A pick-one choice as a Material 3 Expressive connected button group.
/// [fill]: the buttons share the width equally; otherwise they size to their
/// labels (put it in a sideways-scrolling row for longer lists). [icon]: an
/// icon per option; with [iconOnly] the label is only its description.
/// Screen readers hear a radio group.
class ConnectedChoice<K> extends StatelessWidget {
  const ConnectedChoice({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelect,
    this.fill = true,
    this.icon,
    this.iconOnly = false,
  });
  final List<(K, String)> options;
  final K selected;
  final ValueChanged<K> onSelect;
  final bool fill;
  final IconData Function(K)? icon;
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dir = Directionality.of(context);
    const height = 40.0;
    final n = options.length;
    final buttons = <Widget>[];
    for (var i = 0; i < n; i++) {
      final (key, label) = options[i];
      final checked = key == selected;
      final fg = checked ? cs.onPrimary : cs.onSurfaceVariant;
      final ic = icon?.call(key);
      final Widget content;
      if (ic != null && iconOnly) {
        content = Icon(ic, size: 20, color: fg, semanticLabel: label);
      } else {
        final text = Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w500, color: fg));
        content = ic == null
            ? text
            : Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(ic, size: 18, color: fg),
                const SizedBox(width: 8),
                Flexible(child: text),
              ]);
      }
      // The checked button turns fully round, as M3E's toggle does; a
      // pressed one tightens its inner corners.
      final button = Semantics(
        container: true,
        inMutuallyExclusiveGroup: true,
        checked: checked,
        child: ShapeButton(
          color: checked ? cs.primary : cs.surfaceContainer,
          shape: (pressed) => pressed
              ? connectedRadius(i, n, inner: 4).resolve(dir)
              : checked
                  ? BorderRadius.circular(height / 2)
                  : connectedRadius(i, n).resolve(dir),
          onTap: () => onSelect(key),
          child: Container(
            height: height,
            alignment: Alignment.center,
            padding: EdgeInsets.symmetric(horizontal: fill ? 8 : 16),
            child: content,
          ),
        ),
      );
      if (i > 0) buttons.add(const SizedBox(width: connectedGap));
      buttons.add(fill ? Expanded(child: button) : button);
    }
    return Semantics(
      role: SemanticsRole.radioGroup,
      container: true,
      explicitChildNodes: true,
      child: Row(
        mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
        children: buttons,
      ),
    );
  }
}
