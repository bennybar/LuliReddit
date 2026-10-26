import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/share.dart';
import '../../core/widgets/image_decode.dart';
import '../../models/flair.dart';
import '../../models/subreddit.dart';
import '../auth/auth_controller.dart';
import '../feed/post_card.dart' show LetterAvatar;
import '../feed/post_list_view.dart';
import '../multireddit/add_to_custom_feed.dart';
import '../../core/widgets/error_view.dart';

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
    final anonymous = ref.watch(authControllerProvider
            .select((a) => a.valueOrNull?.anonymous)) ??
        true;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('r/${widget.name}'),
        actions: [
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search_rounded),
            onPressed: () => context.push('/search?sr=${widget.name}'),
          ),
          IconButton(
            tooltip: 'About & rules',
            icon: const Icon(Icons.info_outline_rounded),
            onPressed: () => _showAbout(context),
          ),
          if (!anonymous &&
              !const {'all', 'popular'}.contains(widget.name.toLowerCase()))
            IconButton(
              tooltip: 'Add to a custom feed',
              icon: const Icon(Icons.playlist_add_rounded),
              onPressed: () => showAddToCustomFeed(context, widget.name),
            ),
          IconButton(
            tooltip: 'Share',
            icon: const Icon(Icons.share_outlined),
            onPressed: () =>
                shareUrl(context, 'https://reddit.com/r/${widget.name}'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'New post',
        onPressed: () => context.push('/submit?sr=${widget.name}'),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: cs.primaryContainer,
        foregroundColor: cs.onPrimaryContainer,
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

  void _showAbout(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (ctx, scroll) {
          final about =
              ref.read(subredditAboutProvider(widget.name)).valueOrNull;
          final signedIn = !(ref.read(authControllerProvider).valueOrNull
                  ?.anonymous ??
              true);
          return ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            children: [
              Text('r/${widget.name}',
                  style: Theme.of(ctx)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              if (about != null && about.title.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(about.title,
                      style: Theme.of(ctx).textTheme.bodyMedium),
                ),
              if (about != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('${compactNumber(about.subscribers)} members',
                      style: TextStyle(
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                ),
              if (signedIn) _YourFlair(sub: widget.name),
              if (about != null && about.description.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(about.description),
              ],
              const SizedBox(height: 18),
              Text('Rules',
                  style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.primary,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              FutureBuilder<List<(String, String)>>(
                future: ref
                    .read(redditRepositoryProvider)
                    .getSubredditRules(widget.name),
                builder: (ctx, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()));
                  }
                  final rules = snap.data ?? const [];
                  if (rules.isEmpty) return const Text('No rules listed.');
                  return Column(
                    children: [
                      for (var i = 0; i < rules.length; i++)
                        Theme(
                          data: Theme.of(ctx)
                              .copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            title: Text('${i + 1}. ${rules[i].$1}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            childrenPadding:
                                const EdgeInsets.only(bottom: 12),
                            children: [
                              if (rules[i].$2.isNotEmpty)
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(rules[i].$2),
                                ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          );
        },
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
                memCacheWidth: feedDecodeWidth(context),
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
                        LetterAvatar(
                            name: s.name,
                            size: 52,
                            container: cs.secondaryContainer,
                            content: cs.onSecondaryContainer,
                            imageUrl: s.iconUrl),
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
                        // One toggle: its shape and fill change with the
                        // state, and it reads as on/off.
                        Semantics(
                          toggled: subscribed,
                          child: FilledButton(
                            onPressed: () => _toggleSub(s, subscribed),
                            style: FilledButton.styleFrom(
                              backgroundColor: subscribed
                                  ? cs.secondary
                                  : cs.secondaryContainer,
                              foregroundColor: subscribed
                                  ? cs.onSecondary
                                  : cs.onSecondaryContainer,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                      subscribed ? 12 : 20)),
                            ),
                            child: Text(subscribed ? 'Joined' : 'Join'),
                          ),
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
    } catch (e) {
      if (!mounted) return;
      setState(() => _subOverride = currentlySubscribed);
      showActionError(context, next ? 'join' : 'leave', e);
    }
  }
}

/// Your user flair in r/[sub]: what it is, and Change when the community
/// offers flair you can pick (No flair, a choice, or your own words where a
/// choice allows it).
class _YourFlair extends ConsumerStatefulWidget {
  const _YourFlair({required this.sub});
  final String sub;

  @override
  ConsumerState<_YourFlair> createState() => _YourFlairState();
}

class _YourFlairState extends ConsumerState<_YourFlair> {
  late Future<UserFlairSelector> _selector = _load();

  Future<UserFlairSelector> _load() =>
      ref.read(redditRepositoryProvider).getUserFlairSelector(widget.sub);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<UserFlairSelector>(
      future: _selector,
      builder: (context, snap) {
        final s = snap.data;
        final label = snap.connectionState != ConnectionState.done
            ? 'Your flair: …'
            : s == null
                ? "Your flair: couldn't load"
                : s.currentText != null
                    ? 'Your flair: ${s.currentText}'
                    : s.choices.isEmpty
                        ? 'No user flair in this community'
                        : 'Your flair: none';
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(children: [
            Expanded(
                child:
                    Text(label, style: TextStyle(color: cs.onSurfaceVariant))),
            if (s != null && s.choices.isNotEmpty)
              TextButton(
                onPressed: () async {
                  if (await pickUserFlair(context, ref, widget.sub, s)) {
                    setState(() => _selector = _load());
                  }
                },
                child: const Text('Change'),
              ),
          ]),
        );
      },
    );
  }
}

/// Picks and sets your flair in [sub]; true if it changed.
Future<bool> pickUserFlair(BuildContext context, WidgetRef ref, String sub,
    UserFlairSelector s) async {
  final messenger = ScaffoldMessenger.of(context);
  final cs = Theme.of(context).colorScheme;
  // A choice, or this marker for "No flair".
  const noFlair = UserFlairChoice(id: '', text: '', editable: false);
  final picked = await showModalBottomSheet<UserFlairChoice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
        child: ListView.builder(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 8),
          itemCount: s.choices.length + 2,
          itemBuilder: (_, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text('Your flair in r/$sub',
                    style: Theme.of(ctx)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
              );
            }
            final check = Icon(Icons.check_circle_rounded, color: cs.primary);
            if (i == 1) {
              return ListTile(
                title: const Text('No flair'),
                trailing: s.currentId == null && s.currentText == null
                    ? check
                    : null,
                onTap: () => Navigator.pop(ctx, noFlair),
              );
            }
            final c = s.choices[i - 2];
            return ListTile(
              key: ValueKey(c.id),
              title: Text(c.text.isEmpty ? '(write your own)' : c.text),
              subtitle:
                  c.editable ? const Text('You can change the text') : null,
              trailing: c.id == s.currentId ? check : null,
              onTap: () => Navigator.pop(ctx, c),
            );
          },
        ),
      ),
    ),
  );
  if (picked == null || !context.mounted) return false;
  final choice = identical(picked, noFlair) ? null : picked;
  String? text;
  if (choice != null && choice.editable) {
    final controller = TextEditingController(
        text: choice.id == s.currentId
            ? (s.currentText ?? choice.text)
            : choice.text);
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Flair text'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(18))),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Save')),
        ],
      ),
    );
    if (r == null) return false;
    text = r.trim();
  }
  try {
    final me = ref.read(authControllerProvider).valueOrNull?.username ?? '';
    await ref
        .read(redditRepositoryProvider)
        .setUserFlair(sub, me, choice, text);
    messenger.showSnackBar(SnackBar(
        content: Text(choice == null ? 'Flair removed' : 'Flair set')));
    return true;
  } catch (e) {
    if (context.mounted) showActionError(context, 'set your flair', e);
    return false;
  }
}
