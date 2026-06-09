import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

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
          onSelected: (i) => setState(() {
            _index = i;
            _chrome = true; // always reveal chrome when switching tabs
          }),
        ),
      ),
    );
  }
}

/// "Pop" floating pill navigation: a detached, fully-rounded bar that hovers
/// above the content with a soft shadow and an animated selected pill.
class _FloatingNav extends StatelessWidget {
  const _FloatingNav({
    required this.selectedIndex,
    required this.unread,
    required this.onSelected,
  });
  final int selectedIndex;
  final int unread;
  final ValueChanged<int> onSelected;

  static const _items = [
    (Icons.home_outlined, Icons.home_rounded, 'Posts'),
    (Icons.explore_outlined, Icons.explore_rounded, 'Explore'),
    (Icons.mail_outline_rounded, Icons.mail_rounded, 'Inbox'),
    (Icons.account_circle_outlined, Icons.account_circle_rounded, 'Account'),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
        child: Material(
          color: cs.surfaceContainerHigh,
          elevation: 6,
          shadowColor: Colors.black.withValues(alpha: 0.25),
          shape: const StadiumBorder(),
          child: SizedBox(
            height: 70,
            child: Row(
              children: [
                for (var i = 0; i < _items.length; i++)
                  Expanded(
                    child: _NavItem(
                      iconOff: _items[i].$1,
                      iconOn: _items[i].$2,
                      label: _items[i].$3,
                      selected: selectedIndex == i,
                      badge: i == 2 ? unread : 0,
                      onTap: () => onSelected(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
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
    Widget icon = Icon(
      selected ? iconOn : iconOff,
      size: 24,
      color: selected ? cs.onSecondaryContainer : cs.onSurfaceVariant,
    );
    if (badge > 0) {
      icon = Badge(label: Text(badge > 99 ? '99+' : '$badge'), child: icon);
    }
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
            child: icon,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: selected ? cs.onSurface : cs.onSurfaceVariant,
            ),
          ),
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
    final current = ref.watch(settingsControllerProvider).postDisplay;
    return PopupMenuButton<PostDisplay>(
      icon: const Icon(Icons.more_vert_rounded),
      tooltip: 'Display',
      onSelected: (d) =>
          ref.read(settingsControllerProvider.notifier).setPostDisplay(d),
      itemBuilder: (_) => [
        for (final d in PostDisplay.values)
          PopupMenuItem(
            value: d,
            child: Row(
              children: [
                Icon(d.icon, size: 20),
                const SizedBox(width: 12),
                Text(d.label),
                if (d == current) ...[
                  const Spacer(),
                  const Icon(Icons.check_rounded, size: 18),
                ],
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
                child: Material(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(28),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(28),
                    onTap: () => context.push('/search'),
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      child: Row(
                        children: [
                          Icon(Icons.search_rounded,
                              color: cs.onSurfaceVariant),
                          const SizedBox(width: 12),
                          Text('Search Reddit',
                              style: TextStyle(color: cs.onSurfaceVariant)),
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
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    forYou ? 'For You' : 'Frontpage',
                    style: Theme.of(context)
                        .textTheme
                        .headlineLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  if (forYou)
                    Text('Personalized on-device · Beta',
                        style: TextStyle(
                            fontSize: 12.5, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
