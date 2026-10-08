import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/widgets/error_view.dart';
import '../auth/auth_controller.dart';
import '../settings/settings_controller.dart';
import '../../models/listing.dart';
import '../../models/post.dart';
import '../../models/reddit_user.dart';
import '../../models/subreddit.dart';
import '../feed/post_card.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.initialSubreddit, this.initialQuery});
  final String? initialSubreddit;
  final String? initialQuery;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  bool _loading = false;
  String _query = '';
  String _sort = 'relevance';
  String _time = 'all';
  List<Post> _posts = [];
  List<Subreddit> _subs = [];
  List<RedditUser> _users = [];
  List<String> _recent = [];
  Object? _error;
  String? _postsAfter; // next page of post results
  bool _loadingMore = false;
  // Bumped per search: a slow earlier search (e.g. before a sort change) must
  // not overwrite the results of a newer one.
  int _request = 0;

  static const _sorts = {
    'relevance': 'Relevance',
    'hot': 'Hot',
    'top': 'Top',
    'new': 'New',
    'comments': 'Comments',
  };
  static const _times = {
    'hour': 'Hour',
    'day': 'Day',
    'week': 'Week',
    'month': 'Month',
    'year': 'Year',
    'all': 'All time',
  };
  static const _legacyRecentKey = 'recent_searches';
  late final String _recentKey;

  @override
  void initState() {
    super.initState();
    // Per account, like the rest of the on-device history.
    final user =
        ref.read(authControllerProvider).valueOrNull?.username.toLowerCase();
    _recentKey = user == null || user.isEmpty
        ? _legacyRecentKey
        : '${_legacyRecentKey}_$user';
    final prefs = ref.read(sharedPrefsProvider);
    if (_recentKey != _legacyRecentKey &&
        !prefs.containsKey(_recentKey) &&
        prefs.containsKey(_legacyRecentKey)) {
      prefs.setStringList(
          _recentKey, prefs.getStringList(_legacyRecentKey) ?? const []);
      prefs.remove(_legacyRecentKey);
    }
    _recent = prefs.getStringList(_recentKey) ?? [];
    final q = widget.initialQuery?.trim() ?? '';
    if (q.isNotEmpty) {
      _controller.text = q;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _search(q));
    }
  }

  void _saveRecent(String q) {
    // Recent searches are history: none kept while tracking is off.
    if (!ref.read(settingsControllerProvider).trackHistory) return;
    final list = [q, ..._recent.where((e) => e != q)].take(12).toList();
    ref.read(sharedPrefsProvider).setStringList(_recentKey, list);
    setState(() => _recent = list);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    setState(() {
      _query = '';
      _error = null;
      _posts = [];
      _subs = [];
      _users = [];
    });
  }

  Future<void> _search(String q, {bool saveRecent = true}) async {
    q = q.trim();
    if (q.isEmpty) return;
    if (_controller.text != q) _controller.text = q;
    FocusScope.of(context).unfocus();
    if (saveRecent) _saveRecent(q);
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
      _query = q;
    });
    final repo = ref.read(redditRepositoryProvider);
    try {
      final results = await Future.wait([
        repo.searchPosts(q,
            subreddit: widget.initialSubreddit, sort: _sort, time: _time),
        if (widget.initialSubreddit == null)
          repo.searchSubreddits(q)
        else
          Future.value(<Subreddit>[]),
        if (widget.initialSubreddit == null)
          repo.searchUsers(q)
        else
          Future.value(<RedditUser>[]),
      ]);
      if (!mounted || request != _request) return;
      final posts = results[0] as Listing<Post>;
      setState(() {
        _posts = posts.items;
        _postsAfter = posts.after;
        _subs = results[1] as List<Subreddit>;
        _users = results[2] as List<RedditUser>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _error = e; // shown instead of a misleading "No results"
      });
    }
  }

  Future<void> _loadMorePosts() async {
    final after = _postsAfter;
    if (after == null || after.isEmpty || _loadingMore) return;
    final request = _request;
    setState(() => _loadingMore = true);
    try {
      final page = await ref.read(redditRepositoryProvider).searchPosts(_query,
          subreddit: widget.initialSubreddit,
          sort: _sort,
          time: _time,
          after: after);
      if (!mounted || request != _request) return;
      final seen = {for (final p in _posts) p.id};
      setState(() {
        _posts = [..._posts, ...page.items.where((p) => !seen.contains(p.id))];
        _postsAfter = page.after;
      });
    } catch (_) {
      // Keep the cursor: scrolling to the end again retries.
    } finally {
      if (mounted && request == _request) setState(() => _loadingMore = false);
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
            autofocus: (widget.initialQuery?.trim().isEmpty ?? true),
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
            : _error != null
                ? ErrorView(
                    message: _error,
                    onRetry: () => _search(_query, saveRecent: false))
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

  Widget _empty(ColorScheme cs) {
    if (_recent.isEmpty) {
      return Center(
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
    }
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 130),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
          child: Row(
            children: [
              Text('Recent',
                  style: TextStyle(
                      color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton(
                onPressed: () {
                  ref.read(sharedPrefsProvider).remove(_recentKey);
                  setState(() => _recent = []);
                },
                child: const Text('Clear'),
              ),
            ],
          ),
        ),
        for (final q in _recent)
          ListTile(
            leading: const Icon(Icons.history_rounded),
            title: Text(q),
            trailing: IconButton(
              icon: const Icon(Icons.north_west_rounded, size: 18),
              onPressed: () {
                _controller.text = q;
                _search(q, saveRecent: false);
              },
            ),
            onTap: () => _search(q),
          ),
      ],
    );
  }

  Widget _filterBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 2),
      child: Row(
        children: [
          for (final e in _sorts.entries) ...[
            ChoiceChip(
              label: Text(e.value),
              selected: _sort == e.key,
              onSelected: (_) {
                setState(() => _sort = e.key);
                _search(_query, saveRecent: false);
              },
            ),
            const SizedBox(width: 6),
          ],
          if (_sort == 'top') ...[
            const SizedBox(width: 6),
            PopupMenuButton<String>(
              initialValue: _time,
              onSelected: (v) {
                setState(() => _time = v);
                _search(_query, saveRecent: false);
              },
              itemBuilder: (_) => [
                for (final t in _times.entries)
                  PopupMenuItem(value: t.key, child: Text(t.value)),
              ],
              child: Chip(
                avatar: const Icon(Icons.schedule_rounded, size: 16),
                label: Text(_times[_time] ?? 'All time'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _postsTab() => Column(
        children: [
          _filterBar(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _search(_query, saveRecent: false),
              child: _posts.isEmpty
                  ? ListView(children: const [
                      SizedBox(height: 120),
                      Center(child: Text('No posts found')),
                    ])
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(10, 6, 10, 130),
                      itemCount: _posts.length + (_loadingMore ? 1 : 0),
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        if (i >= _posts.length) {
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        // Page in more results 5 cards from the end.
                        if (i >= _posts.length - 5) {
                          WidgetsBinding.instance.addPostFrameCallback(
                              (_) => _loadMorePosts());
                        }
                        return PostCard(post: _posts[i]);
                      },
                    ),
            ),
          ),
        ],
      );

  Widget _subsTab() {
    final cs = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: () => _search(_query, saveRecent: false),
      child: _subs.isEmpty
        ? ListView(children: const [
            SizedBox(height: 120),
            Center(child: Text('No subreddits found')),
          ])
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
          ),
    );
  }

  Widget _usersTab() {
    final cs = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: () => _search(_query, saveRecent: false),
      child: _users.isEmpty
        ? ListView(children: const [
            SizedBox(height: 120),
            Center(child: Text('No users found')),
          ])
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
          ),
    );
  }
}
