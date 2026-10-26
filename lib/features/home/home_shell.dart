import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/widgets/glass_surface.dart' show useLiquidGlass;
import '../about/whats_new.dart';
import '../auth/auth_controller.dart';
import '../explore/explore_screen.dart';
import '../feed/post_list_view.dart';
import '../inbox/inbox_controller.dart';
import '../inbox/inbox_screen.dart';
import '../notifications/inbox_poller.dart';
import '../notifications/notification_service.dart';
import '../settings/settings_controller.dart';
import '../updates/update_checker.dart';
import 'account_tab.dart';
import 'frontpage_tab.dart';
import 'tab_menu.dart';
import 'tab_signals.dart';

/// SharedPreferences flag: have we shown the one-time notifications suggestion?
const String _kNotifPromptedPref = 'notifyInboxPrompted';

const _navItems = [
  (Icons.home_outlined, Icons.home_rounded, 'Posts'),
  (Icons.explore_outlined, Icons.explore_rounded, 'Explore'),
  (Icons.mail_outline_rounded, Icons.mail_rounded, 'Inbox'),
  (Icons.account_circle_outlined, Icons.account_circle_rounded, 'Profile'),
];

/// The home shell: Posts / Explore / Inbox / Profile tabs with the floating
/// "Pop" pill nav and / or the side bar (Settings › Navigation).
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  final _scaffold = GlobalKey<ScaffoldState>();
  int _index = 0;
  bool _chrome = true;
  DateTime _lastExploreTap = DateTime.fromMillisecondsSinceEpoch(0);
  // The other tabs are built one frame after the first paint (the Posts tab
  // shows first); they then stay alive in the IndexedStack.
  bool _allTabs = false;

  @override
  void initState() {
    super.initState();
    // Rebuilt (e.g. after a notification tap reset the stack): stay in sync.
    _index = ref.read(homeTabProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) setState(() => _allTabs = true);
      await _maybeCheckUpdates();
      if (mounted) await maybeShowWhatsNew(context, ref);
      if (mounted) await _maybeSuggestNotifications();
    });
  }

  /// One-time, opt-in suggestion to enable inbox notifications (shown on an
  /// early app open). Declining or enabling both mark it as handled so we never
  /// nag again — it stays fully controllable in Settings either way.
  Future<void> _maybeSuggestNotifications() async {
    final prefs = ref.read(sharedPrefsProvider);
    if (prefs.getBool(_kNotifPromptedPref) ?? false) return;
    if (ref.read(settingsControllerProvider).notifyInbox) return;
    await prefs.setBool(_kNotifPromptedPref, true);
    if (!mounted) return;
    final enable = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.notifications_active_outlined),
        title: const Text('Get notified of replies?'),
        content: const Text(
            'Ilay can check your Reddit inbox in the background (about every 15 '
            'minutes) and notify you of replies, mentions and messages.\n\n'
            'It uses simple polling — no Firebase or tracking. You can change '
            'this anytime in Settings.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Not now')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Enable')),
        ],
      ),
    );
    if (enable != true || !mounted) return;
    final granted = await NotificationService.instance.requestPermission();
    if (!granted) return;
    ref.read(settingsControllerProvider.notifier).setNotifyInbox(true);
    await pollInbox(notify: false); // prime, don't notify for existing unread
    await registerInboxPolling();
  }

  Future<void> _maybeCheckUpdates() async {
    if (!Platform.isAndroid) return; // GitHub-APK updates are Android-only
    if (!ref.read(settingsControllerProvider).checkUpdates) return;
    final info = await UpdateChecker().check();
    if (info == null || !mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Update available — v${info.version}'),
        content: const Text(
            'A newer version of Ilay is available on GitHub.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Later')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              launchUrl(Uri.parse(info.apkUrl ?? info.url),
                  mode: LaunchMode.externalApplication);
            },
            child: const Text('Download'),
          ),
        ],
      ),
    );
  }

  bool _onScroll(UserScrollNotification n) {
    // Any tab's main list, including those inside a tab's pager (Inbox,
    // Profile); not the pagers themselves or horizontal carousels.
    if (n.metrics.axis != Axis.vertical) return false;
    final m = n.metrics;
    // Near the top or overscrolling (iOS rubber-band) — keep chrome shown and
    // don't toggle, so the bar doesn't bounce in/out as you scroll back up.
    if (m.outOfRange || m.pixels <= m.minScrollExtent + 4) {
      if (!_chrome) setState(() => _chrome = true);
      return false;
    }
    if (n.direction == ScrollDirection.reverse && _chrome) {
      setState(() => _chrome = false);
    } else if (n.direction == ScrollDirection.forward && !_chrome) {
      setState(() => _chrome = true);
    }
    return false;
  }

  void _selectTab(int i) {
    // Double-tapping Explore opens search, keyboard up.
    final now = DateTime.now();
    if (i == 1 &&
        now.difference(_lastExploreTap) < const Duration(milliseconds: 400)) {
      _lastExploreTap = DateTime.fromMillisecondsSinceEpoch(0);
      context.push('/search');
      return;
    }
    if (i == 1) _lastExploreTap = now;
    // Re-tapping the active tab scrolls it to top (Posts also refreshes).
    if (i == _index) {
      if (i == 0) {
        ref.read(frontpageScrollSignalProvider.notifier).state++;
      } else {
        ref.read(tabReselectProvider(i).notifier).state++;
      }
      return;
    }
    setState(() {
      _index = i;
      _chrome = true; // always reveal chrome when switching tabs
    });
    ref.read(homeTabProvider.notifier).state = i;
  }

  void _openSideBar() => _scaffold.currentState?.openDrawer();

  Widget _tab(int i) {
    if (!_allTabs && i != _index) return const SizedBox.shrink();
    return switch (i) {
      0 => FrontpageTab(chromeVisible: _chrome),
      1 => const ExploreScreen(),
      2 => const InboxScreen(),
      _ => const ProfileTab(),
    };
  }

  @override
  Widget build(BuildContext context) {
    // Switched from outside (a notification tap opens the Inbox).
    ref.listen<int>(homeTabProvider, (_, i) {
      if (i != _index) _selectTab(i);
    });
    final unread = ref.watch(unreadCountProvider).valueOrNull ?? 0;
    final navStyle =
        ref.watch(settingsControllerProvider.select((s) => s.navStyle));
    final navLabels =
        ref.watch(settingsControllerProvider.select((s) => s.navLabels));
    final navOutline =
        ref.watch(settingsControllerProvider.select((s) => s.navOutline));
    // Settings › Navigation: the bottom bar, the side bar, or both.
    final bottomBar = navStyle != 1;
    final sideBar = navStyle != 0;
    final surface = Theme.of(context).colorScheme.surface;
    return Scaffold(
      key: _scaffold,
      // Pop variant: content flows under the detached floating nav.
      extendBody: true,
      // With the side bar on, an edge swipe from the left brings it out
      // (Android's back gesture does this in Kotlin).
      drawer: sideBar
          ? _SideBar(
              selected: _index,
              unread: unread,
              onTab: (i) {
                _scaffold.currentState?.closeDrawer();
                _selectTab(i);
              },
            )
          : null,
      drawerEnableOpenDragGesture: sideBar,
      body: SideBarScope(
        open: sideBar ? _openSideBar : null,
        child: Stack(
          children: [
            NotificationListener<UserScrollNotification>(
              onNotification: _onScroll,
              child: SafeArea(
                bottom: false,
                child: IndexedStack(
                  index: _index,
                  children: [for (var i = 0; i < 4; i++) _tab(i)],
                ),
              ),
            ),
            if (bottomBar)
              // A fade from the page colour behind the nav, so the pill never
              // sits directly on a post of the same tone; it hides with the
              // nav.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _chrome ? 1 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: Container(
                      height: 130 + MediaQuery.paddingOf(context).bottom,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            surface.withValues(alpha: 0),
                            surface.withValues(alpha: 0.92),
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
      bottomNavigationBar: bottomBar
          ? AnimatedSlide(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              offset: _chrome ? Offset.zero : const Offset(0, 1.4),
              child: _FloatingNav(
                selected: _index,
                unread: unread,
                showLabels: navLabels,
                outline: navOutline,
                onSelected: _selectTab,
              ),
            )
          : null,
    );
  }
}

/// The side bar (Settings › Navigation): the four tabs, then your stuff and
/// Settings. Picking one closes it, then runs the choice.
class _SideBar extends ConsumerWidget {
  const _SideBar(
      {required this.selected, required this.unread, required this.onTab});
  final int selected;
  final int unread;
  final ValueChanged<int> onTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final session = ref.watch(authControllerProvider).valueOrNull;
    final anonymous = session?.anonymous != false;
    final router = GoRouter.of(context);
    final more = [
      if (!anonymous)
        (Icons.bookmark_border_rounded, 'Saved', '/saved'),
      if (!anonymous)
        (Icons.dynamic_feed_rounded, 'Custom feeds', '/custom_feeds'),
      (Icons.history_rounded, 'History', '/history'),
      (Icons.offline_pin_rounded, 'Read later', '/offline'),
      (Icons.edit_note_rounded, 'Drafts', '/drafts'),
      (Icons.settings_outlined, 'Settings', '/settings'),
    ];
    return Drawer(
      width: 300,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 20),
              child: Text('Ilay',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 0, 16),
              child: Text(
                  anonymous
                      ? 'Browsing without an account'
                      : 'u/${session?.username}',
                  style: TextStyle(color: cs.onSurfaceVariant)),
            ),
            for (var i = 0; i < _navItems.length; i++)
              _DrawerItem(
                icon: i == selected ? _navItems[i].$2 : _navItems[i].$1,
                label: _navItems[i].$3,
                selected: i == selected,
                badge: i == 2 && unread > 0
                    ? (unread > 99 ? '99+' : '$unread')
                    : null,
                onTap: () => onTab(i),
              ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              child: Divider(height: 1),
            ),
            for (final m in more)
              _DrawerItem(
                icon: m.$1,
                label: m.$2,
                selected: false,
                onTap: () {
                  Scaffold.of(context).closeDrawer();
                  router.push(m.$3);
                },
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// An M3 navigation drawer item: a 56px stadium, filled when selected.
class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = selected ? cs.onSecondaryContainer : cs.onSurfaceVariant;
    return Semantics(
      selected: selected,
      child: Material(
        color: selected ? cs.secondaryContainer : Colors.transparent,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 56,
            child: Padding(
              padding: const EdgeInsets.only(left: 16, right: 24),
              child: Row(
                children: [
                  Icon(icon, color: fg),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(label,
                        style: TextStyle(
                            color: fg,
                            fontSize: 14,
                            fontWeight: FontWeight.w500)),
                  ),
                  if (badge != null)
                    Text(badge!,
                        style: TextStyle(
                            color: fg,
                            fontSize: 14,
                            fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact floating nav: a centred pill of icon buttons; the current tab
/// expands into a filled primary pill with its label (when labels are on).
/// Outlined and lifted so it reads apart from the posts behind it. Dragging
/// a finger along it moves the selection from tab to tab.
class _FloatingNav extends StatefulWidget {
  const _FloatingNav({
    required this.selected,
    required this.unread,
    required this.showLabels,
    required this.outline,
    required this.onSelected,
  });
  final int selected;
  final int unread;
  final bool showLabels;
  final bool outline;
  final ValueChanged<int> onSelected;

  @override
  State<_FloatingNav> createState() => _FloatingNavState();
}

class _FloatingNavState extends State<_FloatingNav> {
  // Each tab button, for drag hit-testing.
  final _keys = List.generate(_navItems.length, (_) => GlobalKey());

  // Only switch once the finger is inside another tab, so a tab growing under
  // it can't bounce the selection back.
  void _pick(Offset global) {
    for (var i = 0; i < _keys.length; i++) {
      final box = _keys[i].currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final left = box.localToGlobal(Offset.zero).dx;
      if (global.dx >= left && global.dx <= left + box.size.width) {
        if (i != widget.selected) {
          HapticFeedback.selectionClick();
          widget.onSelected(i);
        }
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    const radius = BorderRadius.all(Radius.circular(32));
    final bar = Container(
      height: 64,
      decoration: BoxDecoration(
        // Fully solid so it stays legible over images.
        color: dark ? cs.surfaceContainerHigh : cs.surfaceContainer,
        borderRadius: radius,
        border: widget.outline ? Border.all(color: cs.outlineVariant) : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (d) => _pick(d.globalPosition),
        onHorizontalDragUpdate: (d) => _pick(d.globalPosition),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < _navItems.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              _NavButton(
                key: _keys[i],
                item: _navItems[i],
                selected: widget.selected == i,
                badge: i == 2 ? widget.unread : 0,
                showLabel: widget.showLabels,
                onTap: () => widget.onSelected(i),
              ),
            ],
          ],
        ),
      ),
    );
    // iOS: sit low like Telegram/Apple Music — ignore the home-indicator safe
    // area and keep just a small gap.
    final inset = useLiquidGlass ? 0.0 : MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: 20 + inset),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [bar],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    super.key,
    required this.item,
    required this.selected,
    required this.badge,
    required this.showLabel,
    required this.onTap,
  });
  final (IconData, IconData, String) item;
  final bool selected;
  final int badge;
  final bool showLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = selected ? cs.onPrimary : cs.onSurfaceVariant;
    Widget icon = Icon(selected ? item.$2 : item.$1, size: 24, color: fg);
    if (badge > 0) {
      icon = Badge(label: Text(badge > 99 ? '99+' : '$badge'), child: icon);
    }
    final labelled = selected && showLabel;
    // A tab, for screen readers: "Inbox, selected".
    return Semantics(
      selected: selected,
      button: true,
      inMutuallyExclusiveGroup: true,
      label: item.$3,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          height: 48,
          padding: EdgeInsets.symmetric(horizontal: labelled ? 18 : 12),
          decoration: BoxDecoration(
            color: selected ? cs.primary : cs.primary.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(24),
          ),
          // The selected pill grows to fit its label with a little bounce.
          child: AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutBack,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon,
                if (labelled) ...[
                  const SizedBox(width: 8),
                  Text(item.$3,
                      maxLines: 1,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: fg)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
