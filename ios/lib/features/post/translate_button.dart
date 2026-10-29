import 'package:flutter/material.dart';

import '../../core/translate.dart';

/// Translate: with one language to offer, a toggle (it / the original); with
/// two (the phone's and Settings → Second language), a menu.
class TranslateButton extends StatelessWidget {
  const TranslateButton({
    super.key,
    required this.targets,
    required this.shownIn,
    required this.busy,
    required this.onPick,
    this.size = 24,
  });

  final List<String> targets;
  final String? shownIn;
  final bool busy;
  final void Function(String? to) onPick;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = shownIn != null ? 'Show original' : 'Translate';
    final icon = busy
        ? SizedBox(
            width: size - 4,
            height: size - 4,
            child: const CircularProgressIndicator(strokeWidth: 2))
        : Icon(Icons.translate_rounded,
            size: size, color: shownIn != null ? cs.primary : null);
    if (targets.length == 1) {
      return IconButton(
        tooltip: label,
        onPressed: busy ? null : () => onPick(shownIn != null ? null : targets.single),
        icon: icon,
      );
    }
    return PopupMenuButton<String>(
      tooltip: label,
      enabled: !busy,
      icon: icon,
      onSelected: (v) => onPick(v.isEmpty ? null : v),
      itemBuilder: (_) => [
        for (final t in targets)
          CheckedPopupMenuItem(
            value: t,
            checked: t == shownIn,
            child: Text('Translate to ${Translate.languageName(t)}'),
          ),
        if (shownIn != null)
          const PopupMenuItem(value: '', child: Text('Show original')),
      ],
    );
  }
}
