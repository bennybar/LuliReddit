import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../models/comment.dart';
import '../../models/post.dart';
import '../auth/auth_controller.dart';
import '../feed/content_filters.dart';
import '../feed/local_votes.dart';
import '../offline/offline_store.dart';
import '../settings/settings_controller.dart';
import 'comment_tree.dart';

/// A loaded thread: the post, its comment tree and per-view state.
class PostThread {
  PostThread({
    required this.post,
    required this.comments,
    this.collapsed = const {},
    this.loadingMore = const {},
  });

  final Post post;
  final List<Comment> comments;
  // Collapsed comment ids, plus CommentTree.folded ids.
  final Set<String> collapsed;
  final Set<String> loadingMore; // more-node fullnames being fetched

  /// Visible rows, depth-first (computed once per tree / collapse set).
  late final List<Comment> flat = CommentTree.flatten(comments, collapsed);

  PostThread copyWith({
    Post? post,
    List<Comment>? comments,
    Set<String>? collapsed,
    Set<String>? loadingMore,
  }) =>
      PostThread(
        post: post ?? this.post,
        comments: comments ?? this.comments,
        collapsed: collapsed ?? this.collapsed,
        loadingMore: loadingMore ?? this.loadingMore,
      );
}

/// arg = "subreddit/postId"
const commentSorts = ['confidence', 'top', 'new', 'controversial', 'old', 'qa'];
const commentSortLabels = {
  'confidence': 'Best',
  'top': 'Top',
  'new': 'New',
  'controversial': 'Controversial',
  'old': 'Old',
  'qa': 'Q&A',
};

/// Comments in the first request. Reddit answers 30 in about half the time
/// of 100, so the thread paints with these and the full page follows in the
/// background — only when the first one was cut short.
const _firstPage = 30;
const _fullPage = 100;

/// The thread screen's state: loads the post + comments (following a
/// suggested sort, falling back to an offline copy), and owns collapse /
/// reply / edit / vote / delete / load-more on the tree.
class CommentsController
    extends AutoDisposeFamilyAsyncNotifier<PostThread, String> {
  String _subreddit = '';
  String _postId = '';
  String? _focusCommentId; // set when viewing a single comment thread
  // Empty until the first build seeds it from the user's default comment sort.
  String _sort = '';
  String get sort => _sort;
  bool _sortChosen = false; // the user picked a sort for this thread
  bool get isFocused => _focusCommentId != null;
  // The tree changed locally (vote, reply, edit, load more…) since the first
  // page: the full page then must not replace it.
  bool _touched = false;
  int _generation = 0; // a newer load drops an older full-page fetch

  @override
  Future<PostThread> build(String arg) async {
    // Closed meanwhile: a pending full page must not touch the state.
    ref.onDispose(() => _generation++);
    // Key: "subreddit/postId" or "subreddit/postId/focus_<commentId>".
    final parts = arg.split('/');
    _subreddit = parts[0];
    _postId = parts[1];
    _focusCommentId = (parts.length > 2 && parts[2].startsWith('focus_'))
        ? parts[2].substring(6)
        : null;
    final (thread, more) = await _load();
    if (more) unawaited(_loadFullPage(++_generation));
    return thread;
  }

  /// The first load, and whether the full page should follow (not for an
  /// offline copy or a focused thread).
  Future<(PostThread, bool)> _load() async {
    _touched = false;
    // Seed from the user's default comment sort (changeSort overrides it).
    if (_sort.isEmpty) {
      _sort = ref.read(settingsControllerProvider).defaultCommentSort;
    }
    final repo = ref.read(redditRepositoryProvider);
    final votes = ref.read(commentVotesProvider.notifier);
    // A focused (single-comment) thread is small: one full request.
    final paged = _focusCommentId == null;
    final limit = paged ? _firstPage : _fullPage;
    Post post;
    List<Comment> comments;
    String? suggested;
    try {
      (post, comments, suggested) = await repo.getComments(
        subreddit: _subreddit,
        postId: _postId,
        sort: _sort,
        focusCommentId: _focusCommentId,
        limit: limit,
      );
    } catch (_) {
      // Saved for offline (Read later)? Show that copy instead of an error.
      final saved =
          _focusCommentId == null ? await readOfflineThread(_postId) : null;
      if (saved == null) rethrow;
      (post, comments, _) = repo.parseThread(saved);
      return (PostThread(post: post, comments: votes.apply(comments)), false);
    }
    // Threads like AMAs set a suggested sort (Q&A, New). Follow it unless the
    // user picked a sort for this thread; it's only known once fetched.
    if (!_sortChosen &&
        suggested != null &&
        suggested != _sort &&
        commentSortLabels.containsKey(suggested)) {
      _sort = suggested;
      (post, comments, _) = await repo.getComments(
        subreddit: _subreddit,
        postId: _postId,
        sort: _sort,
        focusCommentId: _focusCommentId,
        limit: limit,
      );
    }
    final thread = PostThread(
        post: post,
        comments: votes.apply(comments),
        collapsed: _startCollapsed(comments));
    // Fetch the full page only when the first one was cut short (it ends in
    // "load more" rows); a small thread is already complete.
    return (
      thread,
      paged && CommentTree.flatten(comments, const {}).any((c) => c.isMore)
    );
  }

  /// Swaps in the full page under the first one. Same sort, so the comments
  /// already on screen keep their place and the rest appear below; collapse
  /// state carries over. Skipped once the user has changed the tree, or if
  /// the request fails (the first page's "more" rows still load the rest).
  Future<void> _loadFullPage(int generation) async {
    final (Post, List<Comment>, String?) full;
    try {
      full = await ref.read(redditRepositoryProvider).getComments(
            subreddit: _subreddit,
            postId: _postId,
            sort: _sort,
            limit: _fullPage,
          );
    } catch (_) {
      return;
    }
    if (generation != _generation) return;
    final cur = state.valueOrNull;
    if (cur == null || _touched) return;
    // New comments start collapsed by the same rules as on first load; a
    // toggle made meanwhile survives the swap.
    final known = {
      for (final c in CommentTree.flatten(cur.comments, const {})) c.id
    };
    final auto = _startCollapsed(full.$2, skip: known);
    state = AsyncData(PostThread(
      post: full.$1,
      comments: ref.read(commentVotesProvider.notifier).apply(full.$2),
      collapsed: {...cur.collapsed, ...auto},
    ));
  }

  /// The comments a thread opens with collapsed: AutoModerator's (content
  /// filter), ones scoring below the "Collapse low-scoring comments" setting
  /// (not your own), and with "Open threads collapsed" every top-level
  /// comment's replies (folded: its own text stays). [skip]: ones already
  /// shown, left as they are.
  Set<String> _startCollapsed(List<Comment> comments,
      {Set<String> skip = const {}}) {
    final autoMod = ref.read(contentFiltersProvider).collapseAutoMod;
    final s = ref.read(settingsControllerProvider);
    final below = s.collapseBelowScore;
    final me = (ref.read(authControllerProvider).valueOrNull?.username ?? '')
        .toLowerCase();
    final out = <String>{};
    for (final c in CommentTree.flatten(comments, const {})) {
      if (c.isMore || skip.contains(c.id)) continue;
      if (autoMod && c.author == 'AutoModerator') {
        out.add(c.id);
      } else if (below != null &&
          c.score < below &&
          !c.scoreHidden &&
          c.author.toLowerCase() != me) {
        out.add(c.id);
      } else if (s.collapseTopLevel &&
          c.depth == 0 &&
          c.replies.any((r) => !r.isMore)) {
        out.add(CommentTree.folded(c.id));
      }
    }
    return out;
  }

  Future<void> changeSort(String sort) async {
    _sort = sort;
    _sortChosen = true;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => build(arg));
  }

  /// Pull-to-refresh: keeps the current thread on screen until the new one is
  /// in. A failed refresh keeps the thread readable and rethrows (the screen
  /// says so); the error screen is for nothing loaded.
  Future<void> refresh() async {
    if (state.valueOrNull == null) {
      state = const AsyncLoading();
      state = await AsyncValue.guard(() => build(arg));
      return;
    }
    final (thread, more) = await _load();
    state = AsyncData(thread);
    if (more) unawaited(_loadFullPage(++_generation));
  }

  void _edit(PostThread Function(PostThread) block) {
    final s = state.valueOrNull;
    if (s != null) state = AsyncData(block(s));
  }

  PostThread _withTree(PostThread t, List<Comment> comments) {
    _touched = true;
    return t.copyWith(comments: comments);
  }

  void toggleCollapse(String commentId) => _edit((t) {
        // Expanding a comment also shows its folded replies.
        final next = {...t.collapsed};
        if (next.contains(commentId)) {
          next
            ..remove(commentId)
            ..remove(CommentTree.folded(commentId));
        } else {
          next.add(commentId);
        }
        return t.copyWith(collapsed: next);
      });

  /// "Show N replies" under a folded comment.
  void unfold(String commentId) => _edit((t) => t.copyWith(
      collapsed: {...t.collapsed}..remove(CommentTree.folded(commentId))));

  /// Splices a freshly-created reply into the tree under [parentFullname]
  /// (the post's fullname → new top-level comment; else under that comment).
  void insertReply(String parentFullname, Comment reply) => _edit((t) =>
      parentFullname == t.post.fullname
          ? _withTree(t, [reply, ...t.comments])
          : _withTree(t,
              CommentTree.insertReply(t.comments, parentFullname, reply)));

  void applyEdit(String fullname, String newBody) => _edit((t) {
        if (fullname == t.post.fullname) {
          _touched = true;
          return t.copyWith(post: t.post.copyWith(selftext: newBody));
        }
        return _withTree(
            t,
            CommentTree.update(
                t.comments, fullname, (c) => c.copyWith(body: newBody)));
      });

  /// Applies [change] to one comment in the tree.
  void updateComment(String fullname, Comment Function(Comment) change) =>
      _edit((t) =>
          _withTree(t, CommentTree.update(t.comments, fullname, change)));

  /// After deleting a comment: drop it, or keep its replies under
  /// "[deleted]".
  void removeComment(String fullname) => _edit(
      (t) => _withTree(t, CommentTree.remove(t.comments, fullname)));

  Future<void> loadMore(Comment moreNode) async {
    final s = state.valueOrNull;
    if (s == null ||
        moreNode.moreChildren.isEmpty ||
        s.loadingMore.contains(moreNode.fullname)) {
      return;
    }
    _touched = true; // the full page would drop this "more" row mid-load
    _edit((t) =>
        t.copyWith(loadingMore: {...t.loadingMore, moreNode.fullname}));
    try {
      final flat = await ref.read(redditRepositoryProvider).getMoreComments(
            linkFullname: s.post.fullname,
            childrenIds: moreNode.moreChildren,
            sort: _sort, // expanded replies follow the thread's sort
            depth: moreNode.depth,
          );
      final applied = ref.read(commentVotesProvider.notifier).apply(flat);
      _edit((t) => _withTree(
              t, CommentTree.replaceMore(t.comments, moreNode, applied))
          .copyWith(
              loadingMore: {...t.loadingMore}..remove(moreNode.fullname)));
    } catch (_) {
      _edit((t) => t.copyWith(
          loadingMore: {...t.loadingMore}..remove(moreNode.fullname)));
    }
  }
}

final commentsControllerProvider = AsyncNotifierProvider.autoDispose
    .family<CommentsController, PostThread, String>(CommentsController.new);
