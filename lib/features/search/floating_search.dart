import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/glass_surface.dart';
import '../settings/settings_controller.dart';

const _recentKey = 'recent_searches';

/// A lightweight floating search launcher: a glass search field (plus recent
/// searches) that drops in from the top and hands off to the full results
/// screen. Used by the compact top bar's magnifier.
Future<void> showFloatingSearch(BuildContext context) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Search',
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (ctx, _, __) => const _FloatingSearch(),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, -0.06), end: Offset.zero)
              .animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _FloatingSearch extends ConsumerStatefulWidget {
  const _FloatingSearch();

  @override
  ConsumerState<_FloatingSearch> createState() => _FloatingSearchState();
}

class _FloatingSearchState extends ConsumerState<_FloatingSearch> {
  final _controller = TextEditingController();
  late final List<String> _recent =
      ref.read(sharedPrefsProvider).getStringList(_recentKey) ?? const [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _go(String query) {
    final q = query.trim();
    if (q.isEmpty) return;
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.push('/search?q=${Uri.encodeQueryComponent(q)}');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GlassSurface(
                borderRadius: BorderRadius.circular(28),
                tintOpacity: 1.0,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Icon(Icons.search_rounded, color: cs.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          autofocus: true,
                          textInputAction: TextInputAction.search,
                          onSubmitted: _go,
                          decoration: const InputDecoration(
                            hintText: 'Search Reddit',
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Search',
                        icon: const Icon(Icons.arrow_forward_rounded),
                        onPressed: () => _go(_controller.text),
                      ),
                    ],
                  ),
                ),
              ),
              if (_recent.isNotEmpty) ...[
                const SizedBox(height: 8),
                GlassSurface(
                  borderRadius: BorderRadius.circular(20),
                  tintOpacity: 1.0,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final q in _recent.take(6))
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.history_rounded, size: 20),
                          title: Text(q,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () => _go(q),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
