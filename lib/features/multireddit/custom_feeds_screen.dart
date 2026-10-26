import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_controller.dart';
import '../home/account_tab.dart' show createMulti;
import 'multireddit_providers.dart';

/// Your custom feeds (side bar → Custom feeds).
// TODO(custom-feeds): the custom feeds area ports Kotlin's CustomFeedsScreen
// (rename, describe, privacy, share, copy); this is the list the old Account
// tab had, so they stay reachable meanwhile.
class CustomFeedsScreen extends ConsumerWidget {
  const CustomFeedsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final username = ref.watch(
            authControllerProvider.select((a) => a.valueOrNull?.username)) ??
        '';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Custom feeds'),
        actions: [
          IconButton(
            tooltip: 'New feed',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => createMulti(context, ref, username),
          ),
        ],
      ),
      body: ref.watch(myMultiredditsProvider).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => const SizedBox.shrink(),
            data: (multis) => multis.isEmpty
                ? Center(
                    child: FilledButton(
                      onPressed: () => createMulti(context, ref, username),
                      child: const Text('New feed'),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 32),
                    itemCount: multis.length,
                    itemBuilder: (_, i) {
                      final m = multis[i];
                      return ListTile(
                        key: ValueKey(m.name),
                        leading: CircleAvatar(
                          backgroundColor: cs.tertiaryContainer,
                          foregroundColor: cs.onTertiaryContainer,
                          child:
                              const Icon(Icons.dynamic_feed_rounded, size: 20),
                        ),
                        title: Text(m.displayName),
                        subtitle: Text('${m.subreddits.length} subreddits'),
                        onTap: () => context.push('/m/$username/${m.name}'),
                      );
                    },
                  ),
          ),
    );
  }
}
