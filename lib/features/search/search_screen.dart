import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/widgets/connected_choice.dart';
import '../../core/widgets/error_view.dart';
import '../../core/widgets/loading.dart';
import '../../core/widgets/pick_one_menu.dart';
import '../auth/auth_controller.dart';
import '../settings/settings_controller.dart';
import '../../models/listing.dart';
import '../../models/post.dart';
import '../../models/reddit_user.dart';
import '../../models/subreddit.dart';
import '../feed/post_card.dart';
import 'saved_searches.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen(
      {super.key,
      this.initialSubreddit,
      this.initialQuery,
      this.initialSort,
      this.initialTime});
  final String? initialSubreddit;
  final String? initialQuery;
  // A saved search from another subreddit opens with its sort and time.
  final String? initialSort;
  final String? initialTime;

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
    _sort = widget.initialSort ?? _sort;
    _time = widget.initialTime ?? _time;
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
      _loading = false;
    });
    _request++;
  }

  /// A saved search here (same scope) runs in place; another subreddit's
  /// opens its own search.
  void _runSaved(SavedSearch s) {
    final here = widget.initialSubreddit;
    if ((s.subreddit ?? '').toLowerCase() == (here ?? '').toLowerCase() &&
        (s.subreddit == null) == (here == null)) {
      setState(() {
        _sort = s.sort;
        _time = s.time;
      });
      _search(s.query, saveRecent: false);
    } else {
      final q = Uri(queryParameters: {
        if (s.subreddit != null) 'sr': s.subreddit!,
        'q': s.query,
        'sort': s.sort,
        't': s.time,
      }).query;
      context.push('/search?$q');
    }
  }

  Future<void> _search(String q, {bool saveRecent = true}) async {
    q = q.trim();
    if (q.isEmpty) return;
    if (_controller.text != q) _controller.text = q;
    FocusScope.of(context).unfocus();
    if (saveRecent) _saveRecent(q);
    final request = ++_request;
    // A new search: the old one's paging state goes with it — a leftover
    // _loadingMore otherwise blocked paging for good.
    setState(() {
      _loading = true;
      _loadingMore = false;
      _postsAfter = null;
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
    if (after == null || after.isEmpty || _loadingMore || _loading) return;
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
    final saved = ref.watch(savedSearchesProvider);
    final current =
        SavedSearch(_query, widget.initialSubreddit, _sort, _time);
    final isSaved =
        _query.isNotEmpty && saved.any((s) => s.key == current.key);
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
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      // Save this search (with its sort and time) to run
                      // again from here.
                      if (_query.isNotEmpty &&
                          _query == _controller.text.trim())
                        IconButton(
                          tooltip:
                              isSaved ? 'Remove saved search' : 'Save search',
                          icon: Icon(
                              isSaved
                                  ? Icons.bookmark_rounded
                                  : Icons.bookmark_border_rounded,
                              color: isSaved ? cs.primary : null),
                          onPressed: () {
                            final store =
                                ref.read(savedSearchesProvider.notifier);
                            if (isSaved) {
                              store.remove(current);
                            } else {
                              store.add(current);
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Search saved: it\'s '
                                          'listed here before you type')));
                            }
                          },
                        ),
                      IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: _clear,
                      ),
                    ]),
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
            ? const Center(child: Loading())
            : _error != null
                ? ErrorView(
                    message: _error,
                    onRetry: () => _search(_query, saveRecent: false))
                : _query.isEmpty
                    ? _empty(cs, saved)
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

  Widget _empty(ColorScheme cs, List<SavedSearch> saved) {
    if (_recent.isEmpty && saved.isEmpty) {
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
    final header =
        TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600);
    // Saved, then "Recent" with its Clear, then the recent searches.
    final savedRows = saved.isEmpty ? 0 : saved.length + 1;
    final recentRows = _recent.isEmpty ? 0 : _recent.length + 1;
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 130),
      itemCount: savedRows + recentRows,
      itemBuilder: (_, i) {
        if (i < savedRows) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Text('Saved', style: header),
            );
          }
          final s = saved[i - 1];
          return ListTile(
            key: ValueKey('s_${s.key}'),
            leading: Icon(Icons.bookmark_rounded, color: cs.primary),
            title: Text(s.query),
            subtitle: Text([
              s.subreddit != null ? 'in r/${s.subreddit}' : 'all of Reddit',
              _sorts[s.sort] ?? s.sort,
              if (s.sort == 'top') _times[s.time] ?? s.time,
            ].join(' · ')),
            trailing: IconButton(
              tooltip: 'Remove saved search',
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: () =>
                  ref.read(savedSearchesProvider.notifier).remove(s),
            ),
            onTap: () => _runSaved(s),
          );
        }
        final j = i - savedRows;
        if (j == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
            child: Row(
              children: [
                Text('Recent', style: header),
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
          );
        }
        final q = _recent[j - 1];
        return ListTile(
          key: ValueKey('r_$q'),
          leading: const Icon(Icons.history_rounded),
          title: Text(q),
          trailing: IconButton(
            icon: const Icon(Icons.north_west_rounded, size: 18),
            onPressed: () => _search(q, saveRecent: false),
          ),
          onTap: () => _search(q),
        );
      },
    );
  }

  Widget _filterBar() {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 2),
      child: Row(
        children: [
          // The sort as one connected button group; the time range sits
          // beside it.
          ConnectedChoice<String>(
            options: [for (final e in _sorts.entries) (e.key, e.value)],
            selected: _sort,
            fill: false,
            onSelect: (k) {
              setState(() => _sort = k);
              _search(_query, saveRecent: false);
            },
          ),
          if (_sort == 'top') ...[
            const SizedBox(width: 12),
            PopupMenuButton<String>(
              initialValue: _time,
              onSelected: (v) {
                setState(() => _time = v);
                _search(_query, saveRecent: false);
              },
              itemBuilder: (_) => pickOneMenu(
                  [for (final t in _times.entries) (t.key, t.value)], _time),
              child: Chip(
                avatar: const Icon(Icons.schedule_rounded, size: 16),
                label: Text(_times[_time] ?? 'All time'),
                shape: const StadiumBorder(),
                side: BorderSide.none,
                backgroundColor: cs.surfaceContainerHigh,
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
            child: RefreshBox(
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
                            child: Center(child: Loading()),
                          );
                        }
                        // Page in more results 5 cards from the end.
                        if (i >= _posts.length - 5) {
                          WidgetsBinding.instance.addPostFrameCallback(
                              (_) => _loadMorePosts());
                        }
                        return PostCard(
                            key: ValueKey(_posts[i].id), post: _posts[i]);
                      },
                    ),
            ),
          ),
        ],
      );

  Widget _subsTab() {
    final cs = Theme.of(context).colorScheme;
    return RefreshBox(
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
                key: ValueKey(s.name),
                leading: LetterAvatar(
                    name: s.name,
                    size: 40,
                    container: cs.secondaryContainer,
                    content: cs.onSecondaryContainer),
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
    return RefreshBox(
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
                key: ValueKey(u.name),
                leading: LetterAvatar(
                    name: u.name,
                    size: 40,
                    container: cs.secondaryContainer,
                    content: cs.onSecondaryContainer),
                title: Text('u/${u.name}'),
                subtitle: Text('${compactNumber(u.linkKarma + u.commentKarma)} karma'),
                onTap: () => context.push('/u/${u.name}'),
              );
            },
          ),
    );
  }
}
