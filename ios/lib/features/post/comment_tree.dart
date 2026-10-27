import '../../models/comment.dart';

/// Pure comment-tree operations (no Flutter), shared by [CommentsController]
/// and the unit tests.
class CommentTree {
  CommentTree._();

  /// The collapse-set key that folds [id]'s replies away (its own text
  /// stays).
  static String folded(String id) => 'f:$id';

  /// How many comments are under [c] (all levels; "more" rows not counted).
  static int replyCount(Comment c) => c.replies
      .fold(0, (n, r) => r.isMore ? n : n + 1 + replyCount(r));

  /// Depth-first visible rows: a collapsed comment's replies (and a "more"
  /// node's) are skipped. A [folded] comment (`f:<id>` in [collapsed]: the
  /// "Open threads collapsed" setting) shows in full but hides its replies.
  static List<Comment> flatten(List<Comment> nodes, Set<String> collapsed) {
    final out = <Comment>[];
    void walk(Comment c) {
      out.add(c);
      if (!c.isMore &&
          !collapsed.contains(c.id) &&
          !collapsed.contains(folded(c.id))) {
        c.replies.forEach(walk);
      }
    }

    nodes.forEach(walk);
    return out;
  }

  /// [c] and its parents up to the top-level comment, top first — the chain
  /// a "Share as image" card shows (at most 8). Visible rows include every
  /// ancestor of a visible comment.
  static List<Comment> chainTo(List<Comment> flat, Comment c) {
    final byName = {for (final x in flat) x.fullname: x};
    final chain = [c];
    var parent = byName[c.parentId];
    while (parent != null && chain.length < 8) {
      chain.insert(0, parent);
      parent = byName[parent.parentId];
    }
    return chain;
  }

  /// Splices [reply] under [parentFullname] (newest first), at its parent's
  /// depth + 1.
  static List<Comment> insertReply(
          List<Comment> nodes, String parentFullname, Comment reply) =>
      [
        for (final n in nodes)
          if (n.fullname == parentFullname)
            n.copyWith(
                replies: [reply.copyWith(depth: n.depth + 1), ...n.replies])
          else if (n.replies.isEmpty)
            n
          else
            n.copyWith(
                replies: insertReply(n.replies, parentFullname, reply)),
      ];

  /// Applies [change] to one comment. Vote and save state live in the tree
  /// rather than the row, which the list disposes as it scrolls off-screen —
  /// so they survive scrolling away and back. Untouched subtrees keep their
  /// identity.
  static List<Comment> update(List<Comment> nodes, String fullname,
          Comment Function(Comment) change) =>
      [
        for (final n in nodes)
          if (n.fullname == fullname)
            change(n)
          else if (n.replies.isEmpty)
            n
          else
            _withReplies(n, update(n.replies, fullname, change)),
      ];

  static Comment _withReplies(Comment n, List<Comment> r) {
    for (var i = 0; i < r.length; i++) {
      if (!identical(r[i], n.replies[i])) return n.copyWith(replies: r);
    }
    return n;
  }

  /// After deleting a comment: drop it, or — if it has replies — keep the
  /// replies under a "[deleted]" placeholder, as Reddit does.
  static List<Comment> remove(List<Comment> nodes, String fullname) => [
        for (final n in nodes)
          if (n.fullname != fullname)
            n.replies.isEmpty
                ? n
                : n.copyWith(replies: remove(n.replies, fullname))
          else if (n.replies.isNotEmpty)
            n.copyWith(author: '[deleted]', body: '[deleted]', media: const {}),
      ];

  /// Re-nests a flat /api/morechildren result by parent_id and splices it in
  /// place of [moreNode] (matched by fullname).
  static List<Comment> replaceMore(
      List<Comment> nodes, Comment moreNode, List<Comment> flat) {
    final byParent = <String, List<Comment>>{};
    for (final c in flat) {
      byParent.putIfAbsent(c.parentId, () => []).add(c);
    }
    Comment attach(Comment c, int depth) => c.copyWith(
          depth: depth,
          replies: [
            for (final k in byParent[c.fullname] ?? const <Comment>[])
              attach(k, depth + 1)
          ],
        );
    final roots = [
      for (final c in byParent[moreNode.parentId] ?? const <Comment>[])
        attach(c, moreNode.depth)
    ];

    List<Comment> replace(List<Comment> list) {
      final out = <Comment>[];
      for (final n in list) {
        if (n.isMore && n.fullname == moreNode.fullname) {
          out.addAll(roots);
        } else if (n.replies.isNotEmpty) {
          out.add(n.copyWith(replies: replace(n.replies)));
        } else {
          out.add(n);
        }
      }
      return out;
    }

    return replace(nodes);
  }

  /// "Hide usernames" on a share image: "Commenter 1, 2…", consistent within
  /// the image.
  static List<String> shareNames(List<Comment> chain, bool hide) {
    final names = <String, String>{};
    return [
      for (final c in chain)
        hide
            ? names.putIfAbsent(c.author, () => 'Commenter ${names.length + 1}')
            : 'u/${c.author}'
    ];
  }
}
