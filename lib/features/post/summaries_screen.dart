import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/deep_links.dart';
import '../../core/format.dart';
import '../../core/widgets/markdown_style.dart';
import '../../core/widgets/reddit_markdown.dart';
import 'summary_store.dart';

/// Summaries: every post summarized with AI, newest first, with its summary
/// and a link back. Select (or long-press one) to delete several, or all.
class SummariesScreen extends ConsumerStatefulWidget {
  const SummariesScreen({super.key});

  @override
  ConsumerState<SummariesScreen> createState() => _SummariesScreenState();
}

class _SummariesScreenState extends ConsumerState<SummariesScreen> {
  String _query = '';
  // Selection mode: null = off; otherwise the selected post ids.
  Set<String>? _selected;

  void _toggle(String id) => setState(() {
        final cur = {...?_selected};
        cur.contains(id) ? cur.remove(id) : cur.add(id);
        _selected = cur;
      });

  Future<void> _deleteSelected() async {
    final ids = {...?_selected};
    final n = ids.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title:
            Text(n == 1 ? 'Delete this summary?' : 'Delete $n summaries?'),
        content: const Text(
            "They're removed from this device. The posts stay on Reddit."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    ref.read(summaryStoreProvider.notifier).removeAll(ids);
    setState(() => _selected = null);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = ref.watch(summaryStoreProvider);
    final q = _query.trim().toLowerCase();
    final shown = q.isEmpty
        ? items
        : [
            for (final s in items)
              if (s.title.toLowerCase().contains(q) ||
                  s.subreddit.toLowerCase().contains(q) ||
                  s.text.toLowerCase().contains(q))
                s
          ];
    final selected = _selected;
    final selecting = selected != null;
    final allShown = shown.isNotEmpty &&
        shown.every((s) => selected?.contains(s.postId) ?? false);

    return PopScope(
      // Back leaves selection mode first.
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _selected = null);
      },
      child: Scaffold(
        appBar: selecting
            ? AppBar(
                leading: IconButton(
                  tooltip: 'Cancel selection',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => setState(() => _selected = null),
                ),
                title: Text('${selected.length} selected'),
                actions: [
                  TextButton(
                    onPressed: () => setState(() => _selected = allShown
                        ? {}
                        : {for (final s in shown) s.postId}),
                    child: Text(allShown ? 'Select none' : 'Select all'),
                  ),
                  IconButton(
                    tooltip: 'Delete selected',
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: selected.isEmpty ? null : _deleteSelected,
                  ),
                ],
              )
            : AppBar(
                title: const Text('Summaries'),
                actions: [
                  if (items.isNotEmpty)
                    IconButton(
                      tooltip: 'Select',
                      icon: const Icon(Icons.checklist_rounded),
                      onPressed: () => setState(() => _selected = {}),
                    ),
                ],
              ),
        body: Column(
          children: [
            if (items.length > 3)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Search summaries',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: BorderSide.none),
                  ),
                ),
              ),
            Expanded(
              child: items.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Text(
                            'No summaries yet. Summarize a thread with the ✦ '
                            "button in a post and it's kept here.",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: cs.onSurfaceVariant)),
                      ),
                    )
                  : shown.isEmpty
                      ? const Center(child: Text('No matches'))
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
                          itemCount: shown.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final s = shown[i];
                            return _SummaryCard(
                              key: ValueKey(s.postId),
                              summary: s,
                              selected: selecting
                                  ? selected.contains(s.postId)
                                  : null,
                              onToggle: () => _toggle(s.postId),
                              onLongPress: () {
                                if (!selecting) {
                                  setState(() => _selected = {s.postId});
                                }
                              },
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

/// [selected]: null outside selection mode; then a tap toggles the card
/// ([onToggle]).
class _SummaryCard extends ConsumerStatefulWidget {
  const _SummaryCard({
    super.key,
    required this.summary,
    required this.selected,
    required this.onToggle,
    required this.onLongPress,
  });
  final SavedSummary summary;
  final bool? selected;
  final VoidCallback onToggle;
  final VoidCallback onLongPress;

  @override
  ConsumerState<_SummaryCard> createState() => _SummaryCardState();
}

class _SummaryCardState extends ConsumerState<_SummaryCard> {
  bool _expanded = false;

  void _open() {
    final s = widget.summary;
    final route = s.permalink.isNotEmpty
        ? routeForRedditUrl(Uri.parse('https://reddit.com${s.permalink}'))
        : '/comments/${s.subreddit.isEmpty ? '_' : s.subreddit}/${s.postId}';
    if (route != null) context.push(route);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = widget.summary;
    final selected = widget.selected;
    final created = DateTime.fromMillisecondsSinceEpoch(s.createdAt);
    return Material(
      color: selected == true ? cs.secondaryContainer : cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onLongPress: widget.onLongPress,
        onTap: selected != null ? widget.onToggle : null,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                if (selected != null) ...[
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: Checkbox(
                        value: selected, onChanged: (_) => widget.onToggle()),
                  ),
                  const SizedBox(width: 6),
                ],
                Icon(Icons.auto_awesome_rounded, size: 14, color: cs.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                      'r/${s.subreddit} · ${s.style} · ${timeAgo(created)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ),
                if (selected == null) ...[
                  IconButton(
                    tooltip: 'Copy summary',
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    icon: const Icon(Icons.content_copy_rounded),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: s.text));
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copied')));
                    },
                  ),
                  IconButton(
                    tooltip: 'Remove',
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () => ref
                        .read(summaryStoreProvider.notifier)
                        .remove(s.postId),
                  ),
                ],
              ]),
              Padding(
                padding: const EdgeInsetsDirectional.only(top: 2, end: 8),
                child: GestureDetector(
                  onTap: _open,
                  child: Text(s.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w600)),
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.only(top: 8, end: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: _expanded
                      ? RedditMarkdown(
                          data: s.text,
                          selectable: true,
                          styleSheet:
                              redditMarkdownStyle(context, fontSize: 14))
                      : Text(markdownPlainText(s.text),
                          maxLines: 6,
                          overflow: TextOverflow.ellipsis,
                          textDirection: isMostlyRtl(s.text)
                              ? TextDirection.rtl
                              : null,
                          style: const TextStyle(fontSize: 14, height: 1.45)),
                ),
              ),
              Row(children: [
                TextButton(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  child: Text(_expanded ? 'Show less' : 'Full summary'),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _open,
                  iconAlignment: IconAlignment.end,
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text('Open post'),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
