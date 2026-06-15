import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../models/subreddit.dart';
import '../home/tab_signals.dart';

final subscribedSubredditsProvider =
    FutureProvider.autoDispose<List<Subreddit>>((ref) async {
  return ref.watch(redditRepositoryProvider).getSubscribedSubreddits();
});

class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final subs = ref.watch(subscribedSubredditsProvider);

    // Re-tapping the Explore tab scrolls back to top.
    ref.listen<int>(tabReselectProvider(1), (_, __) {
      if (_scroll.hasClients) {
        _scroll.animateTo(0,
            duration: const Duration(milliseconds: 320), curve: Curves.easeOut);
      }
    });

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(subscribedSubredditsProvider),
          child: CustomScrollView(
            controller: _scroll,
            slivers: [
              // Search entry
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Material(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(28),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(28),
                      onTap: () => context.push('/search'),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 14),
                        child: Row(
                          children: [
                            Icon(Icons.search_rounded,
                                color: cs.onSurfaceVariant),
                            const SizedBox(width: 12),
                            Text('Search communities & posts',
                                style: TextStyle(color: cs.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text('Explore',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800)),
                ),
              ),
              ...subs.when(
                loading: () => const [
                  SliverToBoxAdapter(
                      child: Padding(
                          padding: EdgeInsets.all(40),
                          child: Center(child: CircularProgressIndicator()))),
                ],
                error: (e, _) => [
                  SliverToBoxAdapter(
                      child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Center(
                              child: Text('Could not load communities: $e')))),
                ],
                data: (list) {
                  final favs = list.where((s) => s.userHasFavorited).toList();
                  final rest = list.where((s) => !s.userHasFavorited).toList();
                  return [
                    if (favs.isNotEmpty) ...[
                      _sectionHeader(context, 'Favorites'),
                      _subList(ref, favs),
                    ],
                    _sectionHeader(context,
                        favs.isEmpty ? 'Subscriptions' : 'Communities'),
                    if (rest.isEmpty && favs.isEmpty)
                      const SliverToBoxAdapter(
                          child: Padding(
                              padding: EdgeInsets.all(32),
                              child: Center(
                                  child: Text('You have no subscriptions yet'))))
                    else
                      _subList(ref, rest),
                  ];
                },
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 130)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) =>
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
          child: Text(title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w700)),
        ),
      );

  Widget _subList(WidgetRef ref, List<Subreddit> subs) => SliverList.builder(
        itemCount: subs.length,
        itemBuilder: (context, i) => _SubredditRow(subreddit: subs[i]),
      );
}

class _SubredditRow extends ConsumerWidget {
  const _SubredditRow({required this.subreddit});
  final Subreddit subreddit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final s = subreddit;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: cs.secondaryContainer,
        foregroundColor: cs.onSecondaryContainer,
        backgroundImage:
            s.iconUrl != null ? CachedNetworkImageProvider(s.iconUrl!) : null,
        child: s.iconUrl == null
            ? Text(s.name.isNotEmpty ? s.name[0].toUpperCase() : '?')
            : null,
      ),
      title: Text(s.namePrefixed),
      subtitle: Text('${compactNumber(s.subscribers)} members'),
      trailing: IconButton(
        tooltip: s.userHasFavorited ? 'Unfavorite' : 'Favorite',
        icon: Icon(
          s.userHasFavorited ? Icons.star_rounded : Icons.star_border_rounded,
          color: s.userHasFavorited ? cs.primary : cs.onSurfaceVariant,
        ),
        onPressed: () async {
          await ref
              .read(redditRepositoryProvider)
              .setSubredditFavorite(s.name, !s.userHasFavorited);
          ref.invalidate(subscribedSubredditsProvider);
        },
      ),
      onTap: () => context.push('/r/${s.name}'),
    );
  }
}
