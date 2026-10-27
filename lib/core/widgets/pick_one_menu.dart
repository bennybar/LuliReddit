import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';

/// One entry of a Material 3 Expressive menu group. [selected]: the current
/// choice of a pick-one group (a radio); [checked]: an on/off entry.
class MenuOption<T> {
  const MenuOption(this.value, this.label,
      {this.icon, this.selected = false, this.checked});
  final T value;
  final String label;
  final IconData? icon;
  final bool selected;
  final bool? checked;
}

/// A Material 3 Expressive menu group (DropdownMenuGroup) for a
/// [PopupMenuButton]: its own rounded surface, item [index] of [count]
/// groups (2 apart), the selected entry highlighted on a rounded tertiary
/// fill. The app theme makes the popup itself transparent, so groups are
/// all there is to see.
class MenuGroup<T> extends PopupMenuEntry<T> {
  const MenuGroup(this.options, {super.key, this.index = 0, this.count = 1});
  final List<MenuOption<T>> options;
  final int index;
  final int count;

  static const _itemHeight = 48.0;

  @override
  double get height => options.length * _itemHeight + 8 + (index > 0 ? 2 : 0);

  // The popup tints a represented entry; groups mark their selection
  // themselves.
  @override
  bool represents(T? value) => false;

  @override
  State<MenuGroup<T>> createState() => _MenuGroupState<T>();
}

class _MenuGroupState<T> extends State<MenuGroup<T>> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme.labelLarge;
    final n = widget.options.length;
    const large = Radius.circular(16);
    const small = Radius.circular(4);
    final first = widget.index == 0, last = widget.index == widget.count - 1;
    return Padding(
      padding: EdgeInsets.only(top: first ? 0 : 2),
      child: Material(
        color: cs.surfaceContainerLow,
        elevation: 3,
        shadowColor: cs.shadow,
        surfaceTintColor: Colors.transparent,
        borderRadius: BorderRadius.vertical(
            top: first ? large : small, bottom: last ? large : small),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < n; i++)
                _item(context, cs, text, widget.options[i], i, n),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(BuildContext context, ColorScheme cs, TextStyle? text,
      MenuOption<T> o, int i, int n) {
    const r12 = Radius.circular(12);
    const r4 = Radius.circular(4);
    final on = o.selected || o.checked == true;
    final fg = o.selected ? cs.onTertiaryContainer : cs.onSurface;
    final radius = o.selected
        ? const BorderRadius.all(r12)
        : BorderRadius.vertical(
            top: i == 0 ? r12 : r4, bottom: i == n - 1 ? r12 : r4);
    // A pick-one group's entries are radios; on/off ones checkboxes.
    final pickOne = widget.options.any((x) => x.selected);
    return Semantics(
      container: true,
      role: pickOne
          ? SemanticsRole.menuItemRadio
          : o.checked != null
              ? SemanticsRole.menuItemCheckbox
              : SemanticsRole.menuItem,
      inMutuallyExclusiveGroup: pickOne ? true : null,
      checked: pickOne ? o.selected : o.checked,
      child: Material(
        color: o.selected ? cs.tertiaryContainer : Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.pop<T>(context, o.value),
          child: Container(
            constraints:
                const BoxConstraints(minHeight: MenuGroup._itemHeight),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                if (o.icon != null) ...[
                  Icon(o.icon,
                      size: 20,
                      color: o.selected ? fg : cs.onSurfaceVariant),
                  const SizedBox(width: 12),
                ],
                Expanded(
                    child: Text(o.label, style: text?.copyWith(color: fg))),
                if (on) ...[
                  const SizedBox(width: 12),
                  Icon(Icons.check_rounded, size: 20, color: fg),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// [groups] as Expressive menu groups, for a [PopupMenuButton]'s
/// itemBuilder.
List<PopupMenuEntry<T>> menuGroups<T>(List<List<MenuOption<T>>> groups) {
  final shown = [for (final g in groups) if (g.isNotEmpty) g];
  return [
    for (var i = 0; i < shown.length; i++)
      MenuGroup<T>(shown[i], index: i, count: shown.length),
  ];
}

/// Picking one of [options] (Kotlin's PickOneMenu): one group, the current
/// one marked selected (also for screen readers).
List<PopupMenuEntry<K>> pickOneMenu<K>(List<(K, String)> options, K? selected,
        {IconData Function(K)? icon}) =>
    [
      MenuGroup<K>([
        for (final (k, label) in options)
          MenuOption(k, label, icon: icon?.call(k), selected: k == selected),
      ]),
    ];
