import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics.dart';
import '../../core/providers.dart';
import '../../models/listing.dart';
import '../../models/post.dart';
import '../auth/auth_controller.dart';
import '../foryou/for_you_seeder.dart';
import '../history/history_store.dart';
import 'home_loading.dart' show redditHomeProgressProvider;
import 'home_status.dart';
import 'reddit_home_loader.dart';

/// Post ids (bare) Reddit offers "Show fewer posts like this" for.
final homeShowFewerProvider = StateProvider<Set<String>>((ref) => const {});

/// What Blend's Home source is doing, for the Blend header.
final blendStateProvider = StateProvider<BlendState?>((ref) => null);

/// One Blend read of your Reddit Home.
sealed class BlendResult {
  const BlendResult();
}

/// Full posts, in Reddit's order.
class BlendPosts extends BlendResult {
  const BlendPosts(this.posts);
  final List<Post> posts;
}

/// Home had nothing new this time (the page may still be setting up).
class BlendEmpty extends BlendResult {
  const BlendEmpty();
}

/// A network or page error: worth trying again on the next page.
class BlendFailed extends BlendResult {
  const BlendFailed();
}

/// No website sign-in, or it expired: Blend is For You until you sign in.
class BlendSignedOut extends BlendResult {
  const BlendSignedOut();
}

/// What Blend's Home source is doing, for the Blend header.
sealed class BlendState {
  const BlendState();
}

class BlendLoading extends BlendState {
  const BlendLoading();
}

/// [count] Reddit Home posts placed in this feed so far.
class BlendIncluded extends BlendState {
  const BlendIncluded(this.count);
  final int count;
}

class BlendUnavailable extends BlendState {
  const BlendUnavailable({required this.signedOut});
  final bool signedOut;
}

/// A Blend read in flight; [result] once it has arrived.
class BlendBatch {
  BlendBatch(Future<BlendResult> f) {
    future = f.then((r) => result = r);
  }
  late final Future<BlendResult> future;
  BlendResult? result;
  bool get isCompleted => result != null;
}

/// Experimental Reddit Home (headless WebView), falling back to For You.
/// Also Blend's Home source. One hidden page for the whole app.
class RedditHomeEngine {
  RedditHomeEngine(this._ref) {
    // The hidden page keeps running its scripts otherwise.
    _lifecycle = AppLifecycleListener(
      onHide: () => _loader?.pause(),
      onShow: () => _loader?.resume(),
    );
    // The other account's Home reads.
    _ref.listen(
        authControllerProvider.select((s) => s.valueOrNull?.username),
        (_, __) => cancelBlend());
  }

  final Ref _ref;
  late final AppLifecycleListener _lifecycle;
  RedditHomeLoader? _loader;

  final _upgrades = StreamController<List<Post>>.broadcast();

  /// Full posts for cards first shown from the page alone (the feed swaps
  /// them in by id, keeping its order).
  Stream<List<Post>> get upgrades => _upgrades.stream;

  // This load fell back to For You (Reddit Home couldn't be read); paging
  // continues with For You until the next refresh.
  bool _fellBack = false;
  int _loadGen = 0; // bumped by each first-page Home load
  int _homeEmpty = 0; // consecutive empty "more" batches from Reddit Home

  // The next batch, read ahead while the user scrolls the current one.
  Future<List<PagePost>>? _prefetch;
  Timer? _viewTimer;

  String get _user =>
      _ref.read(authControllerProvider).valueOrNull?.username ?? '';

  RedditHomeLoader get _l => _loader ??= RedditHomeLoader();

  set _status(HomeStatus? s) =>
      _ref.read(homeStatusProvider.notifier).state = s;

  void _setShowFewer(Set<String> ids) =>
      _ref.read(homeShowFewerProvider.notifier).state = ids;

  /// Home's page [after] (null = first), or For You's ([forYou]) once Home
  /// has fallen back to it.
  Future<Listing<Post>> page(String? after,
      Future<Listing<Post>> Function(String? after) forYou) {
    if (after == null) _fellBack = false;
    return _fellBack ? forYou(after) : _homePage(after, forYou);
  }

  Future<Listing<Post>> _homePage(String? after,
      Future<Listing<Post>> Function(String? after) forYou) async {
    final firstPage = after == null;
    final started = DateTime.now();
    try {
      final store = _ref.read(secureStoreProvider);
      if (await store.authMode != 'web') {
        throw StateError('Reddit Home needs website sign-in');
      }
      final cookie = await store.webCookie ?? '';
      final l = _l;
      final progress = _ref.read(redditHomeProgressProvider.notifier);
      if (firstPage) {
        _loadGen++;
        progress.state = 0;
        // The read-ahead of the old page would only hold the reload up.
        if (_prefetch != null) l.cancel();
        _prefetch = null;
      }
      List<PagePost> page;
      if (firstPage) {
        page = await l.next(
            restart: true,
            cookieHeader: cookie,
            onProgress: (n) => progress.state = n);
      } else {
        final ahead = _prefetch;
        _prefetch = null;
        List<PagePost>? read;
        try {
          read = await ahead;
        } catch (_) {}
        page = read ?? await l.next(restart: false, cookieHeader: cookie);
      }
      if (page.isEmpty) {
        if (firstPage) throw StateError('No posts found on Reddit Home');
        // One empty batch can just be the page still setting up its "load
        // more"; only two in a row end the feed.
        return Listing(
            items: const [], after: ++_homeEmpty >= 2 ? null : 'home');
      }
      _homeEmpty = 0;
      _setShowFewer(l.showFewerIds);
      // Cards straight from the page (no wait for the API); the full posts
      // (media, video, flair, NSFW) follow in the background.
      final cards = [for (final p in page) p.toPost()];
      _upgrade(page, firstPage, _loadGen);
      // Read the next batch ahead, so reaching the end doesn't wait.
      _prefetch = l.next(restart: false, cookieHeader: cookie);
      if (firstPage) {
        _trackLoad('ok', cards.length, started);
        _status = HomeLive(DateTime.now());
      }
      return Listing(items: cards, after: 'home');
    } catch (e) {
      if (!firstPage) rethrow; // a failed page keeps its cursor; retry
      // Reddit changed its page, the session expired, or the site refused:
      // show For You rather than an empty feed, and say so.
      _fellBack = true;
      final signedOut = e is HomeSignedOutException;
      _trackLoad(signedOut ? 'signin_expired' : 'fell_back', 0, started);
      _status = HomeFellBack(signedOut: signedOut);
      return forYou(null);
    }
  }

  // Blend reads keep going when a page stops waiting for one (the next page
  // takes it), so they're tracked here and dropped on refresh, when the feed
  // closes and on account changes; a result from before that ([_blendGen])
  // is thrown away.
  int _blendGen = 0;
  BlendBatch? _blendPending; // being read for the next page
  int _blendPlaced = 0; // Reddit Home posts placed in this feed

  /// Stops every Blend read (refresh, feed closed, account change).
  void cancelBlend() {
    _blendGen++;
    _loader?.cancel();
    _blendPending = null;
  }

  /// The Home read for this page: a fresh one on the first page (older reads
  /// are dropped), else the one already loading in the background.
  BlendBatch blendBatch(bool first) {
    if (first) cancelBlend();
    final pending = _blendPending;
    _blendPending = null;
    if (!first && pending != null) return pending;
    return BlendBatch(_blendCandidates(first, _blendGen));
  }

  /// The page stopped waiting for [batch]: the next page takes it.
  void blendKeep(BlendBatch batch) => _blendPending = batch;

  /// A batch arrived: start reading the next one now, so the next page
  /// doesn't wait.
  void blendPrefetch() =>
      _blendPending = BlendBatch(_blendCandidates(false, _blendGen));

  /// Blend's header: [placed] Reddit Home posts on this page ([first]: the
  /// count starts over), or [state] when it says something else.
  void blendPlaced(int placed, {required bool first, BlendState? state}) {
    _blendPlaced = (first ? 0 : _blendPlaced) + placed;
    _ref.read(blendStateProvider.notifier).state =
        state ?? BlendIncluded(_blendPlaced);
  }

  /// One read of your Reddit Home as full posts (Reddit's "why" kept as
  /// their reason), for For You to rank with everything else.
  Future<BlendResult> _blendCandidates(bool first, int gen) async {
    final user = _user;
    bool stale() => gen != _blendGen || _user != user;
    try {
      final store = _ref.read(secureStoreProvider);
      if (await store.authMode != 'web') return const BlendSignedOut();
      final cookie = await store.webCookie ?? '';
      final l = _l;
      final page = await l.next(restart: first, cookieHeader: cookie);
      if (stale()) return const BlendFailed(); // superseded
      if (page.isEmpty) return const BlendEmpty();
      _setShowFewer(l.showFewerIds);
      final full = await _ref
          .read(redditRepositoryProvider)
          .getPostsByIds([for (final p in page) p.id]);
      if (stale()) return const BlendFailed();
      return BlendPosts(_withReasons(full, page));
    } on HomeSignedOutException {
      return const BlendSignedOut();
    } catch (_) {
      return const BlendFailed();
    }
  }

  static List<Post> _withReasons(List<Post> full, List<PagePost> page) {
    final reasons = {
      for (final p in page) p.id.replaceFirst('t3_', ''): p.reason
    };
    return [
      for (final p in full)
        reasons[p.id] != null ? p.copyWith(feedReason: reasons[p.id]) : p
    ];
  }

  /// Anonymous: whether a Home load worked, how many posts and how long
  /// (coarse ranges).
  void _trackLoad(String outcome, int posts, DateTime started) {
    final ms = DateTime.now().difference(started).inMilliseconds;
    final seconds = ms < 2000
        ? '<2'
        : ms < 5000
            ? '2-5'
            : ms < 10000
                ? '5-10'
                : '10+';
    Analytics.track('home_loaded', {
      'outcome': outcome,
      'posts': posts == 0 ? '0' : (posts <= 9 ? '1-9' : '10+'),
      'seconds': seconds,
    });
  }

  /// Fetches the full posts for [page] and hands them to the feed.
  Future<void> _upgrade(List<PagePost> page, bool firstPage, int gen) async {
    // The account these cards belong to: a switch mid-request must not give
    // its posts (or its saved Home page) to the next account. Likewise a
    // newer Home load ([gen]) makes these cards old: an upgrade finishing
    // after it must not overwrite the newer cards or saved page.
    final user = _user;
    bool stale() => _user != user || gen != _loadGen;
    final repo = _ref.read(redditRepositoryProvider);
    // A failed fetch left cards without media (empty galleries); try again a
    // couple of times before leaving them as they are.
    List<Post>? full;
    for (final wait in const [0, 2000, 5000]) {
      await Future<void>.delayed(Duration(milliseconds: wait));
      try {
        full = await repo.getPostsByIds([for (final p in page) p.id]);
      } catch (_) {}
      if (full != null || stale()) break;
    }
    if (full == null || stale()) return;
    final posts = _withReasons(full, page);
    _upgrades.add(posts);
    if (firstPage && user.isNotEmpty) {
      saveForYouPage(user, posts, repo.rawPost, feed: 'home');
    }
  }

  /// The user is looking at [postId] in Ilay: follow it in the hidden page
  /// so Reddit's "seen" tracking matches (debounced; skipped while loading).
  void viewing(String postId) {
    final l = _loader;
    if (l == null) return;
    _viewTimer?.cancel();
    _viewTimer = Timer(const Duration(milliseconds: 800),
        () => l.scrollTo('t3_$postId'));
  }

  /// "Show fewer posts like this" on reddit.com for [post]. True if Reddit
  /// took it.
  Future<bool> showFewer(Post post) async {
    final l = _loader;
    if (l == null) return false;
    var ok = false;
    try {
      ok = await l.showFewer(post.fullname);
    } catch (_) {}
    _setShowFewer({..._ref.read(homeShowFewerProvider)}..remove(post.id));
    return ok;
  }

  /// The last Home page, minus posts opened since, while the fresh one
  /// loads.
  Future<Listing<Post>?> cachedFirstPage() async {
    final user = _user;
    if (user.isEmpty) return null;
    final posts = await loadForYouPage(user, _ref.read(historyIdsProvider),
        feed: 'home');
    return posts == null ? null : Listing(items: posts, after: null);
  }

  Future<DateTime?> cachedFirstPageTime() async =>
      _user.isEmpty ? null : savedPageTime(_user, feed: 'home');

  /// Closes the hidden browser (the feed went away).
  void close() {
    cancelBlend();
    _prefetch = null;
    _viewTimer?.cancel();
    _setShowFewer(const {});
    final l = _loader;
    _loader = null;
    l?.dispose();
  }

  void _dispose() {
    close();
    _lifecycle.dispose();
    _upgrades.close();
  }
}

final redditHomeEngineProvider = Provider<RedditHomeEngine>((ref) {
  final engine = RedditHomeEngine(ref);
  ref.onDispose(engine._dispose);
  return engine;
});
