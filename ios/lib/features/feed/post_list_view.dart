import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show RenderAbstractViewport, ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../core/network/reddit_client.dart';
import '../../core/providers.dart';
import '../../core/route_observer.dart';
import '../../core/theme/motion.dart';
import '../../core/widgets/error_view.dart';
import '../../core/widgets/image_decode.dart';
import '../../core/widgets/loading.dart';
import '../../core/widgets/toggles.dart';
import '../../data/reddit_repository.dart';
import '../../models/post.dart';
import '../auth/auth_controller.dart';
import '../auth/web_login_screen.dart';
import '../history/history_store.dart';
import '../../core/format.dart';
import '../reddit_home/home_loading.dart';
import '../reddit_home/home_status.dart';
import '../reddit_home/reddit_home_engine.dart';
import '../settings/settings_controller.dart';
import 'content_filters.dart';
import 'expiring_ids.dart';
import 'feed_controller.dart';
import 'post_card.dart';
import 'post_skeleton.dart';

/// Bumped to ask the frontpage feed to scroll to top (or refresh if already
/// there) — e.g. when the Posts tab is tapped while already selected.
final frontpageScrollSignalProvider = StateProvider<int>((ref) => 0);

/// Scrollable list of posts for a feed key ('' = frontpage, else subreddit).
/// [header] is rendered as the first scrolling item (e.g. a big title).
class PostListView extends ConsumerStatefulWidget {
  const PostListView(
      {super.key, required this.feedKey, this.header, this.topPadding = 0});
  final String feedKey;
  final Widget? header;
  final double topPadding; // room for a top bar floating over the list

  @override
  ConsumerState<PostListView> createState() => _PostListViewState();
}

/// Feed list side / bottom padding: room for the floating nav / FABs.
const feedPadding = EdgeInsets.fromLTRB(7, 0, 7, 130);

class _PostListViewState extends ConsumerState<PostListView>
    with RouteAware, WidgetsBindingObserver {
  // The Home loading deck was just showing: deal the first cards in.
  bool _dealHome = false;
  final _scroll = ScrollController();
  final _refreshKey = GlobalKey<RefreshBoxState>();
  final _prefetched = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(() {
      if (_scroll.position.pixels >=
          _scroll.position.maxScrollExtent - 600) {
        ref.read(feedControllerProvider(widget.feedKey).notifier).loadMore();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) appRouteObserver.subscribe(this, route);
  }

  /// Returning to the feed after a pushed route (e.g. a post) is popped, or
  /// to the app: the frontpage keeps its posts for Settings → Keep feed for,
  /// then loads anew; other feeds stage fresh posts behind a "New posts" pill
  /// once stale.
  void _onReturn() {
    final c = ref.read(feedControllerProvider(widget.feedKey).notifier);
    widget.feedKey.isEmpty ? c.refreshIfExpired() : c.refreshIfStale();
  }

  @override
  void didPopNext() => _onReturn();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only while this feed is the visible route.
    final current = ModalRoute.of(context)?.isCurrent ?? false;
    if (state == AppLifecycleState.resumed && current) _onReturn();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    appRouteObserver.unsubscribe(this);
    _scroll.dispose();
    super.dispose();
  }

  /// Warms the image cache for the cards just below the one being built —
  /// same URL and decode size as the card, so the card hits the cache.
  void _prefetchImages(List<Post> posts, int index, Settings settings) {
    // Mini cards only show small thumbnails; not worth warming.
    if (settings.postDisplay == PostDisplay.mini) return;
    final width = feedDecodeWidth(context);
    for (final p in posts.skip(index + 1).take(8)) {
      final url = feedImageUrl(p, settings);
      if (url == null || !_prefetched.add(url)) continue;
      precacheImage(
          ResizeImage(CachedNetworkImageProvider(url), width: width), context,
          onError: (_, __) {});
    }
  }

  /// "Sign in" on the Home strip: the website sign-in expired. Signs in
  /// again on reddit.com, then loads Home anew.
  Future<void> _signIn(FeedController notifier) async {
    final messenger = ScaffoldMessenger.of(context);
    final cookie = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const WebLoginScreen()));
    if (cookie == null || cookie.isEmpty) return;
    try {
      await ref
          .read(authControllerProvider.notifier)
          .loginWithWebSession(cookie);
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text("Couldn't sign in: ${friendlyError(e)}")));
      return;
    }
    await notifier.refresh();
  }

  void _scrollToTopOrRefresh() {
    if (!_scroll.hasClients) return;
    if (_scroll.offset > 20) {
      _scroll.animateTo(0,
          duration: const Duration(milliseconds: 320), curve: Curves.easeOut);
    } else {
      HapticFeedback.mediumImpact();
      // Drive the RefreshBox so the user sees the loading indicator while the
      // re-tap refresh runs (its onRefresh calls notifier.refresh()).
      _refreshKey.currentState?.show();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Frontpage only: respond to the "tap active tab" signal.
    if (widget.feedKey.isEmpty) {
      ref.listen<int>(frontpageScrollSignalProvider,
          (_, __) => _scrollToTopOrRefresh());
    }
    final async = ref.watch(feedControllerProvider(widget.feedKey));
    final notifier =
        ref.read(feedControllerProvider(widget.feedKey).notifier);
    final hasPending = async.valueOrNull?.hasPending ?? false;
    final homeMode = widget.feedKey.isEmpty &&
        ref.watch(settingsControllerProvider
            .select((s) => s.redditHomeAllowed && s.redditHomeFeed));
    final homeStatus = homeMode ? ref.watch(homeStatusProvider) : null;
    // Blend: For You ranking over your Reddit Home too.
    final blendMode = widget.feedKey.isEmpty &&
        ref.watch(settingsControllerProvider.select(
            (s) => s.forYouFeed && s.blendHome && s.redditHomeAllowed));
    // Home and For You load behind the shuffling deck.
    final deckMode = widget.feedKey.isEmpty &&
        (homeMode ||
            ref.watch(settingsControllerProvider.select((s) => s.forYouFeed)));

    final forYouFeed = widget.feedKey.isEmpty &&
        ref.watch(settingsControllerProvider.select((s) => s.forYouFeed));
    final homeAllowed =
        ref.watch(settingsControllerProvider.select((s) => s.redditHomeAllowed));
    final chips = _FeedChips(
      // Rebuilt with the list: it keeps its scroll position through a reload.
      key: PageStorageKey('feedChips_${widget.feedKey}'),
      sort: notifier.sort,
      time: notifier.time,
      onPick: notifier.changeSort,
      isFrontpage: widget.feedKey.isEmpty,
      forYou: forYouFeed,
      onForYou: notifier.selectForYou,
      redditHome: homeMode,
      onRedditHome: homeAllowed ? notifier.selectRedditHome : null,
      blend: blendMode,
      onBlend: homeAllowed ? notifier.selectBlend : null,
    );

    final listPadding = feedPadding.copyWith(top: widget.topPadding);
    final refreshable = RefreshBox(
      key: _refreshKey,
      edgeOffset: widget.topPadding,
      onRefresh: () {
        HapticFeedback.mediumImpact();
        return notifier.refresh();
      },
      child: async.when(
        loading: () {
          // Home and For You: the shuffling deck with a live count of posts
          // found; its cards are then dealt into the feed.
          if (deckMode) {
            _dealHome = true;
            return ListView(
              padding: listPadding,
              children: [
                if (widget.header != null) widget.header!,
                chips,
                const SizedBox(height: 68),
                HomeLoadingDeck(forYou: !homeMode),
              ],
            );
          }
          return ListView(
            padding: listPadding,
            children: [
              if (widget.header != null) widget.header!,
              chips,
              for (var i = 0; i < 5; i++)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: PostSkeleton(),
                ),
            ],
          );
        },
        error: (e, _) => ListView(
          padding: EdgeInsets.only(top: widget.topPadding),
          children: [
            if (widget.header != null) widget.header!,
            SizedBox(
              height: 360,
              // A quarantined or gated subreddit: opt in right here.
              child: FutureBuilder<bool>(
                future: e is RedditApiException &&
                        !widget.feedKey.startsWith('m::')
                    ? ref.read(redditRepositoryProvider).canOptIn(e.reason)
                    : Future.value(false),
                builder: (context, snap) => snap.data != true
                    ? ErrorView(message: e, onRetry: notifier.refresh)
                    : ErrorView(
                        message: e,
                        retryLabel: 'View anyway',
                        onRetry: () async {
                          try {
                            await ref
                                .read(redditRepositoryProvider)
                                .optInSubreddit(widget.feedKey,
                                    (e as RedditApiException).reason!);
                            await notifier.refresh();
                          } catch (err) {
                            if (context.mounted) {
                              showActionError(context, 'opt in', err);
                            }
                          }
                        },
                      ),
              ),
            ),
          ],
        ),
        data: (state) {
          final settings = ref.watch(settingsControllerProvider);
          final homeOn = settings.redditHomeAllowed && settings.redditHomeFeed;
          var posts = state.posts;
          // Auto-hide already-read items in the For You feed (live: rebuilds
          // when history changes). Not in Reddit Home: its recommended posts
          // carry Reddit's reason too, and opening one made it vanish on
          // return.
          if (settings.autoHideReadForYou && !homeOn) {
            final seen = ref.watch(historyIdsProvider);
            posts = posts
                .where((p) => !(p.feedReason != null && seen.contains(p.id)))
                .toList();
          }
          // Posts you hid (Hide / swipe-to-hide), for Settings → Hide posts
          // for.
          final hiddenIds = ref.watch(hiddenPostsProvider);
          if (hiddenIds.isNotEmpty) {
            posts = posts.where((p) => !hiddenIds.contains(p.id)).toList();
          }
          // Home / For You: posts dismissed with the "Dismiss" swipe (kept a
          // day).
          final dismissible = widget.feedKey.isEmpty && deckMode;
          if (dismissible) {
            final dismissed = ref.watch(dismissedPostsProvider);
            if (dismissed.isNotEmpty) {
              posts = posts.where((p) => !dismissed.contains(p.id)).toList();
            }
          }
          // Subreddits hidden for 7 days: anywhere on the front page (Home,
          // For You and Best / Hot / New).
          final frontpage = widget.feedKey.isEmpty;
          if (frontpage) {
            final subs = ref.watch(hiddenHomeSubsProvider);
            if (subs.isNotEmpty) {
              posts = posts
                  .where((p) => !subs.contains(p.subreddit.toLowerCase()))
                  .toList();
            }
          }
          // User content filters (keywords / domains / flairs / subreddits).
          final filters = ref.watch(contentFiltersProvider);
          if (!filters.isEmpty) {
            // A subreddit feed still shows that subreddit's own posts.
            final viewing = widget.feedKey.isEmpty ||
                    widget.feedKey.startsWith('m::')
                ? null
                : widget.feedKey;
            posts = posts
                .where((p) => !filters.hides(p, viewingSubreddit: viewing))
                .toList();
          }
          // A page boundary can repeat a post that moved up meanwhile; the
          // list needs unique keys.
          final ids = <String>{};
          posts = posts.where((p) => ids.add(p.id)).toList();
          final hidden = state.posts.length - posts.length;
          // Paging is triggered by building post rows near the end. If the
          // filters hide (almost) everything loaded, there are no rows to
          // build and the list can't scroll, so the feed stalled blank. Keep
          // fetching instead, up to a bound in case nothing ever matches.
          if (posts.length < 10 &&
              state.hasMore &&
              !state.loadingMore &&
              state.posts.length < 250) {
            WidgetsBinding.instance
                .addPostFrameCallback((_) => notifier.loadMore());
          }
          final itemCount = 1 + posts.length + 1; // sortbar + posts + footer
          return ListView.separated(
            controller: _scroll,
            // Build cards about a screen ahead (the default is 250px), so
            // they're laid out and their images decoding before they appear.
            scrollCacheExtent: const ScrollCacheExtent.pixels(1200),
            padding: listPadding,
            itemCount: (widget.header != null ? 1 : 0) + itemCount,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, rawIndex) {
              var index = rawIndex;
              if (widget.header != null) {
                if (index == 0) return widget.header!;
                index -= 1;
              }
              if (index == 0) {
                // Not your live Home: say what this is instead (until the
                // next load works).
                final status = homeStatus;
                if (status is HomeSaved || status is HomeFellBack) {
                  return Column(children: [
                    chips,
                    _HomeStatusStrip(
                        status: status!,
                        onRetry: notifier.refresh,
                        onSignIn: () => _signIn(notifier)),
                  ]);
                }
                return chips;
              }
              index -= 1;
              if (index < posts.length) {
                _prefetchImages(posts, index, settings);
                // Page early, 10 cards from the end: a fast flick covers
                // several cards in less time than a page takes to arrive.
                // After the frame, since loadMore updates provider state.
                if (index >= posts.length - 10 && state.hasMore) {
                  WidgetsBinding.instance
                      .addPostFrameCallback((_) => notifier.loadMore());
                }
                Widget card = PostCard(
                    key: ValueKey(posts[index].id),
                    post: posts[index],
                    dismissible: dismissible,
                    frontpage: frontpage);
                // Home (and Blend's Home posts): follow the card on screen in
                // the hidden reddit.com page, so Reddit's own "seen" tracking
                // matches what was actually read and the next load brings
                // new posts. (Cards not on its page are ignored there.)
                if (homeMode || blendMode) {
                  final id = posts[index].id;
                  card = VisibilityDetector(
                    key: Key('home_seen_$id'),
                    onVisibilityChanged: (info) {
                      if (info.visibleFraction >= 0.6) {
                        ref.read(redditHomeEngineProvider).viewing(id);
                      }
                    },
                    child: card,
                  );
                }
                if (deckMode && index < 3) {
                  // The first cards after the loading deck are dealt in.
                  final deal = _dealHome;
                  if (deal && index == 2) {
                    WidgetsBinding.instance
                        .addPostFrameCallback((_) => _dealHome = false);
                  }
                  return DealIn(index: index, animate: deal, child: card);
                }
                return card;
              }
              // footer
              final muted = TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    state.loadingMore
                        ? const Loading()
                        : state.hasMore
                            ? const SizedBox.shrink()
                            : Text('— end —', style: muted),
                    if (hidden > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                            '$hidden ${hidden == 1 ? 'post' : 'posts'} hidden',
                            style: muted.copyWith(fontSize: 12.5)),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );

    return Stack(
      children: [
        refreshable,
        if (hasPending)
          Positioned(
            top: 8 + widget.topPadding,
            left: 0,
            right: 0,
            child: Center(
              child: _NewPostsPill(
                onTap: () {
                  notifier.applyPending();
                  if (_scroll.hasClients) {
                    _scroll.animateTo(0,
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeOut);
                  }
                },
              ),
            ),
          ),
      ],
    );
  }
}

/// "Saved Home, from 2h ago · Refresh" / "Home couldn't load · showing For
/// You · Retry".
class _HomeStatusStrip extends StatelessWidget {
  const _HomeStatusStrip(
      {required this.status, required this.onRetry, required this.onSignIn});
  final HomeStatus status;
  final VoidCallback onRetry;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = status;
    final (IconData icon, String text) = switch (s) {
      HomeSaved(:final at) => (
          Icons.history_rounded,
          'Saved Home, from ${_agoPhrase(at)}'
        ),
      HomeFellBack(:final signedOut) => (
          Icons.cloud_off_rounded,
          signedOut
              ? 'Website sign-in expired · showing For You'
              : "Home couldn't load · showing For You"
        ),
      HomeLive() => (Icons.home_rounded, ''),
    };
    final signIn = s is HomeFellBack && s.signedOut;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.fromLTRB(14, 2, 4, 2),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: cs.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                maxLines: 2,
                style:
                    TextStyle(fontSize: 13, color: cs.onSecondaryContainer)),
          ),
          TextButton(
            onPressed: signIn ? onSignIn : onRetry,
            child: Text(signIn
                ? 'Sign in'
                : (s is HomeSaved ? 'Refresh' : 'Retry')),
          ),
        ],
      ),
    );
  }

  static String _agoPhrase(DateTime at) {
    final t = timeAgo(at.toUtc());
    return t == 'now' ? 'just now' : '$t ago';
  }
}

/// Tappable pill shown when a fresh feed page is staged after returning to a
/// stale feed — applies it and scrolls to top.
class _NewPostsPill extends StatelessWidget {
  const _NewPostsPill({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.primary,
      elevation: 3,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.arrow_upward_rounded, size: 16, color: cs.onPrimary),
              const SizedBox(width: 6),
              Text('New posts',
                  style: TextStyle(
                      color: cs.onPrimary, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The profile's sort: a button that opens the list (no room beside its tabs
/// for [_FeedChips]).
class SortBar extends StatelessWidget {
  const SortBar({
    super.key,
    required this.sort,
    required this.time,
    required this.onPick,
    required this.sorts,
  });
  final PostSort sort;
  final TopTime time;
  final void Function(PostSort, {TopTime? time}) onPick;
  final List<PostSort> sorts;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Row(
        children: [
          ActionChip(
            avatar: const Icon(Icons.sort_rounded, size: 18),
            label: Text(sort.needsTime
                ? '${sort.label} · ${time.label}'
                : sort.label),
            shape: const StadiumBorder(),
            side: BorderSide.none,
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerHigh,
            onPressed: () => _showSortSheet(context),
          ),
        ],
      ),
    );
  }

  void _showSortSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      sheetAnimationStyle: sheetMotion,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in sorts)
              ListTile(
                leading: Icon(_iconFor(s)),
                title: Text(s.label),
                trailing: s == sort ? const Icon(Icons.check_rounded) : null,
                onTap: () async {
                  Navigator.pop(ctx);
                  if (s.needsTime) {
                    final t = await pickTopTime(context, time);
                    if (t != null) onPick(s, time: t);
                  } else {
                    onPick(s);
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(PostSort s) => switch (s) {
        PostSort.best => Icons.star_rounded,
        PostSort.hot => Icons.local_fire_department_rounded,
        PostSort.newest => Icons.schedule_rounded,
        PostSort.top => Icons.leaderboard_rounded,
        PostSort.rising => Icons.trending_up_rounded,
      };
}

Future<TopTime?> pickTopTime(BuildContext context, TopTime time) =>
    showModalBottomSheet<TopTime>(
      context: context,
      sheetAnimationStyle: sheetMotion,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final t in TopTime.values)
              ListTile(
                title: Text(t.label),
                trailing: t == time ? const Icon(Icons.check_rounded) : null,
                onTap: () => Navigator.pop(ctx, t),
              ),
          ],
        ),
      ),
    );

enum _FeedMode { forYou, blend, home }

/// A feed's sorts, and on the frontpage its For You / Blend / Home feeds, as
/// Material 3 Expressive filter chips (#53): one tap, and the tapped chip
/// morphs into a pill with a check. Top asks for its time range first. Picking
/// swaps the list for its loading state, which rebuilds this row, so the pick
/// shows for a moment before it's applied, or the morph would never be seen.
class _FeedChips extends StatefulWidget {
  const _FeedChips({
    super.key,
    required this.sort,
    required this.time,
    required this.onPick,
    required this.isFrontpage,
    required this.forYou,
    required this.onForYou,
    required this.redditHome,
    required this.onRedditHome,
    required this.blend,
    required this.onBlend,
  });
  final PostSort sort;
  final TopTime time;
  final void Function(PostSort, {TopTime? time}) onPick;
  final bool isFrontpage;
  final bool forYou;
  final VoidCallback onForYou;
  final bool redditHome;
  final VoidCallback? onRedditHome; // null unless enabled in Settings
  final bool blend;
  final VoidCallback? onBlend; // null unless Reddit Home is enabled

  @override
  State<_FeedChips> createState() => _FeedChipsState();
}

class _FeedChipsState extends State<_FeedChips> {
  final _scroll = ScrollController();
  final _keys = <Object, GlobalKey>{};
  Object? _picked; // a _FeedMode or a PostSort
  TopTime? _pickedTime;

  Object get _current => widget.redditHome
      ? _FeedMode.home
      : widget.blend
          ? _FeedMode.blend
          : widget.forYou
              ? _FeedMode.forYou
              : widget.sort;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _centerSelected());
  }

  @override
  void didUpdateWidget(_FeedChips old) {
    super.didUpdateWidget(old);
    WidgetsBinding.instance.addPostFrameCallback((_) => _centerSelected());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  // Keep the selected chip in view: Home's row can start with it off screen.
  // Not Scrollable.ensureVisible: that would scroll the feed around it too.
  void _centerSelected() {
    final box = _keys[_current]?.currentContext?.findRenderObject();
    if (!mounted || box == null || !_scroll.hasClients) return;
    final to = RenderAbstractViewport.of(box)
        .getOffsetToReveal(box, 0.5)
        .offset
        .clamp(0.0, _scroll.position.maxScrollExtent);
    if ((to - _scroll.offset).abs() < 1) return;
    _scroll.animateTo(to,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  void _choose(Object choice, VoidCallback action, {TopTime? time}) {
    setState(() {
      _picked = choice;
      _pickedTime = time;
    });
    Future.delayed(const Duration(milliseconds: 240), () {
      action();
      if (mounted) {
        setState(() {
          _picked = null;
          _pickedTime = null;
        });
      }
    });
  }

  void _tap(Object chip) async {
    if (_picked != null) return;
    if (chip is PostSort && chip.needsTime) {
      final t = await pickTopTime(context, widget.time);
      if (t != null && (chip != _current || t != widget.time)) {
        _choose(chip, () => widget.onPick(chip, time: t), time: t);
      }
    } else if (chip != _current) {
      _choose(
          chip,
          switch (chip) {
            _FeedMode.forYou => widget.onForYou,
            _FeedMode.blend => () => widget.onBlend?.call(),
            _FeedMode.home => () => widget.onRedditHome?.call(),
            _ => () => widget.onPick(chip as PostSort),
          });
    }
  }

  @override
  Widget build(BuildContext context) {
    final shown = _picked ?? _current;
    final chips = <Object>[
      if (widget.isFrontpage) ...[
        _FeedMode.forYou,
        if (widget.onBlend != null) _FeedMode.blend,
        if (widget.onRedditHome != null) _FeedMode.home,
      ],
      ...PostSort.values,
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          children: [
            for (final chip in chips)
              Padding(
                key: _keys.putIfAbsent(chip, GlobalKey.new),
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: _FeedChip(
                  label: switch (chip) {
                    _FeedMode.forYou => 'For You',
                    _FeedMode.blend => 'Blend · Beta',
                    _FeedMode.home => 'Home',
                    final PostSort s when s.needsTime && s == shown =>
                      '${s.label} · ${(_pickedTime ?? widget.time).label}',
                    final PostSort s => s.label,
                    _ => '',
                  },
                  selected: chip == shown,
                  onTap: () => _tap(chip),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FeedChip extends StatelessWidget {
  const _FeedChip(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = selected ? cs.onSecondaryContainer : cs.onSurface;
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      child: ShapeButton(
        color: selected ? cs.secondaryContainer : cs.surfaceContainerHigh,
        shape: (_) => BorderRadius.circular(selected ? 18 : 8),
        onTap: onTap,
        child: AnimatedSize(
          duration: Motion.fastSpatial.duration,
          curve: Motion.fastSpatial,
          alignment: AlignmentDirectional.centerStart,
          child: Container(
            height: 36,
            // The tick sits closer to the edge than the text does (#57).
            padding: EdgeInsetsDirectional.only(
                start: selected ? 8 : 14, end: 14),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected) ...[
                  Icon(Icons.check_rounded, size: 18, color: fg),
                  const SizedBox(width: 8),
                ],
                Text(label,
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(color: fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
