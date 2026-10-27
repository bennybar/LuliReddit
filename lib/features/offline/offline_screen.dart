import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import 'offline_store.dart';

/// "Read later": threads saved for offline reading. Opening one loads it
/// live when online and from the saved copy when not.
class OfflineScreen extends ConsumerWidget {
  const OfflineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final threads = ref.watch(offlineProvider);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Read later')),
      body: threads.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Nothing saved yet. Use "Save for offline" in a post\'s ⋯ '
                  'menu to keep it, with its comments, for reading without '
                  'a connection.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 130),
              itemCount: threads.length,
              itemBuilder: (_, i) {
                final t = threads[i];
                return Dismissible(
                  key: ValueKey(t.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: cs.errorContainer,
                    alignment: AlignmentDirectional.centerEnd,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Icon(Icons.delete_outline_rounded,
                        color: cs.onErrorContainer),
                  ),
                  onDismissed: (_) =>
                      ref.read(offlineProvider.notifier).remove(t.id),
                  child: ListTile(
                    leading: const Icon(Icons.offline_pin_rounded),
                    title: Text(t.title,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text('r/${t.subreddit} · saved '
                        '${timeAgo(DateTime.fromMillisecondsSinceEpoch(t.savedAt))}'),
                    onTap: () =>
                        context.push('/comments/${t.subreddit}/${t.id}'),
                  ),
                );
              },
            ),
    );
  }
}
