import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/deep_links.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/share.dart';
import '../../models/comment.dart';
import '../../models/post.dart';
import '../../models/reddit_user.dart';
import '../auth/auth_controller.dart';
import '../feed/paged_list.dart';
import '../feed/post_card.dart';

final userAboutProvider =
    FutureProvider.autoDispose.family<RedditUser, String>((ref, name) {
  return ref.watch(redditRepositoryProvider).getUserAbout(name);
});

class UserScreen extends ConsumerWidget {
  const UserScreen({super.key, required this.username});
  final String username;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final about = ref.watch(userAboutProvider(username));
    final me = ref.watch(authControllerProvider).valueOrNull?.username;
    final isSelf = me != null && me.toLowerCase() == username.toLowerCase();
    final repo = ref.read(redditRepositoryProvider);

    final tabs = <Tab>[
      const Tab(text: 'Posts'),
      const Tab(text: 'Comments'),
      if (isSelf) const Tab(text: 'Saved'),
      if (isSelf) const Tab(text: 'Upvoted'),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text('u/$username'),
          actions: [
            if (!isSelf)
              IconButton(
                tooltip: 'Send message',
                icon: const Icon(Icons.mail_outline_rounded),
                onPressed: () => context.push('/compose_message?to=$username'),
              ),
            IconButton(
              tooltip: 'Share',
              icon: const Icon(Icons.share_outlined),
              onPressed: () => shareUrl('https://reddit.com/user/$username'),
            ),
          ],
        ),
        body: Column(
          children: [
            about.when(
              loading: () => const SizedBox(
                  height: 96, child: Center(child: CircularProgressIndicator())),
              error: (e, _) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Could not load profile: $e')),
              data: (u) => _ProfileHeader(user: u),
            ),
            TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: tabs),
            Expanded(
              child: TabBarView(
                children: [
                  PagedList<Post>(
                    fetch: (a) => repo.getUserPosts(username, after: a),
                    itemBuilder: (_, p) => PostCard(post: p),
                    emptyLabel: 'No posts yet',
                  ),
                  PagedList<Comment>(
                    fetch: (a) => repo.getUserComments(username, after: a),
                    itemBuilder: (_, c) => _ProfileCommentCard(comment: c),
                    emptyLabel: 'No comments yet',
                  ),
                  if (isSelf)
                    PagedList<Object>(
                      fetch: (a) => repo.getUserSaved(username, after: a),
                      itemBuilder: (_, item) => item is Post
                          ? PostCard(post: item)
                          : _ProfileCommentCard(comment: item as Comment),
                      emptyLabel: 'Nothing saved',
                    ),
                  if (isSelf)
                    PagedList<Post>(
                      fetch: (a) =>
                          repo.getUserPosts(username, where: 'upvoted', after: a),
                      itemBuilder: (_, p) => PostCard(post: p),
                      emptyLabel: 'Nothing upvoted',
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.user});
  final RedditUser user;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: cs.primaryContainer,
            foregroundColor: cs.onPrimaryContainer,
            backgroundImage: user.iconUrl != null
                ? CachedNetworkImageProvider(user.iconUrl!)
                : null,
            child: user.iconUrl == null
                ? Text(user.name.isNotEmpty ? user.name[0].toUpperCase() : '?')
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('u/${user.name}',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  '${compactNumber(user.linkKarma)} post · '
                  '${compactNumber(user.commentKarma)} comment karma',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
                Text(
                  'Joined ${DateFormat.yMMM().format(user.created.toLocal())}',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileCommentCard extends StatelessWidget {
  const _ProfileCommentCard({required this.comment});
  final Comment comment;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: () {
          final route = comment.permalink.isEmpty
              ? null
              : routeForRedditUrl(
                  Uri.parse('https://reddit.com${comment.permalink}'));
          if (route != null) context.push(route);
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (comment.linkTitle.isNotEmpty)
                Text(
                  comment.linkTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              Text(
                'r/${comment.subreddit} · ${compactNumber(comment.score)} pts · ${timeAgo(comment.created)}',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              Text(
                comment.body.replaceAll('\n', ' '),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: cs.onSurface),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
