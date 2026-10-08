import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../foryou/for_you_stores.dart';
import '../history/interest_store.dart';

/// Everything that shapes the "For You (Beta)" feed, visible and undoable:
/// explicit choices, mutes, learned topics and communities, and a full reset.
/// All local and per-account. Long-press the title for local metrics.
class ManageForYouScreen extends ConsumerWidget {
  const ManageForYouScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final explicit = ref.watch(explicitPrefsProvider);
    final explicitCtrl = ref.read(explicitPrefsProvider.notifier);
    final muted = ref.watch(mutedSubsProvider).toList()..sort();
    final mutedCtrl = ref.read(mutedSubsProvider.notifier);
    final weights = ref.watch(interestStoreProvider);
    final interest = ref.read(interestStoreProvider.notifier);
    final keywords = ref.watch(keywordStoreProvider);
    final keywordCtrl = ref.read(keywordStoreProvider.notifier);
    ref.watch(docFreqProvider);
    final df = ref.read(docFreqProvider.notifier);

    // Learned topics, by how much they actually matter: weight × rarity.
    final topics = (keywords.entries.where((e) => e.value.abs() >= 1).toList()
          ..sort((a, b) => (b.value.abs() * df.idf(b.key))
              .compareTo(a.value.abs() * df.idf(a.key))))
        .take(20)
        .toList();
    final less = weights.entries.where((e) => e.value < 0).toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final more = weights.entries.where((e) => e.value >= 3).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final empty = explicit.isEmpty &&
        muted.isEmpty &&
        topics.isEmpty &&
        less.isEmpty &&
        more.isEmpty;

    Widget sign(int v) => Icon(
        v > 0 ? Icons.thumb_up_alt_outlined : Icons.thumb_down_alt_outlined,
        color: v > 0 ? cs.primary : cs.error);

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onLongPress: () => _showMetrics(context, ref),
          child: const Text('Manage For You'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (empty) _Empty(cs: cs),
          if (!explicit.isEmpty) ...[
            _section(context, 'Your choices',
                'What you asked for with More / Less — these don\'t fade'),
            for (final e in explicit.subs.entries)
              ListTile(
                leading: sign(e.value),
                title: Text('r/${e.key}'),
                subtitle: Text(e.value > 0 ? 'More from here' : 'Less from here'),
                trailing: TextButton(
                    onPressed: () => explicitCtrl.setSub(e.key, 0),
                    child: const Text('Remove')),
              ),
            for (final e in explicit.topics.entries)
              ListTile(
                leading: sign(e.value),
                title: Text('“${e.key}”'),
                subtitle:
                    Text(e.value > 0 ? 'More about this' : 'Less about this'),
                trailing: TextButton(
                    onPressed: () => explicitCtrl.setTopic(e.key, 0),
                    child: const Text('Remove')),
              ),
          ],
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
          if (topics.isNotEmpty) ...[
            _section(context, 'Topics',
                'Learned from the titles you engage with'),
            for (final e in topics)
              ListTile(
                leading: Icon(e.value > 0
                    ? Icons.trending_up_rounded
                    : Icons.trending_down_rounded),
                title: Text('“${e.key}”'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  TextButton(
                      onPressed: () => keywordCtrl.reset(e.key),
                      child: const Text('Reset')),
                  TextButton(
                    onPressed: () {
                      keywordCtrl.reset(e.key);
                      explicitCtrl.setTopic(e.key, -1);
                    },
                    child: const Text('Block'),
                  ),
                ]),
              ),
          ],
          if (less.isNotEmpty) ...[
            _section(context, 'Showing less', 'Learned from what you skip or downvote'),
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
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('Reset For You'),
              onPressed: () => _confirmReset(context, ref),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              'Learned signals fade by half in about two weeks; your explicit '
              'choices and mutes don\'t. Everything here stays on this device.',
              style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset For You?'),
        content: const Text(
            'Forgets everything For You learned and your More / Less choices. '
            'Mutes are kept.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Reset')),
        ],
      ),
    );
    if (ok != true) return;
    ref.read(interestStoreProvider.notifier).clear();
    ref.read(keywordStoreProvider.notifier).clear();
    ref.read(impressionStoreProvider.notifier).clear();
    ref.read(explicitPrefsProvider.notifier).clear();
    ref.read(subStatsProvider.notifier).clear();
  }

  /// Local, never-uploaded counters for judging For You changes.
  void _showMetrics(BuildContext context, WidgetRef ref) {
    final m = ref.read(forYouMetricsProvider.notifier);
    final t = m.totals();
    String rate(String opens, String impr) {
      final i = t[impr] ?? 0;
      return i == 0 ? '–' : '${(100 * (t[opens] ?? 0) / i).toStringAsFixed(1)}%';
    }

    final rows = <(String, String)>[
      ('Seen (primary / discovery)',
          '${t['impr.primary'] ?? 0} / ${t['impr.discovery'] ?? 0}'),
      ('Open rate (primary)', rate('open.primary', 'impr.primary')),
      ('Open rate (discovery)', rate('open.discovery', 'impr.discovery')),
      ('Read 30s+ (primary / discovery)',
          '${t['read30.primary'] ?? 0} / ${t['read30.discovery'] ?? 0}'),
      ('Votes', '${(t['vote.primary'] ?? 0) + (t['vote.discovery'] ?? 0)}'),
      ('More / Less taps', '${t['more'] ?? 0} / ${t['less'] ?? 0}'),
      ('Discovery appetite', m.discoveryAppetite().toStringAsFixed(2)),
      for (final e in (t.entries.where((e) => e.key.startsWith('src.ranked.'))
          .toList()
            ..sort((a, b) => b.value.compareTo(a.value))))
        ('Placed from ${e.key.substring(11)}', '${e.value}'),
    ];
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('For You · last 7 days'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (k, v) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Expanded(child: Text(k)),
                    Text(v, style: const TextStyle(fontWeight: FontWeight.w700)),
                  ]),
                ),
              const SizedBox(height: 8),
              Text('On this device only. Never uploaded.',
                  style: Theme.of(ctx).textTheme.bodySmall),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 48, 32, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.tune_rounded, size: 48, color: cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Text('Nothing to manage yet',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            'Long-press a For You post to tune it, or use its ⋯ menu. Your '
            'choices and what For You learns will show up here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
