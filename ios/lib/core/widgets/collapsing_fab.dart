import 'package:flutter/material.dart';

/// A floating button with a label, or just its icon once scrolled, like
/// Gmail's Compose (#62). A plain, unbouncy animation: the label stays laid
/// out, so it's revealed and fades rather than popping in or out (#65).
class CollapsingFab extends StatelessWidget {
  const CollapsingFab({
    super.key,
    required this.icon,
    required this.label,
    required this.expanded,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool expanded;
  final VoidCallback onTap;

  static const _duration = Duration(milliseconds: 250);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: cs.primaryContainer,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: cs.onPrimaryContainer),
                ClipRect(
                  child: AnimatedAlign(
                    duration: _duration,
                    curve: Curves.fastOutSlowIn,
                    alignment: AlignmentDirectional.centerStart,
                    widthFactor: expanded ? 1 : 0,
                    child: AnimatedOpacity(
                      duration: expanded
                          ? _duration
                          : const Duration(milliseconds: 120),
                      opacity: expanded ? 1 : 0,
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(start: 12),
                        child: Text(label,
                            maxLines: 1,
                            softWrap: false,
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(color: cs.onPrimaryContainer)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
