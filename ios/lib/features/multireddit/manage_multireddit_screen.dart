import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/share.dart';
import '../../core/widgets/loading.dart';
import '../../models/multireddit.dart';
import 'custom_feeds_screen.dart' show editFeedDialog;
import 'multireddit_providers.dart';
import '../../core/widgets/error_view.dart';

class ManageMultiredditScreen extends ConsumerWidget {
  const ManageMultiredditScreen(
      {super.key, required this.username, required this.name});
  final String username;
  final String name;

  /// After a change: this feed and the shared list (Explore, Custom feeds).
  void _reload(WidgetRef ref) {
    ref.invalidate(multiredditByNameProvider(name));
    ref.invalidate(myMultiredditsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(multiredditByNameProvider(name));
    final repo = ref.read(redditRepositoryProvider);
    final cs = Theme.of(context).colorScheme;
    final title = async.valueOrNull?.displayName;

    return Scaffold(
      appBar: AppBar(
        title: Text(title == null || title.isEmpty ? name : title),
        actions: [
          IconButton(
            tooltip: 'Edit name, description, visibility',
            icon: const Icon(Icons.edit_rounded),
            onPressed: () async {
              final multi = async.valueOrNull;
              if (multi == null) return;
              final e = await editFeedDialog(context,
                  title: 'Edit feed',
                  confirm: 'Save',
                  name: multi.displayName,
                  description: multi.descriptionMd,
                  visibility: multi.visibility);
              if (e == null) return;
              try {
                await repo.updateMultireddit(multi,
                    displayName: e.displayName,
                    description: e.description,
                    visibility: e.visibility);
                _reload(ref);
              } catch (ex) {
                if (context.mounted) {
                  showActionError(context, 'update the feed', ex);
                }
              }
            },
          ),
          IconButton(
            tooltip: 'Share link',
            icon: const Icon(Icons.share_outlined),
            onPressed: () => shareUrl(
                context, 'https://www.reddit.com/user/$username/m/$name/'),
          ),
          IconButton(
            tooltip: 'Delete feed',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () async {
              final multi = async.valueOrNull;
              if (multi == null) return;
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text('Delete "$name"?'),
                  content: const Text('This custom feed will be removed.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Delete')),
                  ],
                ),
              );
              if (ok != true) return;
              try {
                await repo.deleteMultireddit(multi.path);
                ref.invalidate(myMultiredditsProvider);
                if (context.mounted) context.pop();
              } catch (e) {
                if (context.mounted) {
                  showActionError(context, 'delete the feed', e);
                }
              }
            },
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: Loading()),
        error: (e, _) => Center(child: Text('Could not load feed: ${friendlyError(e)}')),
        data: (multi) {
          if (multi == null) {
            return const Center(child: Text('Feed not found'));
          }
          final subs = multi.subreddits;
          // Header (privacy + description), Add, then one row per community.
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 32),
            itemCount: 2 + (subs.isEmpty ? 1 : subs.length),
            itemBuilder: (_, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(
                      (multi.visibility == 'public'
                              ? 'Public: anyone with the link can see it'
                              : 'Private: only you can see it') +
                          (multi.descriptionMd.trim().isNotEmpty
                              ? '\n\n${multi.descriptionMd}'
                              : ''),
                      style: TextStyle(color: cs.onSurfaceVariant)),
                );
              }
              if (i == 1) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: FilledButton.tonalIcon(
                      onPressed: () => _addSubreddit(context, ref, multi),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Add subreddit'),
                    ),
                  ),
                );
              }
              if (subs.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text('No subreddits yet')),
                );
              }
              final sr = subs[i - 2];
              return ListTile(
                key: ValueKey(sr),
                leading: const Icon(Icons.subdirectory_arrow_right_rounded),
                title: Text('r/$sr'),
                onTap: () => context.push('/r/$sr'),
                trailing: IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () async {
                    try {
                      await repo.removeSubredditFromMulti(multi.path, sr);
                    } catch (e) {
                      if (context.mounted) {
                        showActionError(context, 'remove r/$sr', e);
                      }
                    }
                    _reload(ref);
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _addSubreddit(
      BuildContext context, WidgetRef ref, Multireddit multi) async {
    final controller = TextEditingController();
    final sr = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add subreddit'),
        content: TextField(
          controller: controller,
          autofocus: true,
          autocorrect: false,
          decoration: InputDecoration(
            prefixText: 'r/',
            labelText: 'Name',
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Add')),
        ],
      ),
    );
    if (sr == null || sr.isEmpty) return;
    try {
      await ref
          .read(redditRepositoryProvider)
          .addSubredditToMulti(multi.path, sr);
    } catch (e) {
      if (context.mounted) showActionError(context, 'add r/$sr', e);
    }
    _reload(ref);
  }
}
