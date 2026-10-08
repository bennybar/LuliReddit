import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../models/comment.dart';
import '../../models/post.dart';
import '../feed/content_filters.dart';
import '../offline/offline_store.dart';
import '../settings/settings_controller.dart';

class PostThread {
  const PostThread({
    required this.post,
    required this.comments,
    this.collapsed = const {},
    this.loadingMore = const {},
  });

  final Post post;
  final List<Comment> comments;
  final Set<String> collapsed; // collapsed comment ids
  final Set<String> loadingMore; // more-node fullnames being fetched

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

class CommentsController extends AutoDisposeFamilyAsyncNotifier<PostThread, String> {
  String _subreddit = '';
  String _postId = '';
  String? _focusCommentId; // set when viewing a single comment thread
  // Empty until the first build seeds it from the user's default comment sort.
  String _sort = '';
  String get sort => _sort;
  bool _sortChosen = false; // the user picked a sort for this thread
  bool get isFocused => _focusCommentId != null;

  @override
  Future<PostThread> build(String arg) async {
    // Seed from the user's default comment sort (changeSort overrides it).
    if (_sort.isEmpty) {
      _sort = ref.read(settingsControllerProvider).defaultCommentSort;
    }
    // Key: "subreddit/postId" or "subreddit/postId/focus_<commentId>".
    final parts = arg.split('/');
    _subreddit = parts[0];
    _postId = parts[1];
    _focusCommentId = (parts.length > 2 && parts[2].startsWith('focus_'))
        ? parts[2].substring(6)
        : null;
    final repo = ref.read(redditRepositoryProvider);
    Post post;
    List<Comment> comments;
    String? suggested;
    try {
      (post, comments, suggested) = await repo.getComments(
        subreddit: _subreddit,
        postId: _postId,
        sort: _sort,
        focusCommentId: _focusCommentId,
      );
    } catch (_) {
      // Saved for offline (Read later)? Show that copy instead of an error.
      final saved =
          _focusCommentId == null ? await readOfflineThread(_postId) : null;
      if (saved == null) rethrow;
      (post, comments, _) = repo.parseThread(saved);
      return PostThread(post: post, comments: comments);
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
      );
    }
    // "Collapse AutoModerator" filter: start its comments collapsed.
    final collapsed = ref.read(contentFiltersProvider).collapseAutoMod
        ? {
            for (final c in comments)
              if (c.author == 'AutoModerator') c.id
          }
        : const <String>{};
    return PostThread(post: post, comments: comments, collapsed: collapsed);
  }

  Future<void> changeSort(String sort) async {
    _sort = sort;
    _sortChosen = true;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => build(arg));
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(() => build(arg));
  }

  void toggleCollapse(String commentId) {
    final s = state.valueOrNull;
    if (s == null) return;
    final next = Set<String>.from(s.collapsed);
    next.contains(commentId) ? next.remove(commentId) : next.add(commentId);
    state = AsyncData(s.copyWith(collapsed: next));
  }

  /// Splices a freshly-created reply into the tree under [parentFullname]
  /// (the post's fullname → new top-level comment; else under that comment).
  void insertReply(String parentFullname, Comment reply) {
    final s = state.valueOrNull;
    if (s == null) return;
    if (parentFullname == s.post.fullname) {
      state = AsyncData(s.copyWith(comments: [reply, ...s.comments]));
      return;
    }
    List<Comment> walk(List<Comment> nodes) => [
          for (final n in nodes)
            if (n.fullname == parentFullname)
              n.copyWith(replies: [reply.copyWith(depth: n.depth + 1), ...n.replies])
            else
              n.copyWith(replies: walk(n.replies)),
        ];
    state = AsyncData(s.copyWith(comments: walk(s.comments)));
  }

  void applyEdit(String fullname, String newBody) {
    final s = state.valueOrNull;
    if (s == null) return;
    if (fullname == s.post.fullname) {
      state = AsyncData(s.copyWith(post: s.post.copyWith(selftext: newBody)));
      return;
    }
    List<Comment> walk(List<Comment> nodes) => [
          for (final n in nodes)
            if (n.fullname == fullname)
              n.copyWith(body: newBody, replies: walk(n.replies))
            else
              n.copyWith(replies: walk(n.replies)),
        ];
    state = AsyncData(s.copyWith(comments: walk(s.comments)));
  }

  /// Applies [change] to one comment in the tree. Vote and save state live
  /// here rather than in the comment's widget, which the list disposes as it
  /// scrolls off-screen — so they survive scrolling away and back.
  void updateComment(String fullname, Comment Function(Comment) change) {
    final s = state.valueOrNull;
    if (s == null) return;
    List<Comment> walk(List<Comment> nodes) => [
          for (final n in nodes)
            n.fullname == fullname
                ? change(n)
                : (n.replies.isEmpty ? n : n.copyWith(replies: walk(n.replies))),
        ];
    state = AsyncData(s.copyWith(comments: walk(s.comments)));
  }

  /// After deleting a comment: drop it, or — if it has replies — keep the
  /// replies under a "[deleted]" placeholder, as Reddit does.
  void removeComment(String fullname) {
    final s = state.valueOrNull;
    if (s == null) return;
    List<Comment> walk(List<Comment> nodes) => [
          for (final n in nodes)
            if (n.fullname != fullname)
              n.copyWith(replies: walk(n.replies))
            else if (n.replies.isNotEmpty)
              n.copyWith(
                  author: '[deleted]', body: '[deleted]', media: const {}),
        ];
    state = AsyncData(s.copyWith(comments: walk(s.comments)));
  }

  Future<void> loadMore(Comment moreNode) async {
    final s = state.valueOrNull;
    if (s == null || moreNode.moreChildren.isEmpty) return;
    state = AsyncData(s.copyWith(
        loadingMore: {...s.loadingMore, moreNode.fullname}));

    try {
      final flat = await ref.read(redditRepositoryProvider).getMoreComments(
            linkFullname: s.post.fullname,
            childrenIds: moreNode.moreChildren,
            sort: _sort, // expanded replies follow the thread's sort
            depth: moreNode.depth,
          );

      // Re-nest the flat list by parent_id.
      final byParent = <String, List<Comment>>{};
      for (final c in flat) {
        byParent.putIfAbsent(c.parentId, () => []).add(c);
      }
      Comment attach(Comment c) {
        final kids = byParent[c.fullname] ?? const [];
        return c.copyWith(
          depth: c.depth,
          replies: [for (final k in kids) attach(_withDepth(k, c.depth + 1))],
        );
      }

      final roots = (byParent[moreNode.parentId] ?? const [])
          .map((c) => attach(_withDepth(c, moreNode.depth)))
          .toList();

      List<Comment> replace(List<Comment> nodes) {
        final out = <Comment>[];
        for (final n in nodes) {
          if (identical(n, moreNode)) {
            out.addAll(roots);
          } else if (n.replies.isNotEmpty) {
            out.add(n.copyWith(replies: replace(n.replies)));
          } else {
            out.add(n);
          }
        }
        return out;
      }

      final current = state.valueOrNull ?? s;
      state = AsyncData(current.copyWith(
        comments: replace(current.comments),
        loadingMore: {...current.loadingMore}..remove(moreNode.fullname),
      ));
    } catch (_) {
      final current = state.valueOrNull ?? s;
      state = AsyncData(current.copyWith(
          loadingMore: {...current.loadingMore}..remove(moreNode.fullname)));
    }
  }

  Comment _withDepth(Comment c, int depth) => c.copyWith(depth: depth);
}

final commentsControllerProvider =
    AsyncNotifierProvider.autoDispose.family<CommentsController, PostThread, String>(
        CommentsController.new);
