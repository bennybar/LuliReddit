import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/share.dart';
import '../../core/widgets/error_view.dart';
import '../auth/auth_controller.dart';
import '../feed/post_list_view.dart';
import 'custom_feeds_screen.dart' show editFeedDialog;
import 'multireddit_providers.dart';

/// A custom feed (multireddit): its posts, with a shortcut to manage it.
class MultiredditFeedScreen extends ConsumerWidget {
  const MultiredditFeedScreen(
      {super.key, required this.username, required this.name});
  final String username;
  final String name;

  /// Someone's public feed: make your own copy of it (Reddit's "Copy custom
  /// feed").
  Future<void> _copy(BuildContext context, WidgetRef ref, String me) async {
    final messenger = ScaffoldMessenger.of(context);
    final e = await editFeedDialog(context,
        title: 'Copy to your feeds',
        confirm: 'Copy',
        name: name.replaceAll('_', ' '),
        description: '',
        visibility: 'private');
    if (e == null) return;
    try {
      await ref
          .read(redditRepositoryProvider)
          .copyMultireddit('/user/$username/m/$name', me, e.displayName);
      ref.invalidate(myMultiredditsProvider);
      messenger.showSnackBar(
          const SnackBar(content: Text('Copied to your custom feeds')));
    } catch (ex) {
      if (context.mounted) showActionError(context, 'copy the feed', ex);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(
            authControllerProvider.select((a) => a.valueOrNull?.username)) ??
        '';
    final mine = username.toLowerCase() == me.toLowerCase();
    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        actions: [
          if (mine)
            IconButton(
              tooltip: 'Manage',
              icon: const Icon(Icons.tune_rounded),
              onPressed: () => context.push('/m/$username/$name/manage'),
            )
          else if (me.isNotEmpty)
            IconButton(
              tooltip: 'Copy to your feeds',
              icon: const Icon(Icons.content_copy_rounded),
              onPressed: () => _copy(context, ref, me),
            ),
          IconButton(
            tooltip: 'Share link',
            icon: const Icon(Icons.share_outlined),
            onPressed: () => shareUrl(
                context, 'https://www.reddit.com/user/$username/m/$name/'),
          ),
        ],
      ),
      body: PostListView(
        feedKey: 'm::$username::$name',
        header: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(name,
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
        ),
      ),
    );
  }
}
