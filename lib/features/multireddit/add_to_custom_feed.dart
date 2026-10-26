import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/widgets/error_view.dart';
import '../../models/multireddit.dart';
import '../auth/auth_controller.dart';
import '../home/account_tab.dart' show createMulti;
import 'multireddit_providers.dart';

/// Add r/[subreddit] to one of your custom feeds (or take it out): your
/// feeds, ticked where it's already in (so it can't be added twice), and New
/// feed, which starts one with it. From a post's ⋮ menu and a community's top
/// bar.
Future<void> showAddToCustomFeed(BuildContext context, String subreddit) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _AddToCustomFeedSheet(subreddit: subreddit),
  );
}

class _AddToCustomFeedSheet extends ConsumerStatefulWidget {
  const _AddToCustomFeedSheet({required this.subreddit});
  final String subreddit;

  @override
  ConsumerState<_AddToCustomFeedSheet> createState() =>
      _AddToCustomFeedSheetState();
}

class _AddToCustomFeedSheetState extends ConsumerState<_AddToCustomFeedSheet> {
  // The feed being changed right now (its row shows a spinner).
  String? _busy;

  bool _contains(Multireddit m) => m.subreddits
      .any((s) => s.toLowerCase() == widget.subreddit.toLowerCase());

  Future<void> _toggle(Multireddit m) async {
    if (_busy != null) return;
    final messenger = ScaffoldMessenger.of(context);
    final sub = widget.subreddit;
    final path = m.path.replaceFirst(RegExp(r'/+$'), '');
    final add = !_contains(m);
    setState(() => _busy = m.path);
    final repo = ref.read(redditRepositoryProvider);
    try {
      if (add) {
        await repo.addSubredditToMulti(path, sub);
      } else {
        await repo.removeSubredditFromMulti(path, sub);
      }
      ref.invalidate(myMultiredditsProvider);
      // Wait for the fresh list, so the tick doesn't flicker back.
      await ref.read(myMultiredditsProvider.future);
      messenger.showSnackBar(SnackBar(
          content: Text(add
              ? 'Added r/$sub to ${m.displayName}'
              : 'Removed r/$sub from ${m.displayName}')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content:
              Text("Couldn't change ${m.displayName}: ${friendlyError(e)}")));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = widget.subreddit;
    final multis = ref.watch(myMultiredditsProvider);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text('Add r/$sub to a custom feed',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            ...multis.when(
              loading: () => const [
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ],
              error: (e, _) => [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text(
                      "Couldn't load your custom feeds: ${friendlyError(e)}"),
                ),
              ],
              data: (list) => [
                for (final m in list)
                  Builder(builder: (_) {
                    final inIt = _contains(m);
                    return ListTile(
                      key: ValueKey(m.path),
                      leading: Icon(Icons.dynamic_feed_rounded,
                          color: cs.tertiary),
                      title: Text(m.displayName),
                      subtitle: Text(inIt
                          ? 'Has r/$sub · tap to remove'
                          : '${m.subreddits.length} communities'),
                      trailing: _busy == m.path
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 3))
                          : inIt
                              ? Icon(Icons.check_circle_rounded,
                                  color: cs.primary,
                                  semanticLabel: 'In this feed')
                              : null,
                      onTap: () => _toggle(m),
                    );
                  }),
              ],
            ),
            ListTile(
              leading: const Icon(Icons.add_rounded),
              title: const Text('New feed'),
              subtitle: Text('Starts with r/$sub'),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                final nav = Navigator.of(context);
                final me = ref.read(authControllerProvider).valueOrNull
                        ?.username ??
                    '';
                if (await createMulti(context, ref, me, [sub])) {
                  messenger.showSnackBar(SnackBar(
                      content: Text('Created a feed with r/$sub')));
                  nav.pop();
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
