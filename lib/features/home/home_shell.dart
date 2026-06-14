import 'dart:io';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/rate_limit.dart';
import '../../core/widgets/glass_surface.dart';
import '../auth/auth_controller.dart';
import '../explore/explore_screen.dart';
import '../feed/post_list_view.dart';
import '../inbox/inbox_controller.dart';
import '../inbox/inbox_screen.dart';
import '../notifications/inbox_poller.dart';
import '../notifications/notification_service.dart';
import '../search/floating_search.dart';
import '../settings/settings_controller.dart';
import '../updates/update_checker.dart';
import 'account_tab.dart';

/// SharedPreferences flag: have we shown the one-time notifications suggestion?
const String _kNotifPromptedPref = 'notifyInboxPrompted';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  bool _chrome = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _maybeCheckUpdates();
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
            'Luli can check your Reddit inbox in the background (about every 15 '
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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Update available — v${info.version}'),
        content: const Text(
            'A newer version of Luli is available on GitHub.'),
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
    if (n.depth != 0) return false;
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

  @override
  Widget build(BuildContext context) {
    final unread = ref.watch(unreadCountProvider).valueOrNull ?? 0;
    final compact = ref.watch(settingsControllerProvider
        .select((s) => s.topBarMode == TopBarMode.compact));
    return Scaffold(
      // Pop variant: content flows under the detached floating nav.
      extendBody: true,
      body: NotificationListener<UserScrollNotification>(
        onNotification: _onScroll,
        child: SafeArea(
          bottom: false,
          child: IndexedStack(
            index: _index,
            children: [
              _FrontpageTab(chromeVisible: _chrome),
              const ExploreScreen(),
              const InboxScreen(),
              const AccountTab(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: AnimatedSlide(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        offset: _chrome ? Offset.zero : const Offset(0, 1.4),
        child: _FloatingNav(
          selectedIndex: _index,
          unread: unread,
          showCompose: compact,
          onNewPost: () => context.push('/submit'),
          onSelected: (i) {
            // Re-tapping the active Posts tab scrolls it to top (or refreshes).
            if (i == _index) {
              if (i == 0) {
                ref.read(frontpageScrollSignalProvider.notifier).state++;
              }
              return;
            }
            setState(() {
              _index = i;
              _chrome = true; // always reveal chrome when switching tabs
            });
          },
        ),
      ),
    );
  }
}

/// "Pop" floating pill navigation. On iOS the selection indicator is a single
/// Liquid-Glass capsule that fluidly slides + stretches between tabs (the
/// Apple-Music "drag" effect); on Android it's the standard Material pill.
class _FloatingNav extends StatefulWidget {
  const _FloatingNav({
    required this.selectedIndex,
    required this.unread,
    required this.onSelected,
    this.showCompose = false,
    this.onNewPost,
  });
  final int selectedIndex;
  final int unread;
  final ValueChanged<int> onSelected;

  /// Compact mode: insert a "New post" action between Explore and Inbox.
  final bool showCompose;
  final VoidCallback? onNewPost;

  @override
  State<_FloatingNav> createState() => _FloatingNavState();
}

class _FloatingNavState extends State<_FloatingNav>
    with SingleTickerProviderStateMixin {
  static const _items = [
    (Icons.home_outlined, Icons.home_rounded, 'Posts'),
    (Icons.explore_outlined, Icons.explore_rounded, 'Explore'),
    (Icons.mail_outline_rounded, Icons.mail_rounded, 'Inbox'),
    (Icons.account_circle_outlined, Icons.account_circle_rounded, 'Account'),
  ];

  late final AnimationController _c;
  double _from = 0;
  double _to = 0;
  // While the user holds & slides their thumb across the bar, the capsule
  // follows the finger (fractional index); null = not dragging.
  double? _drag;
  bool _fromDrag = false;

  @override
  void initState() {
    super.initState();
    _from = _to = _slotForTab(widget.selectedIndex).toDouble();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
  }

  @override
  void didUpdateWidget(_FloatingNav old) {
    super.didUpdateWidget(old);
    if (old.showCompose != widget.showCompose) {
      // Layout changed (compose slot added/removed) — re-seat without animating.
      _from = _to = _slotForTab(widget.selectedIndex).toDouble();
      return;
    }
    if (_fromDrag) {
      _fromDrag = false; // drag already ran its own snap animation
      return;
    }
    if (old.selectedIndex != widget.selectedIndex) {
      _from = _displayed; // smooth interrupt mid-flight
      _to = _slotForTab(widget.selectedIndex).toDouble();
      _c.forward(from: 0);
    }
  }

  double get _displayed =>
      lerpDouble(_from, _to, Curves.easeOutCubic.transform(_c.value))!;

  // --- Slot mapping ---------------------------------------------------------
  // The 4 tabs occupy "slots". In compact mode a non-tab "Post" action is
  // inserted at slot 2, so tab indices (0..3) and visual slots diverge.
  int get _slotCount => widget.showCompose ? 5 : 4;
  bool _isComposeSlot(int s) => widget.showCompose && s == 2;
  int _slotForTab(int tab) => widget.showCompose ? const [0, 1, 3, 4][tab] : tab;
  int? _tabForSlot(int s) =>
      widget.showCompose ? const {0: 0, 1: 1, 2: null, 3: 2, 4: 3}[s] : s;
  List<int> get _tabSlots =>
      widget.showCompose ? const [0, 1, 3, 4] : const [0, 1, 2, 3];

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(40));
    // iOS: sit low like Telegram/Apple Music — ignore the home-indicator safe
    // area and keep just a small gap, letting the indicator overlap the bar.
    if (useLiquidGlass) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
        child: _bar(context, radius),
      );
    }
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
        child: _bar(context, radius),
      ),
    );
  }

  Widget _bar(BuildContext context, BorderRadius radius) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            // Subtler on iOS — the heavy shadow read as an odd aura.
            color:
                Colors.black.withValues(alpha: useLiquidGlass ? 0.10 : 0.22),
            blurRadius: useLiquidGlass ? 14 : 24,
            offset: Offset(0, useLiquidGlass ? 4 : 8),
          ),
        ],
      ),
      child: GlassSurface(
        borderRadius: radius,
        // Nav sits over scrolling content (incl. dark images). Telegram's
        // tab bar is fully solid — match that so labels are always legible.
        tintOpacity: 1.0,
        child: SizedBox(
          height: 70,
          child: useLiquidGlass ? _glass(context) : _material(context),
        ),
      ),
    );
  }

  // Android: standard Material pills (+ optional compose action).
  Widget _material(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (var s = 0; s < _slotCount; s++)
          Expanded(
            child: _isComposeSlot(s)
                ? _composeItem(context, cs)
                : _NavItem(
                    iconOff: _items[_tabForSlot(s)!].$1,
                    iconOn: _items[_tabForSlot(s)!].$2,
                    label: _items[_tabForSlot(s)!].$3,
                    selected: widget.selectedIndex == _tabForSlot(s),
                    badge: _tabForSlot(s) == 2 ? widget.unread : 0,
                    onTap: () => widget.onSelected(_tabForSlot(s)!),
                  ),
          ),
      ],
    );
  }

  /// The accent "New post" action shown in the bottom nav in compact mode.
  Widget _composeItem(BuildContext context, ColorScheme cs) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onNewPost,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 42,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cs.primary,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Icon(Icons.edit_square, size: 18, color: cs.onPrimary),
          ),
          const SizedBox(height: 3),
          Text('Post',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  // iOS: a single sliding/stretching glass capsule behind the items.
  Widget _glass(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, bc) {
        final w = bc.maxWidth;
        final n = _slotCount;
        final iw = w / n;
        final capBase = iw - 14;

        // Finger x → fractional slot (capsule centre follows the thumb).
        double idxFromX(double x) =>
            ((x - iw / 2) / iw).clamp(0.0, (n - 1).toDouble());

        void onDown(double x) => setState(() => _drag = idxFromX(x));
        void onMove(double x) => setState(() => _drag = idxFromX(x));
        void onUp() {
          var slot =
              (_drag ?? _displayed).round().clamp(0, n - 1);
          // Never rest on the compose action; snap to the nearest real tab.
          if (_isComposeSlot(slot)) {
            slot = _tabSlots.reduce(
                (a, b) => (a - slot).abs() <= (b - slot).abs() ? a : b);
          }
          _from = _drag ?? _displayed;
          _to = slot.toDouble();
          _drag = null;
          _fromDrag = true;
          _c.forward(from: 0);
          widget.onSelected(_tabForSlot(slot)!);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (d) => onDown(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => onMove(d.localPosition.dx),
          onHorizontalDragEnd: (_) => onUp(),
          onHorizontalDragCancel: () => setState(() => _drag = null),
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              double leftAt(double idx) => idx * iw + (iw - capBase) / 2;
              double left, width;
              if (_drag != null) {
                // Interactive: capsule sits under the finger, base width.
                width = capBase;
                left = leftAt(_drag!);
              } else {
                final fromL = leftAt(_from), toL = leftAt(_to);
                final fromR = fromL + capBase, toR = toL + capBase;
                final t = _c.value;
                final lead = Curves.easeOutQuart.transform(t);
                final trail = Curves.easeInQuart.transform(t);
                final movingRight = _to >= _from;
                final leftEdge =
                    lerpDouble(fromL, toL, movingRight ? trail : lead)!;
                final rightEdge =
                    lerpDouble(fromR, toR, movingRight ? lead : trail)!;
                left = leftEdge;
                width = (rightEdge - leftEdge).clamp(capBase, w);
              }
              left = left.clamp(4.0, w - 4 - width);
              final activeSlot = (_drag != null
                      ? _drag!.round()
                      : _slotForTab(widget.selectedIndex))
                  .clamp(0, n - 1);
              final dragging = _drag != null;
              return Stack(
                children: [
                  AnimatedPositioned(
                    duration: dragging
                        ? const Duration(milliseconds: 90)
                        : Duration.zero,
                    curve: Curves.easeOut,
                    top: 8,
                    bottom: 8,
                    left: left,
                    width: width,
                    // Lift & grow while held, like iOS.
                    child: AnimatedScale(
                      scale: dragging ? 1.09 : 1.0,
                      duration: const Duration(milliseconds: 170),
                      curve: Curves.easeOut,
                      child: AnimatedContainer(
                      duration: const Duration(milliseconds: 170),
                      curve: Curves.easeOut,
                      decoration: BoxDecoration(
                        // Accent-tinted selection pill so it matches the theme.
                        // No shadow — it read as an odd grey aura on iOS.
                        color: cs.primary.withValues(alpha: dark ? 0.30 : 0.16),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                            color: cs.primary.withValues(alpha: dark ? 0.35 : 0.22),
                            width: 0.5),
                      ),
                    ),
                    ),
                  ),
                  Row(
                    children: [
                      for (var s = 0; s < n; s++)
                        Expanded(
                          child: _isComposeSlot(s)
                              ? _composeItem(context, cs)
                              : _glassTabItem(
                                  context, _tabForSlot(s)!, cs, s, activeSlot),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _glassTabItem(BuildContext context, int tab, ColorScheme cs, int slot,
      int activeSlot) {
    final selected = activeSlot == slot;
    final color = selected ? cs.primary : cs.onSurfaceVariant;
    Widget icon = Icon(selected ? _items[tab].$2 : _items[tab].$1,
        size: 24, color: color);
    final unread = tab == 2 ? widget.unread : 0;
    if (unread > 0) {
      icon = Badge(label: Text(unread > 99 ? '99+' : '$unread'), child: icon);
    }
    // GestureDetector, NOT InkWell: the Material ripple painted a big circular
    // ink "aura" over the glass bar on tap — alien on iOS, where tab bars give
    // no ripple feedback (the sliding pill is the feedback).
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onSelected(tab),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          icon,
          const SizedBox(height: 3),
          Text(_items[tab].$3,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.iconOff,
    required this.iconOn,
    required this.label,
    required this.selected,
    required this.badge,
    required this.onTap,
  });
  final IconData iconOff;
  final IconData iconOn;
  final String label;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final glass = useLiquidGlass;

    // Apple Music: selected content is tinted with the accent; the capsule is a
    // subtle translucent glass highlight (NOT an opaque white block).
    final contentColor = selected
        ? (glass ? cs.primary : cs.onSecondaryContainer)
        : cs.onSurfaceVariant;

    Widget iconW = Icon(selected ? iconOn : iconOff, size: 24, color: contentColor);
    if (badge > 0) {
      iconW = Badge(label: Text(badge > 99 ? '99+' : '$badge'), child: iconW);
    }
    final labelW = Text(
      label,
      style: TextStyle(
          fontSize: 11, fontWeight: FontWeight.w600, color: contentColor),
    );

    if (glass) {
      // Selection capsule wraps the WHOLE item (icon + label), as a soft
      // translucent glass highlight.
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
            color: selected
                ? (dark
                    ? Colors.white.withValues(alpha: 0.14)
                    : Colors.white.withValues(alpha: 0.42))
                : Colors.transparent,
            // Full capsule, echoing the tab bar's rounded shape (not a squircle).
            borderRadius: BorderRadius.circular(999),
            border: selected
                ? Border.all(
                    color: Colors.white.withValues(alpha: dark ? 0.12 : 0.5),
                    width: 0.5)
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [iconW, const SizedBox(height: 3), labelW],
          ),
        ),
      );
    }

    // Material (Android): pill behind the icon, label below.
    return InkWell(
      onTap: onTap,
      customBorder: const StadiumBorder(),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutBack,
            width: 56,
            height: 30,
            decoration: BoxDecoration(
              color: selected ? cs.secondaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            alignment: Alignment.center,
            child: iconW,
          ),
          const SizedBox(height: 4),
          labelW,
        ],
      ),
    );
  }
}

/// Three-dot menu to switch the feed's post display type.
class _DisplayMenu extends ConsumerWidget {
  const _DisplayMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsControllerProvider);
    final ctrl = ref.read(settingsControllerProvider.notifier);
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded),
      tooltip: 'Display',
      onSelected: (v) {
        if (v == 'autoplay') {
          ctrl.setAutoplayMedia(!s.autoplayMedia);
        } else {
          ctrl.setPostDisplay(
              PostDisplay.values.firstWhere((d) => d.name == v));
        }
      },
      itemBuilder: (_) => [
        for (final d in PostDisplay.values)
          PopupMenuItem(
            value: d.name,
            child: Row(
              children: [
                Icon(d.icon, size: 20),
                const SizedBox(width: 12),
                Text(d.label),
                if (d == s.postDisplay) ...[
                  const Spacer(),
                  const Icon(Icons.check_rounded, size: 18),
                ],
              ],
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'autoplay',
          child: Row(
            children: [
              const Icon(Icons.play_circle_outline_rounded, size: 20),
              const SizedBox(width: 12),
              const Text('Autoplay media'),
              const Spacer(),
              if (s.autoplayMedia) const Icon(Icons.check_rounded, size: 18),
            ],
          ),
        ),
      ],
    );
  }
}

class _FrontpageTab extends ConsumerWidget {
  const _FrontpageTab({this.chromeVisible = true});
  final bool chromeVisible;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final username =
        ref.watch(authControllerProvider).valueOrNull?.username ?? '';
    final settings = ref.watch(settingsControllerProvider);
    final forYou = settings.forYouFeed;
    final compact = settings.topBarMode == TopBarMode.compact;
    return Column(
      children: [
        // Full mode: Google-app style search bar with avatar — collapses on
        // scroll. Compact mode hides it (actions move to the bottom nav).
        if (!compact)
          AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: chromeVisible
              ? Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: ref.watch(settingsControllerProvider).showApiUsage
                    ? _ApiUsagePill()
                    : GlassSurface(
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
                                Text('Search Reddit',
                                    style:
                                        TextStyle(color: cs.onSurfaceVariant)),
                              ],
                            ),
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 4),
              IconButton.filled(
                tooltip: 'New post',
                icon: const Icon(Icons.edit_square, size: 22),
                style: IconButton.styleFrom(
                  backgroundColor: cs.primary,
                  foregroundColor: cs.onPrimary,
                ),
                onPressed: () => context.push('/submit'),
              ),
              const _DisplayMenu(),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => context.push('/u/$username'),
                child: CircleAvatar(
                  radius: 22,
                  backgroundColor: cs.primaryContainer,
                  child: Text(
                    username.isNotEmpty ? username[0].toUpperCase() : '?',
                    style: TextStyle(
                        color: cs.onPrimaryContainer,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
                )
              : const SizedBox(width: double.infinity, height: 0),
        ),
        Expanded(
          child: PostListView(
            feedKey: '',
            header: Padding(
              padding: EdgeInsets.fromLTRB(16, compact ? 10 : 8, compact ? 4 : 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    forYou ? 'For You' : 'Frontpage',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  if (forYou) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Personalized on-device · Beta',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant)),
                    ),
                  ] else
                    const Spacer(),
                  // Compact mode keeps search (floating) + the display menu up top.
                  if (compact) ...[
                    IconButton(
                      tooltip: 'Search',
                      icon: const Icon(Icons.search_rounded),
                      onPressed: () => showFloatingSearch(context),
                    ),
                    const _DisplayMenu(),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Shows live Reddit API rate-limit usage in place of the search bar
/// (power-user setting). Reddit allows ~100 requests/minute per OAuth client.
class _ApiUsagePill extends ConsumerWidget {
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
