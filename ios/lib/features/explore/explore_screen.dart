import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/widgets/connected_choice.dart';
import '../../core/widgets/error_view.dart';
import '../../core/widgets/loading.dart';
import '../../core/widgets/pick_one_menu.dart';
import '../../core/widgets/toggles.dart';
import '../../models/subreddit.dart';
import '../auth/auth_controller.dart';
import '../feed/post_card.dart' show LetterAvatar;
import '../history/history_store.dart';
import '../home/account_tab.dart' show SignInPrompt, createMulti;
import '../home/tab_menu.dart';
import '../home/tab_signals.dart';
import '../multireddit/multireddit_providers.dart';

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
  String _query = '';
  bool _favOnly = false;
  String _sort = 'default'; // default | name | subscribers

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final subs = ref.watch(subscribedSubredditsProvider);
    final sideBar = SideBarScope.of(context) != null;

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
        child: RefreshBox(
          onRefresh: () async {
            ref.read(redditRepositoryProvider).clearSubsCache(); // force
            ref.invalidate(subscribedSubredditsProvider);
            ref.invalidate(myMultiredditsProvider);
            try {
              await ref.read(subscribedSubredditsProvider.future);
            } catch (_) {/* shown by the list */}
          },
          child: CustomScrollView(
            controller: _scroll,
            slivers: [
              // Search entry
              SliverToBoxAdapter(
                child: Padding(
                  // With the ☰ here: the same spot as on the other tabs.
                  padding: EdgeInsets.fromLTRB(
                      sideBar ? 4 : 16, sideBar ? 6 : 12, 16, 4),
                  child: Row(children: [
                  const SideBarButton(),
                  Expanded(child: Material(
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
                  )),
                  ]),
                ),
              ),
              SliverToBoxAdapter(
                // A connected pair: round outer corners, tight inner ones.
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Row(
                    children: [
                      Expanded(
                          child: _connectedOutlined(
                              0,
                              Icons.local_fire_department_rounded,
                              'Popular',
                              () => context.push('/r/popular'))),
                      const SizedBox(width: connectedGap),
                      Expanded(
                          child: _connectedOutlined(1, Icons.public_rounded,
                              'All', () => context.push('/r/all'))),
                    ],
                  ),
                ),
              ),
              // Custom feeds (multireddits), with "New feed" at the end
              // (signed in).
              SliverToBoxAdapter(child: _customFeeds(context, cs)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
                  child: Row(children: [
                    Expanded(
                      child: Text('Explore',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800)),
                    ),
                    const SettingsButton(),
                  ]),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          onChanged: (v) => setState(() => _query = v),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: 'Filter your communities',
                            prefixIcon: const Icon(Icons.filter_list_rounded),
                            filled: true,
                            fillColor: cs.surfaceContainerHigh,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      ToggleIcon(
                        checked: _favOnly,
                        onChanged: (v) => setState(() => _favOnly = v),
                        on: Icons.star_rounded,
                        off: Icons.star_border_rounded,
                        description: 'Favorites only',
                        tonal: true,
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Sort',
                        icon: const Icon(Icons.sort_rounded),
                        initialValue: _sort,
                        onSelected: (v) => setState(() => _sort = v),
                        itemBuilder: (_) => pickOneMenu(const [
                          ('default', 'Default'),
                          ('name', 'Name A–Z'),
                          ('subscribers', 'Most subscribers'),
                        ], _sort),
                      ),
                    ],
                  ),
                ),
              ),
              ...subs.when(
                loading: () => const [
                  SliverToBoxAdapter(
                      child: Padding(
                          padding: EdgeInsets.all(40),
                          child: Center(child: Loading()))),
                ],
                error: (e, _) => [
                  if (ref.watch(authControllerProvider).valueOrNull?.anonymous ??
                      false)
                    const SliverToBoxAdapter(
                      child: SignInPrompt(
                          message: 'Sign in to see the communities you\'ve '
                              'joined. You can still search and open any '
                              'subreddit.'),
                    )
                  else
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          const Text("Couldn't load your communities.",
                              textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: () =>
                                ref.invalidate(subscribedSubredditsProvider),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                data: (list) {
                  final q = _query.trim().toLowerCase();
                  final active = q.isNotEmpty || _favOnly || _sort != 'default';

                  if (active) {
                    // Filtered/sorted flat view.
                    var working = [
                      for (final s in list)
                        if ((q.isEmpty || s.name.toLowerCase().contains(q)) &&
                            (!_favOnly || s.userHasFavorited))
                          s
                    ];
                    if (_sort == 'name') {
                      working.sort((a, b) =>
                          a.name.toLowerCase().compareTo(b.name.toLowerCase()));
                    } else if (_sort == 'subscribers') {
                      working
                          .sort((a, b) => b.subscribers.compareTo(a.subscribers));
                    }
                    return [
                      _sectionHeader(context, '${working.length} communities'),
                      if (working.isEmpty)
                        const SliverToBoxAdapter(
                            child: Padding(
                                padding: EdgeInsets.all(32),
                                child: Center(child: Text('No matches'))))
                      else
                        _subList(ref, working),
                    ];
                  }

                  // Default view: recently visited + favorites + the rest.
                  final byName = {for (final s in list) s.name.toLowerCase(): s};
                  final seen = <String>{};
                  final recent = <Subreddit>[];
                  for (final h in ref.watch(historyControllerProvider)) {
                    final s = byName[h.subreddit.toLowerCase()];
                    if (s != null && seen.add(s.name)) recent.add(s);
                    if (recent.length >= 5) break;
                  }
                  final favs = list.where((s) => s.userHasFavorited).toList();
                  // The users you follow (their profiles, u_<name>) get their
                  // own section.
                  final following = list
                      .where((s) =>
                          !s.userHasFavorited && s.name.startsWith('u_'))
                      .toList();
                  final rest = list
                      .where((s) =>
                          !s.userHasFavorited && !s.name.startsWith('u_'))
                      .toList();
                  return [
                    if (recent.isNotEmpty) ...[
                      _sectionHeader(context, 'Recently visited'),
                      _subList(ref, recent),
                    ],
                    if (favs.isNotEmpty) ...[
                      _sectionHeader(context, 'Favorites'),
                      _subList(ref, favs),
                    ],
                    if (following.isNotEmpty) ...[
                      _sectionHeader(context, 'Following'),
                      _subList(ref, following),
                    ],
                    if (rest.isEmpty && favs.isEmpty && following.isEmpty) ...[
                      _sectionHeader(context, 'Subscriptions'),
                      const SliverToBoxAdapter(
                          child: Padding(
                              padding: EdgeInsets.all(32),
                              child: Center(
                                  child: Text('You have no subscriptions yet')))),
                    ] else if (rest.isNotEmpty) ...[
                      _sectionHeader(
                          context,
                          favs.isEmpty && following.isEmpty
                              ? 'Subscriptions'
                              : 'Communities'),
                      _subList(ref, rest),
                    ],
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

  Widget _connectedOutlined(
          int i, IconData icon, String label, VoidCallback onTap) =>
      OutlinedButton.icon(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(
              borderRadius: connectedRadius(i, 2, height: 52)
                  .resolve(Directionality.of(context))),
        ),
        icon: Icon(icon, size: 18),
        label: Text(label),
      );

  /// The custom feeds row: "See all" and a "New feed" chip when signed in;
  /// nothing for a guest without feeds.
  Widget _customFeeds(BuildContext context, ColorScheme cs) {
    final multis = ref.watch(myMultiredditsProvider);
    final auth = ref.watch(authControllerProvider.select((a) =>
        (a.valueOrNull?.anonymous ?? true, a.valueOrNull?.username ?? '')));
    final (anonymous, me) = auth;
    final list = multis.valueOrNull ?? const [];
    if (list.isEmpty && anonymous) return const SizedBox.shrink();
    Widget chip(IconData icon, String label, VoidCallback onTap) => ActionChip(
          avatar: Icon(icon, size: 18, color: cs.onSecondaryContainer),
          label: Text(label),
          onPressed: onTap,
          shape: const StadiumBorder(),
          side: BorderSide.none,
          backgroundColor: cs.surfaceContainerHigh,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 4, 0),
          child: Row(children: [
            Expanded(
              child: Text('Custom feeds',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: cs.primary, fontWeight: FontWeight.w700)),
            ),
            if (!anonymous)
              TextButton(
                onPressed: () => context.push('/custom_feeds'),
                child: const Text('See all'),
              ),
          ]),
        ),
        SizedBox(
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: list.length + (anonymous ? 0 : 1),
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              if (i == list.length) {
                return Center(
                  key: const ValueKey('new_multi'),
                  child: chip(Icons.add_rounded, 'New feed',
                      () => createMulti(context, ref, me)),
                );
              }
              final m = list[i];
              return Center(
                key: ValueKey(m.path.isEmpty ? m.name : m.path),
                child: chip(
                    Icons.dynamic_feed_rounded,
                    m.displayName.isNotEmpty ? m.displayName : m.name,
                    () => context.push('/m/${m.owner(me)}/${m.name}')),
              );
            },
          ),
        ),
      ],
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
        itemBuilder: (context, i) =>
            _SubredditRow(key: ValueKey(subs[i].name), subreddit: subs[i]),
      );
}

class _SubredditRow extends ConsumerWidget {
  const _SubredditRow({super.key, required this.subreddit});
  final Subreddit subreddit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final s = subreddit;
    return ListTile(
      leading: LetterAvatar(
          name: s.name,
          size: 40,
          container: cs.secondaryContainer,
          content: cs.onSecondaryContainer,
          imageUrl: s.iconUrl),
      title: Text(s.namePrefixed),
      subtitle: Text('${compactNumber(s.subscribers)} '
          '${s.name.startsWith('u_') ? 'followers' : 'members'}'),
      trailing: ToggleIcon(
        checked: s.userHasFavorited,
        on: Icons.star_rounded,
        off: Icons.star_border_rounded,
        description: 'Favorite',
        // The star toggle: favouriting reorders the list, so reload it after.
        onChanged: (_) async {
          try {
            await ref
                .read(redditRepositoryProvider)
                .setSubredditFavorite(s.name, !s.userHasFavorited);
            ref.invalidate(subscribedSubredditsProvider);
          } catch (e) {
            if (context.mounted) {
              showActionError(context,
                  s.userHasFavorited ? 'unfavorite' : 'favorite', e);
            }
          }
        },
      ),
      // A followed user is a subscription to their profile, u_<name>.
      onTap: () => context.push(s.name.startsWith('u_')
          ? '/u/${s.name.substring(2)}'
          : '/r/${s.name}'),
    );
  }
}
