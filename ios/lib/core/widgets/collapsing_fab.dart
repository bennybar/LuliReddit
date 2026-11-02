import 'package:flutter/material.dart';

import '../theme/motion.dart';

/// A floating button with a label, or just its icon once scrolled, like
/// Gmail's Compose (#62).
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
          child: AnimatedSize(
            duration: Motion.fastSpatial.duration,
            curve: Motion.fastSpatial,
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: cs.onPrimaryContainer),
                  if (expanded) ...[
                    const SizedBox(width: 12),
                    Text(label,
                        style: Theme.of(context)
                            .textTheme
                            .labelLarge
                            ?.copyWith(color: cs.onPrimaryContainer)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
