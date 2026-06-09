import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/share.dart';
import '../../models/subreddit.dart';
import '../feed/post_list_view.dart';

final subredditAboutProvider =
    FutureProvider.autoDispose.family<Subreddit, String>((ref, name) {
  return ref.watch(redditRepositoryProvider).getSubredditAbout(name);
});

class SubredditScreen extends ConsumerStatefulWidget {
  const SubredditScreen({super.key, required this.name});
  final String name;

  @override
  ConsumerState<SubredditScreen> createState() => _SubredditScreenState();
}

class _SubredditScreenState extends ConsumerState<SubredditScreen> {
  bool? _subOverride; // optimistic subscribe state

  @override
  Widget build(BuildContext context) {
    final about = ref.watch(subredditAboutProvider(widget.name));
    return Scaffold(
      appBar: AppBar(
        title: Text('r/${widget.name}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            onPressed: () => context.push('/search?sr=${widget.name}'),
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () =>
                shareUrl('https://reddit.com/r/${widget.name}'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/submit?sr=${widget.name}'),
        child: const Icon(Icons.edit_rounded),
      ),
      body: PostListView(
        feedKey: widget.name,
        header: about.when(
          loading: () => const SizedBox(height: 4, child: LinearProgressIndicator()),
          error: (_, __) => const SizedBox.shrink(),
          data: (s) => _header(context, s),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, Subreddit s) {
    final cs = Theme.of(context).colorScheme;
    final subscribed = _subOverride ?? s.userIsSubscriber ?? false;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (s.bannerUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: CachedNetworkImage(
                imageUrl: s.bannerUrl!,
                height: 110,
                width: double.infinity,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 26,
                          backgroundColor: cs.secondaryContainer,
                          foregroundColor: cs.onSecondaryContainer,
                          backgroundImage: s.iconUrl != null
                              ? CachedNetworkImageProvider(s.iconUrl!)
                              : null,
                          child: s.iconUrl == null
                              ? Text(s.name.isNotEmpty
                                  ? s.name[0].toUpperCase()
                                  : '?')
                              : null,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.namePrefixed,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w800)),
                              Text('${compactNumber(s.subscribers)} members',
                                  style:
                                      TextStyle(color: cs.onSurfaceVariant)),
                            ],
                          ),
                        ),
                        FilledButton.tonal(
                          onPressed: () => _toggleSub(s, subscribed),
                          child: Text(subscribed ? 'Joined' : 'Join'),
                        ),
                      ],
                    ),
                    if (s.description.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(s.description,
                          style: TextStyle(color: cs.onSurfaceVariant)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleSub(Subreddit s, bool currentlySubscribed) async {
    final next = !currentlySubscribed;
    setState(() => _subOverride = next);
    try {
      await ref.read(redditRepositoryProvider).setSubscribed(s.name, next);
    } catch (_) {
      if (mounted) setState(() => _subOverride = currentlySubscribed);
    }
  }
}
