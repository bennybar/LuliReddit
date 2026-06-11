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
import '../settings/settings_controller.dart';
import '../updates/update_checker.dart';
import 'account_tab.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeCheckUpdates());
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
  });
  final int selectedIndex;
  final int unread;
  final ValueChanged<int> onSelected;

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
    _from = _to = widget.selectedIndex.toDouble();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
  }

  @override
  void didUpdateWidget(_FloatingNav old) {
    super.didUpdateWidget(old);
    if (_fromDrag) {
      _fromDrag = false; // drag already ran its own snap animation
      return;
    }
    if (old.selectedIndex != widget.selectedIndex) {
      _from = _displayed; // smooth interrupt mid-flight
      _to = widget.selectedIndex.toDouble();
      _c.forward(from: 0);
    }
  }

  double get _displayed =>
      lerpDouble(_from, _to, Curves.easeOutCubic.transform(_c.value))!;

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

  // Android: standard Material pills.
  Widget _material(BuildContext context) => Row(
        children: [
          for (var i = 0; i < _items.length; i++)
            Expanded(
              child: _NavItem(
                iconOff: _items[i].$1,
                iconOn: _items[i].$2,
                label: _items[i].$3,
                selected: widget.selectedIndex == i,
                badge: i == 2 ? widget.unread : 0,
                onTap: () => widget.onSelected(i),
              ),
            ),
        ],
      );

  // iOS: a single sliding/stretching glass capsule behind the items.
  Widget _glass(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, bc) {
        final w = bc.maxWidth;
        final n = _items.length;
        final iw = w / n;
        final capBase = iw - 14;

        // Finger x → fractional tab index (capsule centre follows the thumb).
        double idxFromX(double x) =>
            ((x - iw / 2) / iw).clamp(0.0, (n - 1).toDouble());

        void onDown(double x) => setState(() => _drag = idxFromX(x));
        void onMove(double x) => setState(() => _drag = idxFromX(x));
        void onUp() {
          final idx = (_drag ?? widget.selectedIndex.toDouble())
              .round()
              .clamp(0, n - 1);
          _from = _drag ?? idx.toDouble();
          _to = idx.toDouble();
          _drag = null;
          _fromDrag = true;
          _c.forward(from: 0);
          widget.onSelected(idx);
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
              final active =
                  (_drag != null ? _drag!.round() : widget.selectedIndex)
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
                      for (var i = 0; i < n; i++)
                        Expanded(child: _glassItem(context, i, cs, active)),
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

  Widget _glassItem(
      BuildContext context, int i, ColorScheme cs, int activeIndex) {
    final selected = activeIndex == i;
    final color = selected ? cs.primary : cs.onSurfaceVariant;
    Widget icon =
        Icon(selected ? _items[i].$2 : _items[i].$1, size: 24, color: color);
    final unread = i == 2 ? widget.unread : 0;
    if (unread > 0) {
      icon = Badge(label: Text(unread > 99 ? '99+' : '$unread'), child: icon);
    }
    // GestureDetector, NOT InkWell: the Material ripple painted a big circular
    // ink "aura" over the glass bar on tap — alien on iOS, where tab bars give
    // no ripple feedback (the sliding pill is the feedback).
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onSelected(i),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          icon,
          const SizedBox(height: 3),
          Text(_items[i].$3,
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
    final forYou = ref.watch(settingsControllerProvider).forYouFeed;
    return Column(
      children: [
        // Google-app style search bar with avatar — collapses on scroll.
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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
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
