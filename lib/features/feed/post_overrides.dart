import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/post.dart';

/// The current, user-visible state of a post that can change after it's fetched
/// (vote, score, saved, comment count). Lives in a shared store keyed by post id
/// so the feed card and the post-detail screen stay in sync — without a refresh.
class PostOverride {
  const PostOverride({
    required this.likes,
    required this.score,
    required this.numComments,
    required this.saved,
  });
  final bool? likes; // true=up, false=down, null=no vote
  final int score;
  final int numComments;
  final bool saved;

  PostOverride copyWith({
    bool? likes,
    bool clearLikes = false,
    int? score,
    int? numComments,
    bool? saved,
  }) =>
      PostOverride(
        likes: clearLikes ? null : (likes ?? this.likes),
        score: score ?? this.score,
        numComments: numComments ?? this.numComments,
        saved: saved ?? this.saved,
      );
}

class PostOverridesController extends Notifier<Map<String, PostOverride>> {
  @override
  Map<String, PostOverride> build() => {};

  /// Effective state for [p] (an override if one exists, else the post's own).
  PostOverride effective(Post p) =>
      state[p.id] ??
      PostOverride(
          likes: p.likes,
          score: p.score,
          numComments: p.numComments,
          saved: p.saved);

  void _set(String id, PostOverride o) => state = {...state, id: o};

  /// Applies a vote (toggling off if the same direction is tapped again).
  void setVote(Post p, int targetDir) {
    final cur = effective(p);
    final curDir = cur.likes == true ? 1 : (cur.likes == false ? -1 : 0);
    if (targetDir == curDir) return;
    _set(
      p.id,
      cur.copyWith(
        score: cur.score + (targetDir - curDir),
        likes: targetDir == 1 ? true : (targetDir == -1 ? false : null),
        clearLikes: targetDir == 0,
      ),
    );
  }

  void setSaved(Post p, bool saved) =>
      _set(p.id, effective(p).copyWith(saved: saved));

  void bumpComments(Post p, int delta) =>
      _set(p.id, effective(p).copyWith(numComments: effective(p).numComments + delta));

  /// Refresh from a freshly-fetched post (e.g. when the detail opens): always
  /// take the fresh comment count; seed vote/score/saved only if not already
  /// tracking a local change, so we never clobber a pending user action.
  void syncFromServer(Post p) {
    final existing = state[p.id];
    _set(
      p.id,
      PostOverride(
        likes: existing?.likes ?? p.likes,
        score: existing?.score ?? p.score,
        numComments: p.numComments,
        saved: existing?.saved ?? p.saved,
      ),
    );
  }
}

final postOverridesProvider =
    NotifierProvider<PostOverridesController, Map<String, PostOverride>>(
        PostOverridesController.new);
