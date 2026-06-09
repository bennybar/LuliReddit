import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import 'multireddit_providers.dart';

class ManageMultiredditScreen extends ConsumerWidget {
  const ManageMultiredditScreen({super.key, required this.name});
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(multiredditByNameProvider(name));
    final repo = ref.read(redditRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        actions: [
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
              if (ok == true) {
                await repo.deleteMultireddit(multi.path);
                ref.invalidate(myMultiredditsProvider);
                if (context.mounted) context.pop();
              }
            },
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load feed: $e')),
        data: (multi) {
          if (multi == null) {
            return const Center(child: Text('Feed not found'));
          }
          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.tonalIcon(
                  onPressed: () => _addSubreddit(context, ref, multi.path),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add subreddit'),
                ),
              ),
              for (final sr in multi.subreddits)
                ListTile(
                  leading: const Icon(Icons.subdirectory_arrow_right_rounded),
                  title: Text('r/$sr'),
                  trailing: IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () async {
                      await repo.removeSubredditFromMulti(multi.path, sr);
                      ref.invalidate(multiredditByNameProvider(name));
                    },
                  ),
                ),
              if (multi.subreddits.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text('No subreddits yet')),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _addSubreddit(
      BuildContext context, WidgetRef ref, String path) async {
    final controller = TextEditingController();
    final sr = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add subreddit'),
        content: TextField(
          controller: controller,
          autofocus: true,
          autocorrect: false,
          decoration: const InputDecoration(prefixText: 'r/', labelText: 'Name'),
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
    if (sr != null && sr.isNotEmpty) {
      await ref.read(redditRepositoryProvider).addSubredditToMulti(path, sr);
      ref.invalidate(multiredditByNameProvider(name));
    }
  }
}
