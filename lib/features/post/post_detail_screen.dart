import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../history/interest_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/share.dart';
import '../../core/theme/app_theme.dart';
import '../../models/comment.dart';
import '../../models/post.dart';
import '../auth/auth_controller.dart';
import '../feed/post_overrides.dart';
import '../feed/swipe_actions.dart';
import '../media/gallery_carousel.dart';
import '../media/media_viewers.dart';
import '../media/nsfw_blur.dart';
import '../settings/settings_controller.dart';
import 'comments_controller.dart';
import 'compose_sheet.dart';
import 'post_actions.dart';

class PostDetailScreen extends ConsumerStatefulWidget {
  const PostDetailScreen({
    super.key,
    required this.subreddit,
    required this.postId,
    this.initialPost,
    this.focusCommentId,
  });

  final String subreddit;
  final String postId;
  final Post? initialPost;
  final String? focusCommentId; // open a single comment thread (from a permalink)

  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  final ItemScrollController _itemScroll = ItemScrollController();
  final ItemPositionsListener _itemPositions = ItemPositionsListener.create();
  List<Comment> _flat = const [];

  // In-post comment search.
  bool _searchOpen = false;
  final TextEditingController _searchCtrl = TextEditingController();
  List<int> _matchIndices = []; // list indices (ci + 1) of matching comments
  int _matchPos = 0;
  String? _currentMatchId;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) {
        _searchCtrl.clear();
        _matchIndices = [];
        _currentMatchId = null;
      }
    });
  }

  void _runSearch(String raw) {
    final q = raw.trim().toLowerCase();
    final m = <int>[];
    if (q.isNotEmpty) {
      for (var ci = 0; ci < _flat.length; ci++) {
        final c = _flat[ci];
        if (!c.isMore && c.body.toLowerCase().contains(q)) m.add(ci + 1);
      }
    }
    setState(() {
      _matchIndices = m;
      _matchPos = 0;
      _currentMatchId = m.isEmpty ? null : _flat[m.first - 1].fullname;
    });
    if (m.isNotEmpty) _scrollToMatch();
  }

  void _scrollToMatch() {
    if (_matchIndices.isEmpty) return;
    final li = _matchIndices[_matchPos];
    _currentMatchId = _flat[li - 1].fullname;
    _itemScroll.scrollTo(
        index: li,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        alignment: 0.12);
  }

  void _stepMatch(int delta) {
    if (_matchIndices.isEmpty) return;
    setState(() => _matchPos =
        (_matchPos + delta + _matchIndices.length) % _matchIndices.length);
    _scrollToMatch();
  }

  /// Jumps the comment list to the next top-level (depth 0) comment, cycling
  /// back to the first once past the last. List index 0 is the post header, so
  /// comment `ci` lives at list index `ci + 1`.
  void _jumpNextTopLevel() {
    if (_flat.isEmpty) return;

    // Reference = the topmost item actually on screen (ignore the cached items
    // ScrollablePositionedList keeps just outside the viewport).
    final onScreen = _itemPositions.itemPositions.value
        .where((p) => p.itemTrailingEdge > 0 && p.itemLeadingEdge < 1);
    final topIndex = onScreen.isEmpty
        ? 0
        : onScreen.map((p) => p.index).reduce((a, b) => a < b ? a : b);

    // First top-level comment strictly below the current top.
    int? target;
    for (var ci = 0; ci < _flat.length; ci++) {
      if (_flat[ci].depth != 0) continue;
      if (ci + 1 > topIndex) {
        target = ci + 1;
        break;
      }
    }
    // Past the last one → wrap to the first top-level comment.
    if (target == null) {
      for (var ci = 0; ci < _flat.length; ci++) {
        if (_flat[ci].depth == 0) {
          target = ci + 1;
          break;
        }
      }
    }
    if (target == null) return;

    _itemScroll.scrollTo(
      index: target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      alignment: 0.0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final key = widget.focusCommentId != null
        ? '${widget.subreddit}/${widget.postId}/focus_${widget.focusCommentId}'
        : '${widget.subreddit}/${widget.postId}';
    final async = ref.watch(commentsControllerProvider(key));
    final notifier = ref.read(commentsControllerProvider(key).notifier);
    final username =
        ref.watch(authControllerProvider).valueOrNull?.username ?? '';
    final thread = async.valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(thread?.post.subredditPrefixed ??
            (widget.subreddit == '_' ? 'Post' : 'r/${widget.subreddit}')),
        actions: [
          if (thread != null)
            PopupMenuButton<String>(
              icon: const Icon(Icons.sort_rounded),
              tooltip: 'Sort comments',
              onSelected: notifier.changeSort,
              itemBuilder: (_) => [
                for (final s in commentSorts)
                  CheckedPopupMenuItem(
                    value: s,
                    checked: notifier.sort == s,
                    child: Text(commentSortLabels[s] ?? s),
                  ),
              ],
            ),
          if (thread != null)
            IconButton(
              tooltip: 'Search comments',
              icon: Icon(
                  _searchOpen ? Icons.search_off_rounded : Icons.search_rounded),
              onPressed: _toggleSearch,
            ),
          if (thread != null)
            IconButton(
              icon: const Icon(Icons.more_vert_rounded),
              onPressed: () =>
                  showPostActionsSheet(context, ref, thread.post),
            ),
          if (thread != null && thread.post.author == username)
            PopupMenuButton<String>(
              onSelected: (v) async {
                final post = thread.post;
                if (v == 'edit' && post.isSelf) {
                  final newText = await showEditSheet(context, ref,
                      thingFullname: post.fullname, initialText: post.selftext);
                  if (newText != null) notifier.applyEdit(post.fullname, newText);
                } else if (v == 'delete') {
                  final ok = await _confirmDelete(context, 'post');
                  if (ok) {
                    await ref
                        .read(redditRepositoryProvider)
                        .deleteThing(post.fullname);
                    if (context.mounted) Navigator.of(context).maybePop();
                  }
                }
              },
              itemBuilder: (_) => [
                if (thread.post.isSelf)
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
        ],
      ),
      floatingActionButton: thread == null
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (thread.comments.isNotEmpty) ...[
                  FloatingActionButton.small(
                    heroTag: 'nextComment',
                    tooltip: 'Next top-level comment',
                    onPressed: _jumpNextTopLevel,
                    child: const Icon(Icons.keyboard_arrow_down_rounded),
                  ),
                  const SizedBox(height: 12),
                ],
                FloatingActionButton.extended(
                  heroTag: 'comment',
                  onPressed: () async {
                    final reply = await showReplySheet(context, ref,
                        parentFullname: thread.post.fullname, parentDepth: -1);
                    if (reply != null) {
                      notifier.insertReply(thread.post.fullname, reply);
                      ref
                          .read(postOverridesProvider.notifier)
                          .bumpComments(thread.post, 1);
                      // Commenting is the strongest engagement signal we have.
                      ref
                          .read(interestStoreProvider.notifier)
                          .bump(thread.post.subreddit, 2.5);
                      ref
                          .read(keywordStoreProvider.notifier)
                          .bumpTitle(thread.post.title, 1);
                    }
                  },
                  icon: const Icon(Icons.add_comment_rounded),
                  label: const Text('Comment'),
                ),
              ],
            ),
      body: Stack(
        children: [
          async.when(
        loading: () => _LoadingWithHeader(post: widget.initialPost),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Could not load this post.\n$e',
                    textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                    onPressed: notifier.refresh, child: const Text('Retry')),
              ],
            ),
          ),
        ),
        data: (thread) {
          final flat = _flatten(thread.comments, thread.collapsed);
          _flat = flat;
          final list = RefreshIndicator(
            onRefresh: notifier.refresh,
            child: ScrollablePositionedList.builder(
              itemScrollController: _itemScroll,
              itemPositionsListener: _itemPositions,
              padding: const EdgeInsets.only(top: 6, bottom: 96),
              itemCount: 1 + (flat.isEmpty ? 1 : flat.length),
              itemBuilder: (context, index) {
                if (index == 0) return _PostHeader(post: thread.post);
                if (flat.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: Text('No comments yet')),
                  );
                }
                final c = flat[index - 1];
                return _CommentTile(
                  key: ValueKey(c.fullname),
                  comment: c,
                  highlighted: _currentMatchId == c.fullname,
                  isOwn: c.author == username,
                  opAuthor: thread.post.author,
                  collapsed: thread.collapsed.contains(c.id),
                  loadingMore: thread.loadingMore.contains(c.fullname),
                  onToggle: () => notifier.toggleCollapse(c.id),
                  onLoadMore: () => notifier.loadMore(c),
                  onReply: () async {
                    final reply = await showReplySheet(context, ref,
                        parentFullname: c.fullname,
                        parentDepth: c.depth,
                        replyingTo: c.author);
                    if (reply != null) {
                      notifier.insertReply(c.fullname, reply);
                      ref
                          .read(postOverridesProvider.notifier)
                          .bumpComments(thread.post, 1);
                      ref
                          .read(interestStoreProvider.notifier)
                          .bump(thread.post.subreddit, 2.5);
                    }
                  },
                  onEdit: () async {
                    final newText = await showEditSheet(context, ref,
                        thingFullname: c.fullname, initialText: c.body);
                    if (newText != null) notifier.applyEdit(c.fullname, newText);
                  },
                  onDelete: () async {
                    final ok = await _confirmDelete(context, 'comment');
                    if (ok) {
                      await ref
                          .read(redditRepositoryProvider)
                          .deleteThing(c.fullname);
                      notifier.removeComment(c.fullname);
                    }
                  },
                );
              },
            ),
          );
          if (widget.focusCommentId == null) return list;
          // Single-comment view (from an inbox reply / permalink).
          final cs = Theme.of(context).colorScheme;
          return Column(
            children: [
              Material(
                color: cs.secondaryContainer,
                child: InkWell(
                  onTap: () => context
                      .replace('/comments/${widget.subreddit}/${widget.postId}'),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      children: [
                        Icon(Icons.subdirectory_arrow_right_rounded,
                            size: 18, color: cs.onSecondaryContainer),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('Viewing a single comment thread',
                              style: TextStyle(
                                  color: cs.onSecondaryContainer,
                                  fontWeight: FontWeight.w600)),
                        ),
                        Text('Show all',
                            style: TextStyle(
                                color: cs.primary,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(child: list),
            ],
          );
        },
          ),
          if (_searchOpen && thread != null)
            Positioned(
              left: 8,
              right: 8,
              top: 8,
              child: _buildSearchBar(context),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = _matchIndices.length;
    final has = _searchCtrl.text.trim().isNotEmpty;
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(28),
      color: cs.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            const SizedBox(width: 6),
            Icon(Icons.search_rounded, size: 20, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: _runSearch,
                onSubmitted: (_) => _stepMatch(1),
                decoration: const InputDecoration(
                  hintText: 'Search comments',
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
            if (has)
              Text(total == 0 ? '0/0' : '${_matchPos + 1}/$total',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            IconButton(
              tooltip: 'Previous',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.keyboard_arrow_up_rounded),
              onPressed: total == 0 ? null : () => _stepMatch(-1),
            ),
            IconButton(
              tooltip: 'Next',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              onPressed: total == 0 ? null : () => _stepMatch(1),
            ),
            IconButton(
              tooltip: 'Close',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded),
              onPressed: _toggleSearch,
            ),
          ],
        ),
      ),
    );
  }
}

/// Depth-edge colors (rotate by nesting level).
const _railColors = [
  Color(0xFF9F8BE8),
  Color(0xFF62B5AA),
  Color(0xFFE0A55C),
  Color(0xFFD88FB4),
  Color(0xFF7E9BE0),
];

List<Comment> _flatten(List<Comment> nodes, Set<String> collapsed) {
  final out = <Comment>[];
  void walk(Comment c) {
    out.add(c);
    if (!c.isMore && !collapsed.contains(c.id)) {
      for (final r in c.replies) {
        walk(r);
      }
    }
  }

  for (final c in nodes) {
    walk(c);
  }
  return out;
}

Future<bool> _confirmDelete(BuildContext context, String what) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Delete $what?'),
      content: const Text('This cannot be undone.'),
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
  return ok ?? false;
}

class _LoadingWithHeader extends StatelessWidget {
  const _LoadingWithHeader({this.post});
  final Post? post;
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        if (post != null) _PostHeader(post: post!),
        const Padding(
          padding: EdgeInsets.all(40),
          child: Center(child: CircularProgressIndicator()),
        ),
      ],
    );
  }
}

class _PostHeader extends ConsumerStatefulWidget {
  const _PostHeader({required this.post});
  final Post post;
  @override
  ConsumerState<_PostHeader> createState() => _PostHeaderState();
}

class _PostHeaderState extends ConsumerState<_PostHeader> {
  @override
  void initState() {
    super.initState();
    // Seed the shared overrides from this fresh fetch (esp. the comment count)
    // so the feed card reflects it when you go back.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(postOverridesProvider.notifier).syncFromServer(widget.post);
      }
    });
  }

  Future<void> _vote(int dir) async {
    final overrides = ref.read(postOverridesProvider.notifier);
    final cur = overrides.effective(widget.post);
    final current = cur.likes == true ? 1 : (cur.likes == false ? -1 : 0);
    final target = current == dir ? 0 : dir;
    overrides.setVote(widget.post, target);
    if (target == 1) {
      ref.read(interestStoreProvider.notifier).bump(widget.post.subreddit, 2);
    } else if (target == -1) {
      ref.read(interestStoreProvider.notifier).bump(widget.post.subreddit, -1.5);
    }
    try {
      await ref.read(redditRepositoryProvider).vote(widget.post.fullname, target);
    } catch (_) {
      overrides.setVote(widget.post, current);
    }
  }

  void _openMedia() {
    final p = widget.post;
    switch (p.type) {
      case PostType.image:
      case PostType.gif:
        openImageViewer(context, p.previewUrl ?? p.url, title: p.title);
      case PostType.gallery:
        openGalleryViewer(context, p.gallery, title: p.title);
      case PostType.video:
        openVideoViewer(
            context, p.hlsUrl ?? p.fallbackVideoUrl ?? resolveVideoUrl(p.url),
            title: p.title,
            downloadUrl: p.fallbackVideoUrl ?? resolveVideoUrl(p.url),
            externalUrl: p.url);
      case PostType.link:
        launchUrl(Uri.parse(p.url), mode: LaunchMode.externalApplication);
      case PostType.self:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.post;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => context.push('/r/${p.subreddit}'),
            child: Text(p.subredditPrefixed,
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: cs.primary)),
          ),
          const SizedBox(height: 2),
          GestureDetector(
            onTap: () => context.push('/u/${p.author}'),
            child: Text('u/${p.author} · ${timeAgo(p.created)}',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ),
          const SizedBox(height: 12),
          Text(p.title,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700, height: 1.3)),
          if (p.linkFlairText != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8)),
              child: Text(p.linkFlairText!,
                  style:
                      TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ),
          ],
          if (p.crosspostFrom != null) ...[
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.repeat_rounded, size: 14, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Flexible(
                child: Text('Crossposted from r/${p.crosspostFrom}',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ),
            ]),
          ],
          const SizedBox(height: 12),
          _media(cs),
          if (p.pollOptions.isNotEmpty) ...[
            const SizedBox(height: 4),
            for (final opt in p.pollOptions)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(opt),
              ),
            Text('Vote in the official app',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ],
          if (p.isSelf && p.selftext.isNotEmpty)
            MarkdownBody(
              data: p.selftext,
              selectable: true,
              onTapLink: (_, href, __) {
                if (href != null) {
                  launchUrl(Uri.parse(href),
                      mode: LaunchMode.externalApplication);
                }
              },
            ),
          const SizedBox(height: 12),
          Builder(builder: (context) {
            final ov =
                ref.watch(postOverridesProvider.select((m) => m[p.id]));
            final likes = ov != null ? ov.likes : p.likes;
            final score = ov?.score ?? p.score;
            final saved = ov?.saved ?? p.saved;
            final numComments = ov?.numComments ?? p.numComments;
            return Row(
              children: [
                _VotePill(
                    score: score,
                    likes: likes,
                    onUp: () => _vote(1),
                    onDown: () => _vote(-1)),
                const SizedBox(width: 8),
                Chip(
                  avatar: const Icon(Icons.mode_comment_outlined, size: 18),
                  label: Text(compactNumber(numComments)),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () async {
                    final overrides =
                        ref.read(postOverridesProvider.notifier);
                    final next = !overrides.effective(p).saved;
                    overrides.setSaved(p, next);
                    try {
                      await ref
                          .read(redditRepositoryProvider)
                          .setSaved(p.fullname, next);
                    } catch (_) {
                      overrides.setSaved(p, !next);
                    }
                  },
                  color: saved ? cs.primary : null,
                  icon: Icon(saved
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_border_rounded),
                ),
              ],
            );
          }),
          const Divider(height: 24),
        ],
      ),
    );
  }

  Widget _media(ColorScheme cs) {
    final p = widget.post;
    if (p.type == PostType.self) return const SizedBox.shrink();
    final blur = (p.over18 && ref.watch(settingsControllerProvider).blurNsfw) || p.spoiler;
    if (p.type == PostType.gallery && p.gallery.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: NsfwBlur(
          blur: blur,
          child: GalleryCarousel(images: p.gallery, title: p.title),
        ),
      );
    }
    if (p.type == PostType.link) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: OutlinedButton.icon(
          onPressed: _openMedia,
          icon: const Icon(Icons.open_in_new_rounded),
          label: Text(p.domain, overflow: TextOverflow.ellipsis),
        ),
      );
    }
    final url =
        p.previewUrl ?? (p.gallery.isNotEmpty ? p.gallery.first.url : null);
    final aspect = (p.previewWidth != null &&
            p.previewHeight != null &&
            p.previewHeight! > 0)
        ? (p.previewWidth! / p.previewHeight!).clamp(0.5, 2.0)
        : 16 / 9;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: NsfwBlur(
        blur: blur,
        child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: GestureDetector(
          onTap: _openMedia,
          child: AspectRatio(
            aspectRatio: aspect,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (url != null)
                  CachedNetworkImage(imageUrl: url, fit: BoxFit.cover)
                else
                  Container(color: cs.surfaceContainerHighest),
                if (p.type == PostType.video)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: const BoxDecoration(
                          color: Colors.black54, shape: BoxShape.circle),
                      child: const Icon(Icons.play_arrow_rounded,
                          color: Colors.white, size: 36),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}

class _CommentTile extends ConsumerStatefulWidget {
  const _CommentTile({
    super.key,
    required this.comment,
    required this.isOwn,
    required this.opAuthor,
    required this.collapsed,
    required this.loadingMore,
    required this.onToggle,
    required this.onLoadMore,
    required this.onReply,
    required this.onEdit,
    required this.onDelete,
    this.highlighted = false,
  });

  final Comment comment;
  final bool isOwn;
  final String opAuthor;
  final bool collapsed;
  final bool loadingMore;
  final bool highlighted; // current in-post search match
  final VoidCallback onToggle;
  final VoidCallback onLoadMore;
  final VoidCallback onReply;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  ConsumerState<_CommentTile> createState() => _CommentTileState();
}

class _CommentTileState extends ConsumerState<_CommentTile> {
  late bool? _likes = widget.comment.likes;
  late int _score = widget.comment.score;
  late bool _saved = widget.comment.saved;

  Future<void> _vote(int dir) async {
    final current = _likes == true ? 1 : (_likes == false ? -1 : 0);
    final target = current == dir ? 0 : dir;
    setState(() {
      _score += target - current;
      _likes = target == 1 ? true : (target == -1 ? false : null);
    });
    try {
      await ref
          .read(redditRepositoryProvider)
          .vote(widget.comment.fullname, target);
    } catch (_) {
      if (mounted) {
        setState(() {
          _score -= target - current;
          _likes = current == 1 ? true : (current == -1 ? false : null);
        });
      }
    }
  }

  Future<void> _toggleSave() async {
    final next = !_saved;
    setState(() => _saved = next);
    try {
      await ref
          .read(redditRepositoryProvider)
          .setSaved(widget.comment.fullname, next);
    } catch (_) {
      if (mounted) setState(() => _saved = !next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final comment = widget.comment;
    final cs = Theme.of(context).colorScheme;
    final depth = comment.depth;
    final indent = depth.clamp(0, 6) * 12.0;

    // "Load more replies" node — a light indented row, not a card.
    if (comment.isMore) {
      return Padding(
        padding: EdgeInsets.fromLTRB(10 + indent, 0, 10, 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: widget.loadingMore ? null : widget.onLoadMore,
            icon: widget.loadingMore
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(Icons.add_circle_outline_rounded,
                    size: 18, color: cs.primary),
            label: Text(comment.moreChildren.isEmpty
                ? 'Continue thread →'
                : '${comment.moreCount} more replies'),
          ),
        ),
      );
    }

    final isMod = comment.distinguished == 'moderator';
    final nameColor =
        isMod ? Colors.green : (widget.isOwn ? cs.primary : cs.onSurface);
    final edge = _railColors[(depth - 1).clamp(0, _railColors.length - 1)];

    return SwipeActions(
      enabled: ref.watch(settingsControllerProvider).swipeActions,
      onRight: () => _vote(1),
      onLeft: () => _vote(-1),
      child: Container(
        margin: EdgeInsets.fromLTRB(10 + indent, 0, 10, 8),
        decoration: BoxDecoration(
          color: widget.highlighted
              ? cs.primaryContainer
              : cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: widget.highlighted
              ? Border.all(color: cs.primary, width: 1.5)
              : null,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 5,
                offset: const Offset(0, 1)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Colored depth edge (only on replies).
              if (depth > 0)
                Container(width: 4, color: edge.withValues(alpha: 0.9)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Long-press collapses the whole subtree; tap re-expands a
                    // collapsed comment (so a tap can't accidentally collapse).
                    InkWell(
            onTap: widget.collapsed ? widget.onToggle : null,
            onLongPress: () {
              HapticFeedback.selectionClick();
              widget.onToggle();
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  _AuthorDot(name: comment.author, size: 20),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'u/${comment.author}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: nameColor,
                      ),
                    ),
                  ),
                  if (comment.author == widget.opAuthor &&
                      comment.author != '[deleted]') ...[
                    const SizedBox(width: 6),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(6)),
                      child: Text('OP',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: cs.onPrimaryContainer)),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Text('· ${timeAgo(comment.created)}',
                      style:
                          TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                  const Spacer(),
                  if (widget.collapsed)
                    Icon(Icons.unfold_more_rounded,
                        size: 16, color: cs.onSurfaceVariant),
                ],
              ),
            ),
          ),
          if (!widget.collapsed) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
              child: MarkdownBody(
                data: comment.body,
                selectable: true,
                styleSheet: MarkdownStyleSheet(
                  p: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontSize: 15, height: 1.45),
                ),
                onTapLink: (_, href, __) {
                  if (href != null) {
                    launchUrl(Uri.parse(href),
                        mode: LaunchMode.externalApplication);
                  }
                },
              ),
            ),
            _actions(cs),
          ] else
            Padding(
              padding: const EdgeInsets.fromLTRB(40, 0, 12, 8),
              child: Text(
                comment.body.replaceAll('\n', ' '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurfaceVariant,
                    fontStyle: FontStyle.italic),
              ),
            ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actions(ColorScheme cs) {
    final votes = Theme.of(context).extension<VoteColors>()!;
    final up = _likes == true;
    final down = _likes == false;
    final scoreColor = up ? votes.up : (down ? votes.down : cs.onSurfaceVariant);
    return Row(
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          onPressed: () => _vote(1),
          icon: Icon(Icons.arrow_upward_rounded,
              color: up ? votes.up : cs.onSurfaceVariant),
        ),
        Text(
          widget.comment.scoreHidden ? '–' : compactNumber(_score),
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: scoreColor),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          onPressed: () => _vote(-1),
          icon: Icon(Icons.arrow_downward_rounded,
              color: down ? votes.down : cs.onSurfaceVariant),
        ),
        _CommentActionBtn(
          icon: Icons.reply_rounded,
          label: 'Reply',
          onTap: widget.onReply,
        ),
        const Spacer(),
        IconButton(
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          tooltip: 'Collapse thread',
          onPressed: widget.onToggle,
          color: cs.onSurfaceVariant,
          icon: const Icon(Icons.unfold_less_rounded),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          onPressed: _toggleSave,
          color: _saved ? cs.primary : cs.onSurfaceVariant,
          icon: Icon(_saved
              ? Icons.bookmark_rounded
              : Icons.bookmark_border_rounded),
        ),
        PopupMenuButton<String>(
          icon: Icon(Icons.more_horiz_rounded,
              size: 18, color: cs.onSurfaceVariant),
          padding: EdgeInsets.zero,
          onSelected: (v) {
            switch (v) {
              case 'copy':
                Clipboard.setData(ClipboardData(text: widget.comment.body));
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied')));
              case 'share':
                shareUrl(context, 'https://reddit.com${widget.comment.permalink}');
              case 'edit':
                widget.onEdit();
              case 'delete':
                widget.onDelete();
              case 'block':
                confirmBlockUser(context, ref, widget.comment.author);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'copy', child: Text('Copy text')),
            if (widget.comment.permalink.isNotEmpty)
              const PopupMenuItem(value: 'share', child: Text('Share')),
            if (widget.isOwn) ...[
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
            if (!widget.isOwn && widget.comment.author != '[deleted]')
              PopupMenuItem(
                  value: 'block', child: Text('Block u/${widget.comment.author}')),
          ],
        ),
      ],
    );
  }
}

class _CommentActionBtn extends StatelessWidget {
  const _CommentActionBtn(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: cs.onSurfaceVariant,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 36),
      ),
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12.5)),
    );
  }
}

/// Small colored avatar with the author's initial (color derived from name).
class _AuthorDot extends StatelessWidget {
  const _AuthorDot({required this.name, this.size = 20});
  final String name;
  final double size;

  static const _palette = [
    Color(0xFF7C5CE0),
    Color(0xFF4FA89B),
    Color(0xFFC77E4A),
    Color(0xFFC46A96),
    Color(0xFF5B82CE),
    Color(0xFF5FA85A),
  ];

  @override
  Widget build(BuildContext context) {
    final clean = name.replaceFirst('u/', '');
    final deleted = clean.isEmpty || clean.startsWith('[');
    var h = 0;
    for (final r in clean.codeUnits) {
      h = (h * 31 + r) & 0x7fffffff;
    }
    final color =
        deleted ? Theme.of(context).colorScheme.outline : _palette[h % _palette.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Text(
        deleted ? '?' : clean[0].toUpperCase(),
        style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: size * 0.5),
      ),
    );
  }
}

class _VotePill extends StatelessWidget {
  const _VotePill({
    required this.score,
    required this.likes,
    required this.onUp,
    required this.onDown,
  });
  final int score;
  final bool? likes;
  final VoidCallback onUp;
  final VoidCallback onDown;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final votes = Theme.of(context).extension<VoteColors>()!;
    final up = likes == true;
    final down = likes == false;
    final countColor = up ? votes.up : (down ? votes.down : cs.onSurfaceVariant);
    return Container(
      decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: onUp,
            visualDensity: VisualDensity.compact,
            iconSize: 20,
            icon: Icon(Icons.arrow_upward_rounded,
                color: up ? votes.up : cs.onSurfaceVariant),
          ),
          Text(compactNumber(score),
              style: TextStyle(fontWeight: FontWeight.w700, color: countColor)),
          IconButton(
            onPressed: onDown,
            visualDensity: VisualDensity.compact,
            iconSize: 20,
            icon: Icon(Icons.arrow_downward_rounded,
                color: down ? votes.down : cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
