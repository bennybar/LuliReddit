import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../history/interest_store.dart';

/// Lets the user review and undo the per-subreddit signals that shape the
/// "For You (Beta)" feed: subreddits they've muted, told us to show less of, or
/// that the model has learned to favour. Everything here is local + per-account.
class ManageForYouScreen extends ConsumerWidget {
  const ManageForYouScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final muted = ref.watch(mutedSubsProvider).toList()..sort();
    final weights = ref.watch(interestStoreProvider);
    final interest = ref.read(interestStoreProvider.notifier);
    final mutedCtrl = ref.read(mutedSubsProvider.notifier);

    // Demoted (negative) and boosted (clearly positive) subreddits.
    final less = weights.entries.where((e) => e.value < 0).toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final more = weights.entries.where((e) => e.value >= 3).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final empty = muted.isEmpty && less.isEmpty && more.isEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Manage For You')),
      body: empty
          ? _Empty(cs: cs)
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                if (muted.isNotEmpty) ...[
                  _section(context, 'Muted', 'Hidden from For You entirely'),
                  for (final sub in muted)
                    ListTile(
                      leading: const Icon(Icons.volume_off_rounded),
                      title: Text('r/$sub'),
                      trailing: TextButton(
                        onPressed: () => mutedCtrl.toggle(sub),
                        child: const Text('Unmute'),
                      ),
                    ),
                ],
                if (less.isNotEmpty) ...[
                  _section(context, 'Showing less',
                      'You asked to see less of these'),
                  for (final e in less)
                    ListTile(
                      leading: const Icon(Icons.thumb_down_alt_outlined),
                      title: Text('r/${e.key}'),
                      trailing: TextButton(
                        onPressed: () => interest.reset(e.key),
                        child: const Text('Reset'),
                      ),
                    ),
                ],
                if (more.isNotEmpty) ...[
                  _section(context, 'Showing more',
                      'Learned favourites — reset to forget'),
                  for (final e in more)
                    ListTile(
                      leading: const Icon(Icons.thumb_up_alt_outlined),
                      title: Text('r/${e.key}'),
                      trailing: TextButton(
                        onPressed: () => interest.reset(e.key),
                        child: const Text('Reset'),
                      ),
                    ),
                ],
              ],
            ),
    );
  }

  Widget _section(BuildContext context, String title, String subtitle) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    )),
            Text(subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.cs});
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tune_rounded, size: 48, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text('Nothing to manage yet',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Mute a subreddit or tap “Less” on a For You post and it will show '
              'up here, where you can undo it.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
