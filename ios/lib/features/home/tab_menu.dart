import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Opens the side bar (Settings › Navigation: side bar / both); [open] is
/// null when it's off.
class SideBarScope extends InheritedWidget {
  const SideBarScope({super.key, required this.open, required super.child});
  final VoidCallback? open;

  static VoidCallback? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SideBarScope>()?.open;

  @override
  bool updateShouldNotify(SideBarScope old) =>
      (old.open == null) != (open == null);
}

/// The ☰ at the start of a tab's top bar, when the side bar is on. Every tab
/// places it the same: 4px from the edge and 8px from the top of the tab
/// (the Inbox's app bar puts it there itself), so it doesn't shift as you
/// switch tabs.
class SideBarButton extends StatelessWidget {
  const SideBarButton({super.key});

  @override
  Widget build(BuildContext context) {
    final open = SideBarScope.of(context);
    if (open == null) return const SizedBox.shrink();
    return IconButton(
      tooltip: 'Open menu',
      icon: const Icon(Icons.menu_rounded),
      onPressed: open,
    );
  }
}

/// The ⚙ at the top of a tab's main screen: straight to Settings.
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Settings',
        icon: const Icon(Icons.settings_outlined),
        onPressed: () => context.push('/settings'),
      );
}
