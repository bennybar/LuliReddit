import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/drafts.dart';
import '../../core/providers.dart';
import '../auth/auth_controller.dart';
import '../auth/web_login_screen.dart';
import '../multireddit/multireddit_providers.dart';
import '../user/user_screen.dart';
import 'tab_menu.dart';

/// The Profile tab: your profile (Posts, Comments, Saved, Upvoted) under a
/// bar with the account switcher and Settings, and a "Your stuff" row for
/// what's kept on this device. Browsing without an account: sign in, plus
/// your stuff.
class ProfileTab extends ConsumerWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final username = ref.watch(
            authControllerProvider.select((a) => a.valueOrNull?.username)) ??
        '';
    final anonymous = ref.watch(authControllerProvider
            .select((a) => a.valueOrNull?.anonymous)) ??
        false;
    final sideBar = SideBarScope.of(context) != null;

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(sideBar ? 4 : 16, 8, 4, 0),
          child: Row(
            children: [
              const SideBarButton(),
              Expanded(
                child: Text('Profile',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ),
              if (!anonymous)
                IconButton(
                  tooltip: 'Switch / add account',
                  icon: const Icon(Icons.people_alt_rounded),
                  onPressed: () => _showAccountSheet(context, ref, username),
                ),
              const SettingsButton(),
            ],
          ),
        ),
        Expanded(
          child: anonymous || username.isEmpty
              ? ListView(
                  padding: const EdgeInsets.only(bottom: 130),
                  children: [
                    const SignInPrompt(
                        message: 'You\'re browsing without an account. Sign '
                            'in to vote, comment, save, see your inbox and get '
                            'your own frontpage.'),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Text('Your stuff',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w700)),
                    ),
                    ListTile(
                      leading: const Icon(Icons.history_rounded),
                      title: const Text('History'),
                      subtitle:
                          const Text('Recently viewed (stored on this device)'),
                      onTap: () => context.push('/history'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.offline_pin_rounded),
                      title: const Text('Read later'),
                      subtitle: const Text('Threads saved for offline reading'),
                      onTap: () => context.push('/offline'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.auto_awesome_rounded),
                      title: const Text('Summaries'),
                      subtitle: const Text(
                          'Posts you summarized with AI, and their summaries'),
                      onTap: () => context.push('/summaries'),
                    ),
                  ],
                )
              : UserProfileBody(
                  username: username, belowHeader: const _YourStuffRow()),
        ),
      ],
    );
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
    }
  }
}

/// History, Read later, Drafts, Summaries and saved search, as one row of
/// chips.
class _YourStuffRow extends ConsumerWidget {
  const _YourStuffRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final drafts = ref.watch(draftListProvider.select((l) => l.length));
    final chips = [
      (Icons.history_rounded, 'History', '/history'),
      (Icons.offline_pin_rounded, 'Read later', '/offline'),
      (
        Icons.edit_note_rounded,
        drafts == 0 ? 'Drafts' : 'Drafts · $drafts',
        '/drafts'
      ),
      (Icons.auto_awesome_rounded, 'Summaries', '/summaries'),
      (Icons.bookmark_border_rounded, 'Search saved', '/saved'),
    ];
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => Center(
          child: ActionChip(
            key: ValueKey(chips[i].$3),
            onPressed: () => context.push(chips[i].$3),
            avatar: Icon(chips[i].$1, size: 18, color: cs.onSecondaryContainer),
            label: Text(chips[i].$2),
            shape: const StadiumBorder(),
            side: BorderSide.none,
            backgroundColor: cs.surfaceContainerHigh,
          ),
        ),
      ),
    );
  }
}

/// Asks for a name and creates a custom feed (holding [subreddits]); true if
/// it was created.
Future<bool> createMulti(BuildContext context, WidgetRef ref, String username,
    [List<String> subreddits = const []]) async {
  final messenger = ScaffoldMessenger.of(context);
  final controller = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('New custom feed'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: 'Feed name',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
        ),
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
  controller.dispose();
  if (name == null || name.isEmpty) return false;
  try {
    await ref.read(redditRepositoryProvider).createMultireddit(
        username: username, name: name, subreddits: subreddits);
    ref.invalidate(myMultiredditsProvider);
    return true;
  } catch (e) {
    messenger.showSnackBar(SnackBar(
        content: Text(
            'Could not create feed: ${'$e'.replaceFirst('Exception: ', '')}')));
    return false;
  }
}

/// Shown where an account is needed while browsing without one: explains it
/// and offers to sign in (which goes back to the login screen).
class SignInPrompt extends ConsumerWidget {
  const SignInPrompt({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.travel_explore_rounded, color: cs.primary),
                const SizedBox(width: 10),
                Text('Browsing without an account',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 8),
              Text(message),
              const SizedBox(height: 12),
              FilledButton.icon(
                icon: const Icon(Icons.login_rounded),
                label: const Text('Sign in'),
                // Ends the anonymous session; the router then shows login
                // (the Client ID stays filled in).
                onPressed: () =>
                    ref.read(authControllerProvider.notifier).logout(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
