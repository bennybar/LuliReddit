import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/deep_links.dart';
import 'history_store.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  String _query = '';
  String? _subFilter; // null = all subreddits

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(historyControllerProvider);
    final ctrl = ref.read(historyControllerProvider.notifier);
    final cs = Theme.of(context).colorScheme;

    final subs = {for (final e in history) e.subreddit}.toList()..sort();
    final q = _query.trim().toLowerCase();
    // Keep the chosen filter valid if its subreddit dropped out of history.
    final subFilter = (_subFilter != null && subs.contains(_subFilter))
        ? _subFilter
        : null;
    final filtered = [
      for (final e in history)
        if ((subFilter == null || e.subreddit == subFilter) &&
            (q.isEmpty ||
                e.title.toLowerCase().contains(q) ||
                e.subreddit.toLowerCase().contains(q)))
          e
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          if (subs.isNotEmpty)
            PopupMenuButton<String?>(
              tooltip: 'Filter by subreddit',
              icon: Icon(subFilter == null
                  ? Icons.filter_list_rounded
                  : Icons.filter_list_alt),
              onSelected: (v) => setState(() => _subFilter = v),
              itemBuilder: (_) => [
                const PopupMenuItem(value: null, child: Text('All subreddits')),
                for (final s in subs)
                  PopupMenuItem(value: s, child: Text('r/$s')),
              ],
            ),
          if (history.isNotEmpty)
            PopupMenuButton<String>(
              tooltip: 'Clear history',
              icon: const Icon(Icons.delete_outline_rounded),
              onSelected: (v) {
                switch (v) {
                  case '7':
                    ctrl.clearOlderThan(const Duration(days: 7));
                  case '30':
                    ctrl.clearOlderThan(const Duration(days: 30));
                  case 'all':
                    ctrl.clear();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: '7', child: Text('Clear older than 7 days')),
                PopupMenuItem(
                    value: '30', child: Text('Clear older than 30 days')),
                PopupMenuItem(value: 'all', child: Text('Clear all history')),
              ],
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
          if (history.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search history',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: cs.surfaceContainerHigh,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          Expanded(
            child: history.isEmpty
                ? const Center(child: Text('No history yet'))
                : filtered.isEmpty
                    ? const Center(child: Text('No matches'))
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final e = filtered[i];
                          return ListTile(
                            title: Text(e.title,
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                            subtitle: Text('r/${e.subreddit}'),
                            trailing: IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18),
                              tooltip: 'Remove',
                              onPressed: () => ctrl.removeViewed(e.id),
                            ),
                            onTap: () {
                              final route = e.permalink.isNotEmpty
                                  ? routeForRedditUrl(Uri.parse(
                                      'https://reddit.com${e.permalink}'))
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
