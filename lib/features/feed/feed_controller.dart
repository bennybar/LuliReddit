import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/reddit_repository.dart';
import '../../models/listing.dart';
import '../../models/post.dart';
import '../history/history_store.dart';
import '../auth/auth_controller.dart';
import '../foryou/for_you_ranker.dart';
import '../foryou/for_you_seeder.dart';
import '../foryou/for_you_stores.dart';
import '../history/interest_store.dart';
import '../settings/settings_controller.dart';

class FeedState {
  const FeedState({
    required this.posts,
    required this.sort,
    required this.time,
    this.after,
    this.loadingMore = false,
    this.hasPending = false,
  });

  final List<Post> posts;
  final PostSort sort;
  final TopTime time;
  final String? after;
  final bool loadingMore;
  final bool hasPending; // a fresh page is staged behind a "New posts" pill

  bool get hasMore => after != null && after!.isNotEmpty;

  FeedState copyWith({
    List<Post>? posts,
    PostSort? sort,
    TopTime? time,
    String? after,
    bool? loadingMore,
    bool? hasPending,
  }) =>
      FeedState(
        posts: posts ?? this.posts,
        sort: sort ?? this.sort,
        time: time ?? this.time,
        after: after,
        loadingMore: loadingMore ?? this.loadingMore,
        hasPending: hasPending ?? this.hasPending,
      );
}

/// Feed for the frontpage (key == '') or a subreddit (key == name).
class FeedController extends FamilyAsyncNotifier<FeedState, String> {
  String? get _subreddit => arg.isEmpty ? null : arg;
  RedditRepository get _repo => ref.read(redditRepositoryProvider);

  PostSort? _sort;
  TopTime _time = TopTime.day;
  bool _initialized = false;
  bool _cacheConsulted = false;
  bool _showingCache = false; // a cached page is on screen, fresh one in flight
  // Bumped whenever the list is replaced (load, refresh, sort, "New posts"),
  // so a page that was in flight for the old list is dropped, not appended.
  int _generation = 0;
  DateTime _lastLoaded = DateTime.fromMillisecondsSinceEpoch(0);

  /// A multireddit feed key looks like `m::username::multiname`.
  ({String username, String name})? get _multi {
    if (!arg.startsWith('m::')) return null;
    final parts = arg.split('::');
    if (parts.length != 3) return null;
    return (username: parts[1], name: parts[2]);
  }

  bool get _isFrontpage => arg.isEmpty;
  bool get _forYou =>
      _isFrontpage && ref.read(settingsControllerProvider).forYouFeed;

  /// "Hide read posts": drops posts already in history as each page arrives.
  /// Filtering when fetched rather than live keeps a post you've just read
  /// (or scrolled past) from vanishing under you; the next load skips it.
  /// For You has its own live auto-hide option.
  Listing<Post> _dropRead(Listing<Post> listing) {
    if (_forYou || !ref.read(settingsControllerProvider).hideReadPosts) {
      return listing;
    }
    final read = {for (final e in ref.read(historyControllerProvider)) e.id};
    if (read.isEmpty) return listing;
    return Listing(
        items: [for (final p in listing.items) if (!read.contains(p.id)) p],
        after: listing.after);
  }

  Future<Listing<Post>> _fetch({String? after}) async =>
      _dropRead(await _fetchRaw(after: after));

  Future<Listing<Post>> _fetchRaw({String? after}) {
    if (_forYou) return _forYouPage(after);
    final multi = _multi;
    if (multi != null) {
      return _repo.getMultiPosts(
        username: multi.username,
        multiname: multi.name,
        sort: _sort!,
        time: _time,
        after: after,
      );
    }
    return _repo.getPosts(
        subreddit: _subreddit, sort: _sort!, time: _time, after: after);
  }

  // For You: the previous page's unplaced candidates, and which candidate
  // communities to sample next (rotated each refresh).
  List<Candidate> _leftovers = const [];
  int _communityTurn = 0;

  /// Snapshot of everything For You learned, for the ranker.
  RankInputs _rankInputs({required bool firstPage}) {
    final kw = ref.read(keywordStoreProvider.notifier);
    final df = ref.read(docFreqProvider.notifier);
    final impressions = ref.read(impressionStoreProvider.notifier);
    final loaded = state.valueOrNull?.posts ?? const <Post>[];
    return RankInputs(
      interest: ref.read(interestStoreProvider),
      subStats: ref.read(subStatsProvider),
      explicit: ref.read(explicitPrefsProvider),
      keywordScore: (t) => kw.scoreTitle(t, idf: df.idf),
      topKeyword: (t) => kw.topKeywordIn(t, idf: df.idf),
      muted: ref.read(mutedSubsProvider),
      openedAt: {
        for (final e in ref.read(historyControllerProvider)) e.id: e.viewedAt
      },
      impressions: impressions.count,
      // A refresh makes room: the old top 10 is demoted a little.
      previousTop: firstPage ? {for (final p in loaded.take(10)) p.id} : const {},
      // Stories already shown on earlier pages count toward repeats.
      previousTitles:
          firstPage ? const [] : [for (final p in loaded.reversed.take(100)) p.title],
      discoveryAppetite:
          ref.read(forYouMetricsProvider.notifier).discoveryAppetite(),
    );
  }

  /// Communities you've dipped into but don't follow (0.5 ≤ interest < 2),
  /// plus ones you asked for more of: three per refresh, rotating, as
  /// personalised discovery instead of r/popular alone.
  List<String> _candidateCommunities() {
    final explicitMore = [
      for (final e in ref.read(explicitPrefsProvider).subs.entries)
        if (e.value > 0) e.key
    ];
    final visited = (ref
            .read(interestStoreProvider)
            .entries
            .where((e) => e.value >= 0.5 && e.value < kEngagedInterest)
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .map((e) => e.key);
    final all = {...explicitMore, ...visited}.toList();
    if (all.isEmpty) return const [];
    final start = (_communityTurn++ * 3) % all.length;
    return [for (var k = 0; k < 3 && k < all.length; k++) all[(start + k) % all.length]];
  }

  Future<Listing<Post>> _forYouPage(String? after) async {
    final firstPage = after == null;
    if (firstPage) await seedForYouIfNeeded(ref);
    final page = await _repo.getForYouFeed(
      inputs: _rankInputs(firstPage: firstPage),
      communities: firstPage ? _candidateCommunities() : const [],
      cursors: after, // null = first page; else the encoded cursor bundle
      excludeIds: firstPage
          ? const {}
          : {for (final p in state.valueOrNull?.posts ?? const <Post>[]) p.id},
      carryOver: firstPage ? const [] : _leftovers,
    );
    _leftovers = page.leftovers;
    final meta = ref.read(forYouMetaProvider.notifier);
    meta.state = firstPage ? page.meta : {...meta.state, ...page.meta};
    ref.read(docFreqProvider.notifier).observe(page.candidateTitles);
    for (final p in page.listing.items) {
      ref.read(forYouMetricsProvider.notifier)
          .count('src.ranked.${page.meta[p.id]?.source ?? 'other'}');
    }
    final user = ref.read(authControllerProvider).valueOrNull?.username ?? '';
    if (firstPage && user.isNotEmpty) {
      saveForYouPage(user, page.listing.items, _repo.rawPost);
    }
    return page.listing;
  }

  @override
  Future<FeedState> build(String arg) async {
    _generation++;
    if (!_initialized) {
      _sort = ref.read(settingsControllerProvider).defaultSort;
      _initialized = true;
    }
    // Paint the last cached page straight away on a cold open, before the
    // network answers: parsing a page costs milliseconds, the request costs
    // hundreds. Only once per feed — a refresh or sort change already has
    // intent behind it and shouldn't flash an older page. Never for For You,
    // which is ranked locally from live signals.
    Listing<Post>? cached;
    if (!_cacheConsulted) {
      _cacheConsulted = true;
      cached = await _cachedFirstPage();
      if (cached != null) {
        _showingCache = true;
        state = AsyncData(FeedState(
            posts: cached.items, sort: _sort!, time: _time, after: cached.after));
      }
    }
    // Retry once: a cold-start request can fail while the token is being
    // refreshed for the first time.
    Listing<Post> listing;
    try {
      try {
        listing = await _fetch();
      } catch (_) {
        listing = await _fetch();
      }
    } catch (_) {
      // Keep the cached page rather than replacing it with an error: it's
      // still the most useful thing to show, and pull-to-refresh retries.
      if (cached == null) rethrow;
      _showingCache = false;
      return FeedState(
          posts: cached.items, sort: _sort!, time: _time, after: cached.after);
    }
    _showingCache = false;
    _lastLoaded = DateTime.now();
    return FeedState(
      posts: listing.items,
      sort: _sort!,
      time: _time,
      after: listing.after,
    );
  }

  Future<Listing<Post>?> _cachedFirstPage() async {
    if (_forYou) {
      // The last ranked For You page, minus posts opened since.
      final user = ref.read(authControllerProvider).valueOrNull?.username ?? '';
      if (user.isEmpty) return null;
      final opened = {for (final e in ref.read(historyControllerProvider)) e.id};
      final posts = await loadForYouPage(user, opened);
      return posts == null ? null : Listing(items: posts, after: null);
    }
    if (_multi != null) return null;
    try {
      final cached = await _repo.cachedPosts(
          subreddit: _subreddit, sort: _sort!, time: _time);
      return cached == null ? null : _dropRead(cached);
    } catch (_) {
      return null;
    }
  }

  Future<void> changeSort(PostSort sort, {TopTime? time}) async {
    _sort = sort;
    if (time != null) _time = time;
    // Persist the frontpage sort + turn off the For You feed.
    if (_isFrontpage) {
      final s = ref.read(settingsControllerProvider.notifier);
      s.setDefaultSort(sort);
      s.setForYouFeed(false);
    }
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => build(arg));
  }

  /// Switches the frontpage to the "For You (Beta)" feed (persisted).
  Future<void> selectForYou() async {
    ref.read(settingsControllerProvider.notifier).setForYouFeed(true);
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => build(arg));
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(() => build(arg));
  }

  // A freshly-fetched first page staged behind the "New posts" pill.
  List<Post>? _pending;
  String? _pendingAfter;

  /// When returning to a stale feed, quietly fetch the first page. If it has
  /// posts we're not already showing, stage them behind a "New posts" pill
  /// instead of yanking the list out from under the user.
  Future<void> refreshIfStale(
      [Duration maxAge = const Duration(minutes: 5)]) async {
    if (state.isLoading) return;
    final cur = state.valueOrNull;
    if (cur == null) return;
    if (cur.hasPending) return; // already staged
    if (DateTime.now().difference(_lastLoaded) < maxAge) return;
    try {
      final listing = await _fetch();
      _lastLoaded = DateTime.now();
      final currentIds = {for (final p in cur.posts) p.id};
      // For You re-ranks rising posts every time, so "anything new" was
      // almost always true; it needs 3 new posts in the new top 10.
      final hasNew = _forYou
          ? listing.items.take(10).where((p) => !currentIds.contains(p.id)).length >= 3
          : listing.items.any((p) => !currentIds.contains(p.id));
      if (hasNew) {
        _pending = listing.items;
        _pendingAfter = listing.after;
        state = AsyncData(cur.copyWith(hasPending: true, after: cur.after));
      }
    } catch (_) {/* leave the current feed in place */}
  }

  /// Swaps the staged "New posts" page in (called when the pill is tapped).
  void applyPending() {
    final cur = state.valueOrNull;
    if (cur == null || _pending == null) return;
    _generation++;
    state = AsyncData(cur.copyWith(
        posts: _pending!, after: _pendingAfter, hasPending: false));
    _pending = null;
    _pendingAfter = null;
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || current.loadingMore) return;
    // Paging off a cached page would be overwritten by the fresh one.
    if (_showingCache) return;
    final generation = _generation;
    state = AsyncData(current.copyWith(loadingMore: true, after: current.after));
    try {
      final listing = await _fetch(after: current.after);
      if (generation != _generation) return; // the list was replaced meanwhile
      // Append to the latest state, which may carry a staged "New posts" page.
      final latest = state.valueOrNull ?? current;
      state = AsyncData(latest.copyWith(
        posts: [...latest.posts, ...listing.items],
        after: listing.after,
        loadingMore: false,
      ));
    } catch (_) {
      if (generation != _generation) return;
      final latest = state.valueOrNull ?? current;
      state = AsyncData(latest.copyWith(loadingMore: false, after: latest.after));
    }
  }
}

final feedControllerProvider =
    AsyncNotifierProviderFamily<FeedController, FeedState, String>(
        FeedController.new);
