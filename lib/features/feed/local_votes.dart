/// −1 / 0 / +1 for a `likes` value (false / null / true).
int dirOf(bool? likes) => likes == true ? 1 : (likes == false ? -1 : 0);

/// The `likes` value for a vote direction.
bool? likesOf(int dir) => dir == 1 ? true : (dir == -1 ? false : null);

class _Pending {
  const _Pending(this.dir, this.baseScore, this.baseDir, this.at);
  final int dir;
  final int baseScore;
  final int baseDir;
  final DateTime at;
}

/// Your recent votes, kept until Reddit's copy shows them. Reddit's copies
/// lag: a fetch soon after voting can still carry the old vote, or the new
/// vote with the score from before it. Trusting it blindly made a vote look
/// un-counted when you went back into a thread.
class LocalVotes {
  static const _window = Duration(minutes: 15);

  final _pending = <String, _Pending>{};
  // The last server (score, dir) seen per id: the baseline for the next vote.
  final _seen = <String, (int, int)>{};

  /// You voted [dir] on [id]; [serverScore] / [serverLikes] are the copy you
  /// voted on.
  void record(String id, int dir, int serverScore, bool? serverLikes) {
    final prev = _pending[id];
    final (score, d) = _seen[id] ?? (serverScore, dirOf(serverLikes));
    _pending[id] = _Pending(dir, prev?.baseScore ?? score,
        prev?.baseDir ?? d, DateTime.now());
  }

  /// The vote and score to show for a fresh server copy of [id].
  (bool?, int) reconcile(String id, bool? serverLikes, int serverScore) {
    final sDir = dirOf(serverLikes);
    final p = _pending[id];
    if (p == null || DateTime.now().difference(p.at) > _window) {
      _pending.remove(id);
      _seen[id] = (serverScore, sDir);
      return (serverLikes, serverScore);
    }
    final likes = likesOf(p.dir);
    // Reddit doesn't have the vote yet: its score is from the old one.
    if (sDir != p.dir) return (likes, serverScore + (p.dir - sDir));
    // The vote is in but the score hasn't moved since you voted.
    if (serverScore == p.baseScore) {
      return (likes, serverScore + (p.dir - p.baseDir));
    }
    // Reddit has caught up.
    _pending.remove(id);
    _seen[id] = (serverScore, sDir);
    return (serverLikes, serverScore);
  }

  bool isPending(String id) => _pending.containsKey(id);

  void clear() {
    _pending.clear();
    _seen.clear();
  }
}
