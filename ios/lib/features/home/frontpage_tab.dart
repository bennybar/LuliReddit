import 'package:flutter/rendering.dart';
import '../../core/widgets/collapsing_fab.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/rate_limit.dart';
import '../../core/widgets/glass_surface.dart';
import '../../core/widgets/pick_one_menu.dart';
import '../auth/auth_controller.dart';
import '../feed/post_card.dart' show LetterAvatar;
import '../feed/feed_controller.dart';
import '../feed/post_list_view.dart';
import '../reddit_home/reddit_home_engine.dart';
import '../settings/settings_controller.dart';
import 'tab_menu.dart';

/// The Posts tab: the frontpage feed under its top bar (Full or Expandable
/// mode).
class FrontpageTab extends ConsumerStatefulWidget {
  const FrontpageTab({super.key, this.selected = true});
  final bool selected;

  @override
  ConsumerState<FrontpageTab> createState() => _FrontpageTabState();
}

// The top bar floats over the feed and follows the finger, in and out (#55):
// it slides away as you scroll down and back as you scroll up, and the feed
// stays put under it instead of being pushed around.
class _FrontpageTabState extends ConsumerState<FrontpageTab>
    with SingleTickerProviderStateMixin {
  final _barKey = GlobalKey();
  double _barHeight = 0;
  bool _fabExpanded = true; // folds scrolling down, opens scrolling up (#62)
  // 0 = shown, -_barHeight = hidden.
  late final AnimationController _barShift =
      AnimationController.unbounded(vsync: this);

  void _slideBar(double to) => _barShift.animateTo(to,
      duration: const Duration(milliseconds: 200), curve: Curves.easeOut);

  @override
  void didUpdateWidget(FrontpageTab old) {
    super.didUpdateWidget(old);
    if (widget.selected && !old.selected) _slideBar(0);
  }

  @override
  void dispose() {
    _barShift.dispose();
    super.dispose();
  }

  bool _onFeedScroll(ScrollNotification n) {
    final m = n.metrics;
    // The feed itself: not a card's carousel or the chip row.
    if (m.axis != Axis.vertical || n.depth != 0) return false;
    if (n is UserScrollNotification && n.direction != ScrollDirection.idle) {
      final expanded = n.direction == ScrollDirection.forward;
      if (expanded != _fabExpanded) setState(() => _fabExpanded = expanded);
    }
    final fromTop = m.pixels - m.minScrollExtent;
    if (n is ScrollUpdateNotification && n.scrollDelta != null) {
      if (m.pixels > m.maxScrollExtent) return false; // iOS bounce at the end
      _barShift.stop();
      // Never hidden past the feed's top, however it got there (a re-tap on
      // the tab, new posts): there'd be a blank gap above the first card.
      final shift = math.max(_barShift.value - n.scrollDelta!, -fromTop);
      _barShift.value = shift.clamp(-_barHeight, 0.0);
    } else if (n is ScrollEndNotification) {
      // Don't rest half way; hide only with the feed scrolled far enough to
      // fill the space the bar leaves.
      final v = _barShift.value;
      if (v != 0 && v != -_barHeight) {
        _slideBar(fromTop >= _barHeight && v < -_barHeight / 2
            ? -_barHeight
            : 0);
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    // Reloading starts a new list from the top.
    ref.listen(feedControllerProvider(''), (_, next) {
      if (next.isLoading || next.hasError) _slideBar(0);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final h = _barKey.currentContext?.size?.height;
      if (mounted && h != null && h != _barHeight) {
        setState(() => _barHeight = h);
      }
    });
    final cs = Theme.of(context).colorScheme;
    final homeFab =
        ref.watch(settingsControllerProvider.select((s) => s.homeFab));
    final bottomBar =
        ref.watch(settingsControllerProvider.select((s) => s.navStyle)) != 1;
    final username = ref.watch(
            authControllerProvider.select((a) => a.valueOrNull?.username)) ??
        '';
    final forYou =
        ref.watch(settingsControllerProvider.select((s) => s.forYouFeed));
    final homeOn = ref.watch(settingsControllerProvider
        .select((s) => s.redditHomeAllowed && s.redditHomeFeed));
    final blend = forYou &&
        ref.watch(settingsControllerProvider
            .select((s) => s.blendHome && s.redditHomeAllowed));
    final mode =
        ref.watch(settingsControllerProvider.select((s) => s.topBarMode));
    final showApiUsage =
        ref.watch(settingsControllerProvider.select((s) => s.showApiUsage));
    final sideBar = SideBarScope.of(context) != null;
    final expandable = mode == TopBarMode.expandable;
    // The title row: the bar itself in Expandable mode; Full mode scrolls it
    // with the feed.
    final titleRow = Padding(
      // With the ☰ there, line it up with the other tabs' (4px + the
      // button's own inset). The feed (or, in Expandable mode, the
      // bar) already insets it 7px.
      padding: EdgeInsets.fromLTRB(
          expandable && sideBar ? 0 : 16,
          expandable ? (sideBar ? 8 : 10) : 8,
          expandable ? 4 : 16,
          0),
      child: Row(
        children: [
          // Full mode has it in the action row above.
          if (expandable)
            Transform.translate(
                offset: const Offset(-3, 0),
                child: const SideBarButton()),
          Text(
            homeOn
                ? 'Home'
                : blend
                    ? 'Blend'
                    : (forYou ? 'For You' : 'Frontpage'),
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          if (!homeOn && forYou) ...[
            const SizedBox(width: 8),
            Expanded(
              child: blend
                  ? const _BlendSubtitle()
                  : Text('Personalized on your phone',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurfaceVariant)),
            ),
          ] else
            const Spacer(),
          // Expandable mode: search right here, and one button that
          // floats the toolbar in.
          if (expandable) ...[
            IconButton(
              tooltip: 'Search',
              icon: const Icon(Icons.search_rounded),
              onPressed: () => context.push('/search'),
            ),
            IconButton(
              tooltip: 'Toolbar',
              icon: const Icon(Icons.more_horiz_rounded),
              onPressed: () => _showFloatingToolbar(context, username),
            ),
          ],
        ],
      ),
    );
    // Full mode: Google-app style search bar with avatar.
    final actionRow = Padding(
        // With the ☰ here: the same spot as on the other tabs.
        padding: EdgeInsets.fromLTRB(
            sideBar ? 4 : 16, sideBar ? 6 : 12, 16, 4),
        child: Row(
          children: [
            const SideBarButton(),
            Expanded(
              child: showApiUsage
                  ? const _ApiUsagePill()
                  : _SearchPill(
                      onTap: () => context.push('/search')),
            ),
            const SizedBox(width: 4),
            _NewPostButton(onTap: () => context.push('/submit')),
            const _DisplayMenu(),
            const SizedBox(width: 4),
            _ProfileAvatar(
                username: username,
                size: 44,
                onTap: () => context.push('/u/$username')),
          ],
        ),
      );
    return NotificationListener<ScrollNotification>(
      onNotification: _onFeedScroll,
      // A Stack doesn't clip a Transform: the hidden bar would sit over the
      // status bar.
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            PostListView(
              feedKey: '',
              header: expandable ? null : titleRow,
              topPadding: _barHeight,
              barShift: _barShift,
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AnimatedBuilder(
                animation: _barShift,
                builder: (_, child) => Transform.translate(
                    offset: Offset(0, _barShift.value), child: child),
                child: ColoredBox(
                  key: _barKey,
                  color: cs.surface,
                  child: expandable
                      ? Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 7),
                          child: titleRow)
                      : actionRow,
                ),
              ),
            ),
            if (homeFab != HomeFab.off)
              Positioned(
                right: 16,
                // Above the bottom bar, when there is one.
                bottom: MediaQuery.viewPaddingOf(context).bottom +
                    (bottomBar ? 86 : 16),
                child: CollapsingFab(
                  icon: homeFab == HomeFab.newPost
                      ? Icons.edit_rounded
                      : Icons.search_rounded,
                  label: homeFab.label,
                  expanded: _fabExpanded,
                  onTap: () => context
                      .push(homeFab == HomeFab.newPost ? '/submit' : '/search'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Blend's header subtitle: what its Reddit Home source is contributing
/// right now.
class _BlendSubtitle extends ConsumerWidget {
  const _BlendSubtitle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = switch (ref.watch(blendStateProvider)) {
      BlendIncluded(:final count) => count == 0
          ? 'Beta · no Reddit Home picks yet'
          : 'Beta · $count Reddit Home pick${count == 1 ? '' : 's'}',
      BlendLoading() => 'Beta · Reddit Home loading…',
      BlendUnavailable(:final signedOut) => signedOut
          ? 'Beta · Reddit Home signed out: showing For You'
          : 'Beta · Reddit Home unavailable: showing For You',
      null => 'Your Reddit Home + For You · Beta',
    };
    return Text(text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant));
  }
}

class _SearchPill extends StatelessWidget {
  const _SearchPill({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GlassSurface(
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.search_rounded, color: cs.onSurfaceVariant),
              const SizedBox(width: 12),
              Text('Search Reddit',
                  style: TextStyle(color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewPostButton extends StatelessWidget {
  const _NewPostButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IconButton.filled(
      tooltip: 'New post',
      icon: const Icon(Icons.post_add_outlined, size: 22),
      style: IconButton.styleFrom(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
      ),
      onPressed: onTap,
    );
  }
}

class _ProfileAvatar extends ConsumerWidget {
  const _ProfileAvatar(
      {required this.username, required this.size, required this.onTap});
  final String username;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final anonymous = ref.watch(authControllerProvider
            .select((a) => a.valueOrNull?.anonymous)) ??
        true;
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Your profile',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: LetterAvatar(
          name: username,
          size: size,
          container: cs.primaryContainer,
          content: cs.onPrimaryContainer,
          imageUrl: anonymous || username.isEmpty
              ? null
              : ref.watch(meProvider(username)).valueOrNull?.iconUrl,
          fontSize: 16,
        ),
      ),
    );
  }
}

/// Three-dot menu to switch the feed's post display type (and media
/// autoplay). Grouped like Kotlin's Expressive menu: Layout (pick one),
/// Autoplay (on/off), Settings.
class _DisplayMenu extends ConsumerWidget {
  const _DisplayMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final display =
        ref.watch(settingsControllerProvider.select((s) => s.postDisplay));
    final autoplay =
        ref.watch(settingsControllerProvider.select((s) => s.autoplayMedia));
    final ctrl = ref.read(settingsControllerProvider.notifier);
    return PopupMenuButton<VoidCallback>(
      tooltip: 'Display',
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (f) => f(),
      itemBuilder: (_) => menuGroups([
        [
          for (final d in PostDisplay.values)
            MenuOption(() => ctrl.setPostDisplay(d), d.label,
                icon: d.icon, selected: d == display),
        ],
        [
          MenuOption(() => ctrl.setAutoplayMedia(!autoplay), 'Autoplay media',
              icon: Icons.play_circle_outline_rounded, checked: autoplay),
        ],
        [
          MenuOption(() => context.push('/settings'), 'Settings',
              icon: Icons.settings_outlined),
        ],
      ]),
    );
  }
}

/// Shows live Reddit API rate-limit usage in place of the search bar
/// (power-user setting). Reddit allows ~100 requests/minute per OAuth client.
class _ApiUsagePill extends ConsumerWidget {
  const _ApiUsagePill();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final rl = ref.watch(rateLimitProvider);
    final String label;
    if (rl == null) {
      label = 'API usage · no calls yet';
    } else {
      label = 'API ${rl.used}/${rl.total} · resets ${rl.resetSeconds}s';
    }
    return GlassSurface(
      borderRadius: BorderRadius.circular(28),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            Icon(Icons.speed_rounded, color: cs.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: cs.onSurfaceVariant)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Expandable top-bar mode: floats the full toolbar (search, new post,
/// display, profile) in from the top as a dismissible overlay — it never
/// displaces the feed.
Future<void> _showFloatingToolbar(BuildContext context, String username) {
  final router = GoRouter.of(context);
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Toolbar',
    barrierColor: Colors.black.withValues(alpha: 0.30),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (ctx, _, __) {
      // Close first, then go: the panel animates away under the new screen.
      void go(String location) {
        Navigator.of(ctx).pop();
        router.push(location);
      }

      return SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: _ToolbarPanel(
              username: username,
              onSearch: () => go('/search'),
              onNewPost: () => go('/submit'),
              onProfile: () => go('/u/$username'),
              onSettings: () => go('/settings'),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, -1 / 6), end: Offset.zero)
              .animate(curved),
          child: child,
        ),
      );
    },
  );
}

const _panelOuter = Radius.circular(26);
const _panelInner = Radius.circular(6);

/// The expandable top bar's panel: connected segments 3px apart — search
/// (with the profile avatar), New post / Settings, the feed layout as one
/// connected button group, and the autoplay switch. Layout and autoplay
/// apply at once and leave the panel open, so the change is visible behind
/// it.
class _ToolbarPanel extends ConsumerWidget {
  const _ToolbarPanel({
    required this.username,
    required this.onSearch,
    required this.onNewPost,
    required this.onProfile,
    required this.onSettings,
  });
  final String username;
  final VoidCallback onSearch;
  final VoidCallback onNewPost;
  final VoidCallback onProfile;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final display =
        ref.watch(settingsControllerProvider.select((s) => s.postDisplay));
    final autoplay =
        ref.watch(settingsControllerProvider.select((s) => s.autoplayMedia));
    final ctrl = ref.read(settingsControllerProvider.notifier);
    final seg = cs.surfaceContainerHigh;
    const all = PostDisplay.values;
    return Material(
      color: cs.surfaceContainer,
      elevation: 8,
      borderRadius: BorderRadius.circular(32),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: seg,
              borderRadius: const BorderRadius.only(
                  topLeft: _panelOuter,
                  topRight: _panelOuter,
                  bottomLeft: _panelInner,
                  bottomRight: _panelInner),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onSearch,
                child: SizedBox(
                  height: 60,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16, right: 8),
                    child: Row(
                      children: [
                        Icon(Icons.search_rounded, color: cs.onSurfaceVariant),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text('Search Reddit',
                              maxLines: 1,
                              style: TextStyle(
                                  fontSize: 16, color: cs.onSurfaceVariant)),
                        ),
                        _ProfileAvatar(
                            username: username, size: 44, onTap: onProfile),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 3),
            Row(
              children: [
                Expanded(
                    child: _PanelButton(
                        icon: Icons.post_add_outlined,
                        label: 'New post',
                        onTap: onNewPost)),
                const SizedBox(width: 3),
                Expanded(
                    child: _PanelButton(
                        icon: Icons.settings_outlined,
                        label: 'Settings',
                        onTap: onSettings)),
              ],
            ),
            const SizedBox(height: 3),
            Container(
              decoration: BoxDecoration(
                  color: seg,
                  borderRadius: const BorderRadius.all(_panelInner)),
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 12, 0, 8),
                    child: Text('Layout',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: cs.primary)),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < all.length; i++) ...[
                        if (i > 0) const SizedBox(width: 3),
                        Expanded(
                          child: _LayoutChoice(
                            display: all[i],
                            selected: all[i] == display,
                            start: i == 0
                                ? const Radius.circular(20)
                                : _panelInner,
                            end: i == all.length - 1
                                ? const Radius.circular(20)
                                : _panelInner,
                            onTap: () => ctrl.setPostDisplay(all[i]),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 3),
            Material(
              color: seg,
              borderRadius: const BorderRadius.only(
                  topLeft: _panelInner,
                  topRight: _panelInner,
                  bottomLeft: _panelOuter,
                  bottomRight: _panelOuter),
              clipBehavior: Clip.antiAlias,
              child: MergeSemantics(
                child: InkWell(
                  onTap: () => ctrl.setAutoplayMedia(!autoplay),
                  child: SizedBox(
                    height: 60,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Icon(Icons.play_circle_outline_rounded,
                              color: cs.onSurfaceVariant),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Text('Autoplay media',
                                style: TextStyle(fontSize: 16)),
                          ),
                          Switch(
                              value: autoplay,
                              onChanged: ctrl.setAutoplayMedia),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LayoutChoice extends StatelessWidget {
  const _LayoutChoice({
    required this.display,
    required this.selected,
    required this.start,
    required this.end,
    required this.onTap,
  });
  final PostDisplay display;
  final bool selected;
  final Radius start;
  final Radius end;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = selected ? cs.onPrimary : cs.onSurface;
    // Pick-one for screen readers: "Calm, selected".
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      button: true,
      child: Material(
        color: selected ? cs.primary : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.horizontal(left: start, right: end),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 76,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(display.icon, size: 22, color: fg),
                  const SizedBox(height: 6),
                  Text(display.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: fg)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PanelButton extends StatelessWidget {
  const _PanelButton(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHigh,
      borderRadius: const BorderRadius.all(_panelInner),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 56,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: cs.onSurface),
              const SizedBox(width: 10),
              Text(label,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}
