import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:go_router/go_router.dart';

import '../../core/deep_links.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../models/comment.dart';
import '../../models/post.dart';
import '../auth/auth_controller.dart';
import '../feed/post_card.dart';

/// A dedicated, searchable hub for the user's Saved items, with a type filter
/// (all / posts / comments) and live text search over what's loaded.
class SavedHubScreen extends ConsumerStatefulWidget {
  const SavedHubScreen({super.key});

  @override
  ConsumerState<SavedHubScreen> createState() => _SavedHubScreenState();
}

class _SavedHubScreenState extends ConsumerState<SavedHubScreen> {
  final _scroll = ScrollController();
  final _items = <Object>[];
  String? _after;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;

  String _query = '';
  String _type = 'all'; // all | posts | comments

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 500) {
        _loadMore();
      }
    });
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  String get _username =>
      ref.read(authControllerProvider).valueOrNull?.username ?? '';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final listing =
          await ref.read(redditRepositoryProvider).getUserSaved(_username);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(listing.items);
        _after = listing.after;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _after == null || _after!.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final listing = await ref
          .read(redditRepositoryProvider)
          .getUserSaved(_username, after: _after);
      if (!mounted) return;
      setState(() {
        _items.addAll(listing.items);
        _after = listing.after;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  List<Object> get _filtered {
    final q = _query.trim().toLowerCase();
    return [
      for (final it in _items)
        if ((_type == 'all' ||
                (_type == 'posts' && it is Post) ||
                (_type == 'comments' && it is Comment)) &&
            (q.isEmpty ||
                (it is Post && it.title.toLowerCase().contains(q)) ||
                (it is Comment && it.body.toLowerCase().contains(q))))
          it
    ];
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final filtered = _filtered;
    return Scaffold(
      appBar: AppBar(title: const Text('Saved')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search saved',
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
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                for (final t in const [
                  ('all', 'All'),
                  ('posts', 'Posts'),
                  ('comments', 'Comments'),
                ]) ...[
                  ChoiceChip(
                    label: Text(t.$2),
                    selected: _type == t.$1,
                    onSelected: (_) => setState(() => _type = t.$1),
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Text('Could not load saved.\n$_error',
                                textAlign: TextAlign.center),
                            const SizedBox(height: 12),
                            FilledButton(
                                onPressed: _load, child: const Text('Retry')),
                          ]),
                        ),
                      )
                    : filtered.isEmpty
                        ? Center(
                            child: Text(_items.isEmpty
                                ? 'Nothing saved'
                                : 'No matches'))
                        : ListView.separated(
                            controller: _scroll,
                            padding: const EdgeInsets.fromLTRB(10, 8, 10, 32),
                            itemCount: filtered.length + 1,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              if (i == filtered.length) {
                                return _loadingMore
                                    ? const Padding(
                                        padding: EdgeInsets.all(16),
                                        child: Center(
                                            child:
                                                CircularProgressIndicator()))
                                    : const SizedBox.shrink();
                              }
                              final it = filtered[i];
                              return it is Post
                                  ? PostCard(post: it)
                                  : _SavedComment(comment: it as Comment);
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

class _SavedComment extends StatelessWidget {
  const _SavedComment({required this.comment});
  final Comment comment;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          if (comment.permalink.isEmpty) return;
          final route = routeForRedditUrl(
              Uri.parse('https://reddit.com${comment.permalink}'));
          if (route != null) context.push(route);
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.mode_comment_outlined, size: 14, color: cs.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'r/${comment.subreddit} · u/${comment.author} · ${compactNumber(comment.score)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ),
              ]),
              const SizedBox(height: 6),
              MarkdownBody(data: comment.body),
            ],
          ),
        ),
      ),
    );
  }
}
