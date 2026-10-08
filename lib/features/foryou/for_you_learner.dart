import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/post.dart';
import '../history/interest_store.dart';
import 'for_you_stores.dart';

/// The one place For You learns from what the user does. Every call site
/// used to bump the stores itself, with drift between them (the post-detail
/// vote never taught keywords; unsave reverted interest but not keywords;
/// re-voting kept adding up).
///
/// Learned signals respect the history-tracking switch (inside each store);
/// explicit More/Less choices live in [ExplicitPrefs] and always apply.
class ForYouLearner {
  ForYouLearner(this._ref);
  final Ref _ref;
  final _seen = <String>{}; // impressions counted this session
  final _engaged = <String>{}; // posts already counted as engaged

  InterestStore get _interest => _ref.read(interestStoreProvider.notifier);
  KeywordStore get _keywords => _ref.read(keywordStoreProvider.notifier);
  ForYouMetrics get _metrics => _ref.read(forYouMetricsProvider.notifier);

  String _group(Post p) {
    final m = _ref.read(forYouMetaProvider)[p.id];
    return m == null ? 'other' : (m.discovery ? 'discovery' : 'primary');
  }

  void _learn(Post p, double subDelta, double titleDelta) {
    _interest.bump(p.subreddit, subDelta);
    if (titleDelta != 0) _keywords.bumpTitle(p.title, titleDelta);
  }

  /// Opened, read 30s+, or voted: counts once per post toward the
  /// subreddit's engagement rate.
  void _engage(Post p, String event) {
    _metrics.count('$event.${_group(p)}');
    if (_engaged.add(p.id)) {
      _ref.read(subStatsProvider.notifier).engaged(p.subreddit);
    }
  }

  /// A For You card that stayed on screen for a second.
  void impression(Post p) {
    _ref.read(impressionStoreProvider.notifier).record(p.id);
    if (!_seen.add(p.id)) return;
    _ref.read(subStatsProvider.notifier).impression(p.subreddit);
    final m = _ref.read(forYouMetaProvider)[p.id];
    _metrics.count('impr.${_group(p)}');
    if (m != null) {
      _metrics.count('src.${m.source}');
      if (m.position < 10) _metrics.count('impr.top10');
    }
  }

  /// A vote changed from [from] to [to] (−1, 0, +1). Learns only the change,
  /// so up → none → up nets +1 vote, not +2, and switching up → down lands on
  /// a plain downvote.
  void vote(Post p, int from, int to) {
    if (from == to) return;
    double sub(int d) => d == 1 ? 2 : (d == -1 ? -1.5 : 0);
    double kw(int d) => d == 1 ? 1 : (d == -1 ? -0.8 : 0);
    _learn(p, sub(to) - sub(from), kw(to) - kw(from));
    if (to != 0) _engage(p, 'vote');
  }

  void save(Post p, bool saved) =>
      _learn(p, saved ? 3 : -3, saved ? 1.5 : -1.5);

  void open(Post p) {
    _learn(p, 0.5, 0);
    _engage(p, 'open');
  }

  void viewMedia(Post p) => _learn(p, 1, 0);

  /// Commenting is the strongest engagement signal there is.
  void comment(Post p) => _learn(p, 2.5, 1);

  void share(Post p) => _learn(p, 1.5, 0.75);

  /// Time in the thread: 30s+ ([long] = 2min+, on top of it).
  void read(Post p, {bool long = false}) {
    _learn(p, long ? 1.5 : 1, long ? 1 : 0.5);
    if (!long) _engage(p, 'read30');
  }

  /// Backed out within 3 seconds.
  void bounce(Post p) => _learn(p, -0.5, 0);

  /// Explicit "More/Less from r/x" (+1 / −1 / 0 to clear).
  void subPreference(Post p, int value) {
    _ref.read(explicitPrefsProvider.notifier).setSub(p.subreddit, value);
    if (value != 0) _metrics.count(value > 0 ? 'more' : 'less');
  }

  /// Explicit "More/Less about 'topic'".
  void topicPreference(String topic, int value) {
    _ref.read(explicitPrefsProvider.notifier).setTopic(topic, value);
    if (value != 0) _metrics.count(value > 0 ? 'more' : 'less');
  }
}

final forYouLearnerProvider = Provider<ForYouLearner>(ForYouLearner.new);
