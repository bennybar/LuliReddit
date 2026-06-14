import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/route_observer.dart';
import '../../core/widgets/error_view.dart';
import '../../data/reddit_repository.dart';
import '../history/history_store.dart';
import '../settings/settings_controller.dart';
import 'feed_controller.dart';
import 'post_card.dart';
import 'post_skeleton.dart';

/// Bumped to ask the frontpage feed to scroll to top (or refresh if already
/// there) — e.g. when the Posts tab is tapped while already selected.
final frontpageScrollSignalProvider = StateProvider<int>((ref) => 0);

/// Scrollable list of posts for a feed key ('' = frontpage, else subreddit).
/// [header] is rendered as the first scrolling item (e.g. a big title).
class PostListView extends ConsumerStatefulWidget {
  const PostListView({super.key, required this.feedKey, this.header});
  final String feedKey;
  final Widget? header;

  @override
  ConsumerState<PostListView> createState() => _PostListViewState();
}

class _PostListViewState extends ConsumerState<PostListView> with RouteAware {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
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

  /// Returning to the feed after a pushed route (e.g. a post) is popped:
  /// pull in fresh posts if the feed has gone stale.
  @override
  void didPopNext() {
    ref.read(feedControllerProvider(widget.feedKey).notifier).refreshIfStale();
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToTopOrRefresh() {
    if (!_scroll.hasClients) return;
    if (_scroll.offset > 20) {
      _scroll.animateTo(0,
          duration: const Duration(milliseconds: 320), curve: Curves.easeOut);
    } else {
      HapticFeedback.mediumImpact();
      ref.read(feedControllerProvider(widget.feedKey).notifier).refresh();
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

    return RefreshIndicator(
      onRefresh: () {
        HapticFeedback.mediumImpact();
        return notifier.refresh();
      },
      child: async.when(
        loading: () => ListView(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 130),
          children: [
            if (widget.header != null) widget.header!,
            const SizedBox(height: 8),
            for (var i = 0; i < 5; i++)
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: PostSkeleton(),
              ),
          ],
        ),
        error: (e, _) => ListView(
          children: [
            if (widget.header != null) widget.header!,
            SizedBox(
              height: 360,
              child: ErrorView(message: e, onRetry: notifier.refresh),
            ),
          ],
        ),
        data: (state) {
          final settings = ref.watch(settingsControllerProvider);
          var posts = state.posts;
          // Auto-hide already-read items in the For You feed (live: rebuilds
          // when history changes).
          if (settings.autoHideReadForYou) {
            final seen = {for (final e in ref.watch(historyControllerProvider)) e.id};
            posts = posts
                .where((p) => !(p.feedReason != null && seen.contains(p.id)))
                .toList();
          }
          final itemCount = 1 + posts.length + 1; // sortbar + posts + footer
          return ListView.separated(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 130),
            itemCount: (widget.header != null ? 1 : 0) + itemCount,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, rawIndex) {
              var index = rawIndex;
              if (widget.header != null) {
                if (index == 0) return widget.header!;
                index -= 1;
              }
              if (index == 0) {
                return _SortBar(
                  sort: state.sort,
                  time: state.time,
                  onPick: notifier.changeSort,
                  isFrontpage: widget.feedKey.isEmpty,
                  forYou: settings.forYouFeed && widget.feedKey.isEmpty,
                  onForYou: notifier.selectForYou,
                );
              }
              index -= 1;
              if (index < posts.length) {
                return PostCard(post: posts[index]);
              }
              // footer
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: state.loadingMore
                      ? const CircularProgressIndicator()
                      : state.hasMore
                          ? const SizedBox.shrink()
                          : Text('— end —',
                              style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _SortBar extends StatelessWidget {
  const _SortBar({
    required this.sort,
    required this.time,
    required this.onPick,
    this.isFrontpage = false,
    this.forYou = false,
    this.onForYou,
  });
  final PostSort sort;
  final TopTime time;
  final void Function(PostSort, {TopTime? time}) onPick;
  final bool isFrontpage;
  final bool forYou;
  final VoidCallback? onForYou;

  @override
  Widget build(BuildContext context) {
    final label = forYou
        ? 'For You · Beta'
        : (sort.needsTime ? '${sort.label} · ${time.label}' : sort.label);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Row(
        children: [
          ActionChip(
            avatar: Icon(
                forYou ? Icons.auto_awesome_rounded : Icons.sort_rounded,
                size: 18),
            label: Text(label),
            onPressed: () => _showSortSheet(context),
          ),
        ],
      ),
    );
  }

  void _showSortSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isFrontpage && onForYou != null)
              ListTile(
                leading: const Icon(Icons.auto_awesome_rounded),
                title: const Text('For You'),
                subtitle: const Text('Personalized · Beta'),
                trailing: forYou ? const Icon(Icons.check_rounded) : null,
                onTap: () {
                  Navigator.pop(ctx);
                  onForYou!();
                },
              ),
            for (final s in PostSort.values)
              ListTile(
                leading: Icon(_iconFor(s)),
                title: Text(s.label),
                trailing:
                    (!forYou && s == sort) ? const Icon(Icons.check_rounded) : null,
                onTap: () {
                  Navigator.pop(ctx);
                  if (s.needsTime) {
                    _showTimeSheet(context, s);
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

  void _showTimeSheet(BuildContext context, PostSort s) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final t in TopTime.values)
              ListTile(
                title: Text(t.label),
                trailing: t == time ? const Icon(Icons.check_rounded) : null,
                onTap: () {
                  Navigator.pop(ctx);
                  onPick(s, time: t);
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
