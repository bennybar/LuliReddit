import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/reddit_repository.dart';
import '../../models/listing.dart';
import '../../models/post.dart';
import '../history/history_store.dart';
import '../history/interest_store.dart';
import '../settings/settings_controller.dart';

class FeedState {
  const FeedState({
    required this.posts,
    required this.sort,
    required this.time,
    this.after,
    this.loadingMore = false,
  });

  final List<Post> posts;
  final PostSort sort;
  final TopTime time;
  final String? after;
  final bool loadingMore;

  bool get hasMore => after != null && after!.isNotEmpty;

  FeedState copyWith({
    List<Post>? posts,
    PostSort? sort,
    TopTime? time,
    String? after,
    bool? loadingMore,
  }) =>
      FeedState(
        posts: posts ?? this.posts,
        sort: sort ?? this.sort,
        time: time ?? this.time,
        after: after,
        loadingMore: loadingMore ?? this.loadingMore,
      );
}

/// Feed for the frontpage (key == '') or a subreddit (key == name).
class FeedController extends FamilyAsyncNotifier<FeedState, String> {
  String? get _subreddit => arg.isEmpty ? null : arg;
  RedditRepository get _repo => ref.read(redditRepositoryProvider);

  PostSort? _sort;
  TopTime _time = TopTime.day;
  bool _initialized = false;
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

  Future<Listing<Post>> _fetch({String? after}) {
    if (_forYou) {
      final history = ref.read(historyControllerProvider);
      final kw = ref.read(keywordStoreProvider.notifier);
      return _repo.getForYouFeed(
        interest: ref.read(interestStoreProvider),
        muted: ref.read(mutedSubsProvider),
        seen: {for (final e in history) e.id},
        impressions: ref.read(impressionStoreProvider),
        titleScore: kw.scoreTitle,
        titleKeyword: kw.topKeywordIn,
        cursors: after, // null = first page; else the encoded cursor bundle
        excludeIds: after == null
            ? const {}
            : {
                for (final p in state.valueOrNull?.posts ?? const <Post>[])
                  p.id
              },
      );
    }
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

  @override
  Future<FeedState> build(String arg) async {
    if (!_initialized) {
      _sort = ref.read(settingsControllerProvider).defaultSort;
      _initialized = true;
    }
    // Retry once: a cold-start request can fail while the token is being
    // refreshed for the first time.
    Listing<Post> listing;
    try {
      listing = await _fetch();
    } catch (_) {
      listing = await _fetch();
    }
    _lastLoaded = DateTime.now();
    return FeedState(
      posts: listing.items,
      sort: _sort!,
      time: _time,
      after: listing.after,
    );
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

  /// Silently reloads the feed only if the data is older than [maxAge] — used
  /// when returning to the feed after viewing a post, so fresh posts appear
  /// without a jarring spinner or losing the user's place on a quick in/out.
  Future<void> refreshIfStale(
      [Duration maxAge = const Duration(minutes: 5)]) async {
    if (state.isLoading) return;
    if (DateTime.now().difference(_lastLoaded) < maxAge) return;
    await refresh();
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || current.loadingMore) return;
    state = AsyncData(current.copyWith(loadingMore: true, after: current.after));
    try {
      final listing = await _fetch(after: current.after);
      state = AsyncData(current.copyWith(
        posts: [...current.posts, ...listing.items],
        after: listing.after,
        loadingMore: false,
      ));
    } catch (_) {
      state = AsyncData(current.copyWith(loadingMore: false, after: current.after));
    }
  }
}

final feedControllerProvider =
    AsyncNotifierProviderFamily<FeedController, FeedState, String>(
        FeedController.new);
