import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../auth/auth_controller.dart';
import '../multireddit/multireddit_providers.dart';

class AccountTab extends ConsumerWidget {
  const AccountTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final username =
        ref.watch(authControllerProvider).valueOrNull?.username ?? '';

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: cs.primaryContainer,
                  child: Text(
                    username.isNotEmpty ? username[0].toUpperCase() : '?',
                    style: TextStyle(
                        fontSize: 22,
                        color: cs.onPrimaryContainer,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('u/$username',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      TextButton(
                        onPressed: () => context.push('/u/$username'),
                        style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 0),
                            tapTargetSize:
                                MaterialTapTargetSize.shrinkWrap),
                        child: const Text('View profile'),
                      ),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: 'Settings',
                  onPressed: () => context.push('/settings'),
                  icon: const Icon(Icons.settings_rounded),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Log out',
                  onPressed: () => _confirmLogout(context, ref),
                  icon: const Icon(Icons.logout_rounded),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text('Custom feeds',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                TextButton.icon(
                  onPressed: () => _createMulti(context, ref, username),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('New'),
                ),
              ],
            ),
          ),
        ),
        ref.watch(myMultiredditsProvider).when(
              loading: () => const SliverToBoxAdapter(
                  child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()))),
              error: (e, _) => const SliverToBoxAdapter(child: SizedBox.shrink()),
              data: (multis) => SliverList.builder(
                itemCount: multis.length,
                itemBuilder: (context, i) {
                  final m = multis[i];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: cs.tertiaryContainer,
                      foregroundColor: cs.onTertiaryContainer,
                      child: const Icon(Icons.dynamic_feed_rounded, size: 20),
                    ),
                    title: Text(m.displayName),
                    subtitle: Text('${m.subreddits.length} subreddits'),
                    onTap: () => context.push('/m/$username/${m.name}'),
                  );
                },
              ),
            ),
        const SliverToBoxAdapter(child: SizedBox(height: 130)),
      ],
    );
  }

  Future<void> _createMulti(
      BuildContext context, WidgetRef ref, String username) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New custom feed'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Feed name'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Create')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      await ref
          .read(redditRepositoryProvider)
          .createMultireddit(username: username, name: name);
      ref.invalidate(myMultiredditsProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text('Could not create feed: ${'$e'.replaceFirst('Exception: ', '')}')));
      }
    }
  }

  void _confirmLogout(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
            'You will need to sign in again. Your saved API credentials stay '
            'on this device.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(authControllerProvider.notifier).logout();
            },
            child: const Text('Log out'),
          ),
        ],
      ),
    );
  }
}
