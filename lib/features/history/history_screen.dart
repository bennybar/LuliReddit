import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/deep_links.dart';
import 'history_store.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyControllerProvider);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          if (history.isNotEmpty)
            IconButton(
              tooltip: 'Clear history',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () =>
                  ref.read(historyControllerProvider.notifier).clear(),
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: cs.surfaceContainerHigh,
            padding: const EdgeInsets.all(12),
            child: Text(
              'Recently viewed posts are stored only on this device — Reddit '
              'does not sync viewing history to third-party apps.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: history.isEmpty
                ? const Center(child: Text('No history yet'))
                : ListView.builder(
                    itemCount: history.length,
                    itemBuilder: (_, i) {
                      final e = history[i];
                      return ListTile(
                        title: Text(e.title,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text('r/${e.subreddit}'),
                        onTap: () {
                          final route = e.permalink.isNotEmpty
                              ? routeForRedditUrl(
                                  Uri.parse('https://reddit.com${e.permalink}'))
                              : '/comments/${e.subreddit}/${e.id}';
                          if (route != null) context.push(route);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
