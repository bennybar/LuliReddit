import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../feed/post_list_view.dart';

class MultiredditFeedScreen extends ConsumerWidget {
  const MultiredditFeedScreen(
      {super.key, required this.username, required this.name});
  final String username;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        actions: [
          IconButton(
            tooltip: 'Manage',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => context.push('/m/$username/$name/manage'),
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
