import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../models/post.dart';
import '../../models/reddit_user.dart';
import '../../models/subreddit.dart';
import '../feed/post_card.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.initialSubreddit});
  final String? initialSubreddit;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  bool _loading = false;
  String _query = '';
  List<Post> _posts = [];
  List<Subreddit> _subs = [];
  List<RedditUser> _users = [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    setState(() {
      _query = '';
      _posts = [];
      _subs = [];
      _users = [];
    });
  }

  Future<void> _search(String q) async {
    q = q.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _query = q;
    });
    final repo = ref.read(redditRepositoryProvider);
    try {
      final results = await Future.wait([
        repo.searchPosts(q, subreddit: widget.initialSubreddit),
        if (widget.initialSubreddit == null)
          repo.searchSubreddits(q)
        else
          Future.value(<Subreddit>[]),
        if (widget.initialSubreddit == null)
          repo.searchUsers(q)
        else
          Future.value(<RedditUser>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _posts = (results[0] as dynamic).items as List<Post>;
        _subs = results[1] as List<Subreddit>;
        _users = results[2] as List<RedditUser>;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final restricted = widget.initialSubreddit != null;
    return DefaultTabController(
      length: restricted ? 1 : 3,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 8,
          title: TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: restricted
                  ? 'Search in r/${widget.initialSubreddit}'
                  : 'Search Reddit',
              isDense: true,
              filled: true,
              fillColor: cs.surfaceContainerHigh,
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: _clear,
                    ),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          bottom: restricted
              ? null
              : const TabBar(tabs: [
                  Tab(text: 'Posts'),
                  Tab(text: 'Subreddits'),
                  Tab(text: 'Users'),
                ]),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _query.isEmpty
                ? _empty(cs)
                : TabBarView(
                    children: [
                      _postsTab(),
                      if (!restricted) _subsTab(),
                      if (!restricted) _usersTab(),
                    ],
                  ),
      ),
    );
  }

  Widget _empty(ColorScheme cs) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_rounded, size: 56, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text('Search posts, subreddits and users',
                style: TextStyle(color: cs.onSurfaceVariant)),
          ],
        ),
      );

  Widget _postsTab() => _posts.isEmpty
      ? const Center(child: Text('No posts found'))
      : ListView.separated(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 130),
          itemCount: _posts.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => PostCard(post: _posts[i]),
        );

  Widget _subsTab() {
    final cs = Theme.of(context).colorScheme;
    return _subs.isEmpty
        ? const Center(child: Text('No subreddits found'))
        : ListView.builder(
            padding: const EdgeInsets.only(bottom: 130),
            itemCount: _subs.length,
            itemBuilder: (_, i) {
              final s = _subs[i];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: cs.secondaryContainer,
                  foregroundColor: cs.onSecondaryContainer,
                  child:
                      Text(s.name.isNotEmpty ? s.name[0].toUpperCase() : '?'),
                ),
                title: Text(s.namePrefixed),
                subtitle: Text('${compactNumber(s.subscribers)} members'),
                onTap: () => context.push('/r/${s.name}'),
              );
            },
          );
  }

  Widget _usersTab() {
    final cs = Theme.of(context).colorScheme;
    return _users.isEmpty
        ? const Center(child: Text('No users found'))
        : ListView.builder(
            padding: const EdgeInsets.only(bottom: 130),
            itemCount: _users.length,
            itemBuilder: (_, i) {
              final u = _users[i];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: cs.secondaryContainer,
                  foregroundColor: cs.onSecondaryContainer,
                  child:
                      Text(u.name.isNotEmpty ? u.name[0].toUpperCase() : '?'),
                ),
                title: Text('u/${u.name}'),
                subtitle: Text('${compactNumber(u.linkKarma + u.commentKarma)} karma'),
                onTap: () => context.push('/u/${u.name}'),
              );
            },
          );
  }
}
