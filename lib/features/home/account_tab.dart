import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../auth/auth_controller.dart';
import '../auth/web_login_screen.dart';
import '../explore/explore_screen.dart';
import '../feed/feed_controller.dart';
import '../inbox/inbox_controller.dart';
import '../multireddit/multireddit_providers.dart';
import '../settings/settings_screen.dart';

/// Refreshes all account-scoped data after switching/adding/removing an account.
void _resetAccountData(WidgetRef ref) {
  ref.read(redditRepositoryProvider).clearSubsCache();
  ref.invalidate(feedControllerProvider);
  ref.invalidate(inboxControllerProvider);
  ref.invalidate(unreadCountProvider);
  ref.invalidate(subscribedSubredditsProvider);
  ref.invalidate(myMultiredditsProvider);
}

class AccountTab extends ConsumerWidget {
  const AccountTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final username =
        ref.watch(authControllerProvider).valueOrNull?.username ?? '';

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // Profile header
        Padding(
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
                    InkWell(
                      onTap: () => _showAccountSheet(context, ref, username),
                      borderRadius: BorderRadius.circular(8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text('u/$username',
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w700)),
                          ),
                          const Icon(Icons.unfold_more_rounded, size: 20),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => context.push('/u/$username'),
                      style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 0),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                      child: const Text('View profile'),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Switch / add account',
                onPressed: () => _showAccountSheet(context, ref, username),
                icon: const Icon(Icons.people_alt_rounded),
              ),
            ],
          ),
        ),

        // Settings (primary)
        const SettingsList(embedded: true),

        const Divider(),

        // Custom feeds (secondary)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text('Custom feeds',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(
                            color: cs.primary, fontWeight: FontWeight.w700)),
              ),
              TextButton.icon(
                onPressed: () => _createMulti(context, ref, username),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('New'),
              ),
            ],
          ),
        ),
        ref.watch(myMultiredditsProvider).when(
              loading: () => const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator())),
              error: (e, _) => const SizedBox.shrink(),
              data: (multis) => Column(
                children: [
                  for (final m in multis)
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: cs.tertiaryContainer,
                        foregroundColor: cs.onTertiaryContainer,
                        child: const Icon(Icons.dynamic_feed_rounded, size: 20),
                      ),
                      title: Text(m.displayName),
                      subtitle: Text('${m.subreddits.length} subreddits'),
                      onTap: () => context.push('/m/$username/${m.name}'),
                    ),
                ],
              ),
            ),
        const SizedBox(height: 130),
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

  void _showAccountSheet(BuildContext context, WidgetRef ref, String current) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Consumer(
        builder: (ctx, ref2, _) {
          final cs = Theme.of(ctx).colorScheme;
          final accounts =
              ref2.watch(accountsProvider).valueOrNull ?? [current];
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Accounts',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
                for (final a in accounts)
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: cs.primaryContainer,
                      foregroundColor: cs.onPrimaryContainer,
                      child: Text(a.isNotEmpty ? a[0].toUpperCase() : '?'),
                    ),
                    title: Text('u/$a'),
                    selected: a == current,
                    trailing: a == current
                        ? Icon(Icons.check_circle_rounded, color: cs.primary)
                        : IconButton(
                            tooltip: 'Remove',
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () =>
                                _confirmRemove(context, ref, a),
                          ),
                    onTap: a == current
                        ? null
                        : () async {
                            Navigator.pop(ctx);
                            await ref
                                .read(authControllerProvider.notifier)
                                .switchAccount(a);
                            _resetAccountData(ref);
                          },
                  ),
                const Divider(height: 8),
                ListTile(
                  leading: const Icon(Icons.person_add_alt_1_rounded),
                  title: const Text('Add account'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _addAccount(context, ref);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.logout_rounded, color: cs.error),
                  title: Text('Log out of u/$current',
                      style: TextStyle(color: cs.error)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _confirmRemove(context, ref, current);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _addAccount(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final isWeb = ref.read(authModeProvider).valueOrNull == 'web';
    try {
      if (isWeb) {
        // Match the current method: website-session add (fresh cookies).
        final cookie = await Navigator.of(context).push<String>(
          MaterialPageRoute(
              builder: (_) => const WebLoginScreen(clearFirst: true)),
        );
        if (cookie == null || cookie.isEmpty) return;
        await ref.read(authControllerProvider.notifier).loginWithWebSession(cookie);
      } else {
        await ref.read(authControllerProvider.notifier).addAccount();
      }
      _resetAccountData(ref);
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text(
              'Could not add account: ${'$e'.replaceFirst('Exception: ', '')}')));
    }
  }

  Future<void> _confirmRemove(
      BuildContext context, WidgetRef ref, String username) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Log out of u/$username?'),
        content: const Text(
            'This removes the account from this device. Your saved API '
            'credentials stay so you can add it again.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Log out')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(authControllerProvider.notifier).removeAccount(username);
      _resetAccountData(ref);
    }
  }
}
