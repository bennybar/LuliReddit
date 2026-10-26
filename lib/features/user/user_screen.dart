import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/deep_links.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/share.dart';
import '../../core/theme/app_theme.dart' show VoteColors;
import '../../core/widgets/loading.dart';
import '../../core/widgets/toggles.dart';
import '../../models/comment.dart';
import '../../models/listing.dart';
import '../../models/post.dart';
import '../../models/reddit_user.dart';
import '../auth/auth_controller.dart';
import '../feed/local_votes.dart';
import '../feed/paged_list.dart';
import '../feed/post_card.dart';
import '../post/post_actions.dart';
import '../../core/widgets/error_view.dart';

final userAboutProvider =
    FutureProvider.autoDispose.family<RedditUser, String>((ref, name) {
  return ref.watch(redditRepositoryProvider).getUserAbout(name);
});

/// A user's profile: header + Posts / Comments (and your own Saved /
/// Upvoted) tabs.
class UserScreen extends ConsumerWidget {
  const UserScreen({super.key, required this.username});
  final String username;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(
            authControllerProvider.select((a) => a.valueOrNull?.username)) ??
        '';
    final isSelf =
        me.isNotEmpty && me.toLowerCase() == username.toLowerCase();
    return Scaffold(
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
            onPressed: () =>
                shareUrl(context, 'https://reddit.com/user/$username'),
          ),
          if (!isSelf)
            IconButton(
              tooltip: 'Block user',
              icon: const Icon(Icons.block_flipped),
              onPressed: () => confirmBlockUser(context, ref, username),
            ),
        ],
      ),
      body: UserProfileBody(username: username),
    );
  }
}

/// A profile's header and its Posts / Comments (and your own Saved /
/// Upvoted) lists: the user screen, and the Profile tab ([belowHeader]: its
/// "Your stuff" row).
class UserProfileBody extends ConsumerWidget {
  const UserProfileBody({super.key, required this.username, this.belowHeader});
  final String username;
  final Widget? belowHeader;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final about = ref.watch(userAboutProvider(username));
    final me = ref.watch(
            authControllerProvider.select((a) => a.valueOrNull?.username)) ??
        '';
    final isSelf =
        me.isNotEmpty && me.toLowerCase() == username.toLowerCase();
    final repo = ref.read(redditRepositoryProvider);
    final votes = ref.read(commentVotesProvider.notifier);
    // Your own lists reload on every return from a post (scores and votes
    // you just changed); others' after the usual five minutes.
    final staleAfter = isSelf
        ? const Duration(seconds: 30)
        : const Duration(minutes: 5);

    final tabs = <Tab>[
      const Tab(text: 'Posts'),
      const Tab(text: 'Comments'),
      if (isSelf) const Tab(text: 'Saved'),
      if (isSelf) const Tab(text: 'Upvoted'),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Column(
        children: [
          about.when(
            loading: () => const SizedBox(
                height: 96, child: Center(child: Loading())),
            error: (e, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Could not load profile: ${friendlyError(e)}')),
            data: (u) =>
                _ProfileHeader(user: u, canFollow: !isSelf && me.isNotEmpty),
          ),
          if (belowHeader != null) belowHeader!,
          TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: tabs),
          Expanded(
            child: TabBarView(
              children: [
                PagedList<Post>(
                  fetch: (a) => repo.getUserPosts(username, after: a),
                  itemBuilder: (_, p) => PostCard(key: ValueKey(p.id), post: p),
                  emptyLabel: 'No posts yet',
                  staleAfter: staleAfter,
                ),
                PagedList<Comment>(
                  // Your votes from threads that Reddit hasn't caught up with.
                  fetch: (a) async {
                    final l = await repo.getUserComments(username, after: a);
                    return Listing(items: votes.apply(l.items), after: l.after);
                  },
                  itemBuilder: (_, c) => _ProfileCommentCard(
                      key: ValueKey(c.id), comment: c),
                  emptyLabel: 'No comments yet',
                  staleAfter: staleAfter,
                ),
                if (isSelf)
                  PagedList<Object>(
                    fetch: (a) => repo.getUserSaved(username, after: a),
                    itemBuilder: (_, item) => item is Post
                        ? PostCard(key: ValueKey(item.id), post: item)
                        : _ProfileCommentCard(
                            key: ValueKey((item as Comment).id),
                            comment: item),
                    emptyLabel: 'Nothing saved',
                    staleAfter: staleAfter,
                  ),
                if (isSelf)
                  PagedList<Post>(
                    fetch: (a) =>
                        repo.getUserPosts(username, where: 'upvoted', after: a),
                    itemBuilder: (_, p) =>
                        PostCard(key: ValueKey(p.id), post: p),
                    emptyLabel: 'Nothing upvoted',
                    staleAfter: staleAfter,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileHeader extends ConsumerStatefulWidget {
  const _ProfileHeader({required this.user, required this.canFollow});
  final RedditUser user;
  final bool canFollow;

  @override
  ConsumerState<_ProfileHeader> createState() => _ProfileHeaderState();
}

class _ProfileHeaderState extends ConsumerState<_ProfileHeader> {
  // Following a user is subscribing to their profile (u_<name>): their posts
  // then show in your Best / Hot / New and For You, like a subreddit's.
  late bool _following = widget.user.following;
  bool _busy = false;

  @override
  void didUpdateWidget(_ProfileHeader old) {
    super.didUpdateWidget(old);
    if (old.user.name != widget.user.name) {
      _following = widget.user.following;
    }
  }

  Future<void> _toggle() async {
    final next = !_following;
    setState(() {
      _following = next;
      _busy = true;
    });
    try {
      await ref
          .read(redditRepositoryProvider)
          .setSubscribed('u_${widget.user.name}', next);
    } catch (e) {
      if (!mounted) return;
      setState(() => _following = !next);
      showActionError(context, next ? 'follow' : 'unfollow', e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final user = widget.user;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          LetterAvatar(
            name: user.name,
            size: 60,
            container: cs.primaryContainer,
            content: cs.onPrimaryContainer,
            imageUrl: user.iconUrl,
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
                  'Joined '
                  '${DateFormat('MMM yyyy').format(user.created.toLocal())}',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          // One toggle: its shape and fill change with the state, and it
          // reads as on/off.
          if (widget.canFollow)
            ToggleButton(
              checked: _following,
              onChanged: _busy ? null : (_) => _toggle(),
              child: Text(_following ? 'Following' : 'Follow'),
            ),
        ],
      ),
    );
  }
}

/// Opens a comment's permalink (its thread, focused on it).
void openPermalink(BuildContext context, String permalink) {
  if (permalink.isEmpty) return;
  final route =
      routeForRedditUrl(Uri.parse('https://reddit.com$permalink'));
  if (route != null) context.push(route);
}

class _ProfileCommentCard extends ConsumerWidget {
  const _ProfileCommentCard({super.key, required this.comment});
  final Comment comment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    // Your votes from threads (this list is Reddit's copy from when it
    // loaded).
    final vote =
        ref.watch(commentVotesProvider.select((m) => m[comment.id]));
    final likes = vote != null ? vote.likes : comment.likes;
    final voteColors = Theme.of(context).extension<VoteColors>()!;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: () => openPermalink(context, comment.permalink),
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
                'r/${comment.subreddit} · '
                '${compactNumber(vote?.score ?? comment.score)} pts · '
                '${timeAgo(comment.created)}',
                style: TextStyle(
                    fontSize: 12,
                    color: switch (likes) {
                      true => voteColors.up,
                      false => voteColors.down,
                      null => cs.onSurfaceVariant,
                    }),
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
