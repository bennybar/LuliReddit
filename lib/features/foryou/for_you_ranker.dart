import 'dart:math' as math;

import '../../models/post.dart';
import '../history/interest_store.dart' show titleKeywords;
import 'for_you_stores.dart';

/// A post fetched for For You, and the request it came from.
class Candidate {
  const Candidate(this.post, this.source);
  final Post post;
  final String source; // best / rising / popular / favourite / interest / community
}

/// Interest at or above this counts a subreddit as one you engage with — for
/// both primary membership and the "Because you engage" label (they used to
/// disagree: 2 vs 4).
const kEngagedInterest = 2.0;

/// Everything the ranker knows about the user, snapshotted from the local
/// stores. Pure data, so ranking is deterministic and unit-testable.
class RankInputs {
  RankInputs({
    this.favourites = const {},
    this.subscribed = const {},
    this.interest = const {},
    this.subStats = const {},
    this.explicit = const ExplicitPrefs(),
    this.keywordScore,
    this.topKeyword,
    this.muted = const {},
    this.openedAt = const {},
    this.impressions,
    this.previousTop = const {},
    this.previousTitles = const [],
    this.discoveryAppetite = 1,
    DateTime? now,
  }) : now = now ?? DateTime.now().toUtc();

  final Set<String> favourites; // lowercase
  final Set<String> subscribed; // lowercase
  final Map<String, double> interest;
  final Map<String, (double, double)> subStats; // sub → (seen, engaged)
  final ExplicitPrefs explicit;
  final double Function(String title)? keywordScore; // idf-weighted, −6…8
  final String? Function(String title)? topKeyword;
  final Set<String> muted;
  final Map<String, int> openedAt; // post id → millis
  final double Function(String postId)? impressions; // faded count
  final Set<String> previousTop; // the top 10 before this refresh
  final List<String> previousTitles; // titles already on earlier pages
  final double discoveryAppetite; // discovery vs primary open rate
  final DateTime now;

  /// The same inputs once the subscription list has arrived.
  RankInputs withSubscriptions(Set<String> favourites, Set<String> subscribed) =>
      RankInputs(
        favourites: favourites,
        subscribed: subscribed,
        interest: interest,
        subStats: subStats,
        explicit: explicit,
        keywordScore: keywordScore,
        topKeyword: topKeyword,
        muted: muted,
        openedAt: openedAt,
        impressions: impressions,
        previousTop: previousTop,
        previousTitles: previousTitles,
        discoveryAppetite: discoveryAppetite,
        now: now,
      );
}

class RankResult {
  const RankResult(this.ranked, this.leftovers, this.meta);
  final List<Post> ranked;
  final List<Candidate> leftovers; // carried into the next page's pool
  final Map<String, ForYouMeta> meta;
}

class _Scored {
  _Scored(this.c, this.score, this.discovery, this.reason, this.why,
      this.story);
  final Candidate c;
  final double score;
  final bool discovery;
  final String reason;
  final List<String> why;
  final Set<String> story; // title keywords, for same-story detection
}

/// "For You" ranking.
///
/// score = additive · community · affinity · explicit · keywords · quality ·
///         fatigue — every factor positive, so nothing can flip sign (a
///         negative keyword sum used to turn the multipliers upside down:
///         opened posts and favourites ranking *below* others).
RankResult rankForYou(List<Candidate> pool, RankInputs i,
    {int pageSize = 50}) {
  // Global open rate, the baseline each subreddit's rate is compared with.
  var seenAll = 0.0, engAll = 0.0;
  for (final v in i.subStats.values) {
    seenAll += v.$1;
    engAll += v.$2;
  }
  final globalCtr = (engAll + 1) / (seenAll + 6);

  double ageHours(Post p) =>
      math.max(i.now.difference(p.created).inMinutes / 60.0, 1);

  // Per-subreddit velocity percentile, so small communities aren't drowned
  // out by raw point counts ("a top post *for this sub*" is what matters).
  final vels = <String, List<double>>{};
  for (final c in pool) {
    vels.putIfAbsent(c.post.subreddit, () => []).add(
        c.post.score / ageHours(c.post));
  }
  vels.forEach((_, v) => v.sort());
  double velPct(Post p) {
    final v = vels[p.subreddit]!;
    if (v.length == 1) return 0.7;
    final x = p.score / ageHours(p);
    var lo = 0, hi = v.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      v[mid] < x ? lo = mid + 1 : hi = mid;
    }
    return lo / (v.length - 1);
  }

  String pct(double f) =>
      '×${f.toStringAsFixed(f >= 10 ? 0 : (f >= 1 ? 1 : 2))}';

  _Scored? score(Candidate c) {
    final p = c.post;
    final sub = p.subreddit.toLowerCase();
    if (p.stickied || i.muted.contains(sub)) return null;
    final opened = i.openedAt[p.id];
    // Opened more than 12h ago: done with it.
    if (opened != null &&
        i.now.millisecondsSinceEpoch - opened > 12 * 3600 * 1000) {
      return null;
    }

    final fav = i.favourites.contains(sub);
    final subd = i.subscribed.contains(sub);
    final explicitSub = i.explicit.subs[sub] ?? 0;

    // Affinity: learned interest plus how often you actually open this
    // subreddit compared with everything else (rate, not count).
    var lift = 0.0;
    final st = i.subStats[sub];
    if (st != null && st.$1 >= 3) {
      final ctr = (st.$2 + 1) / (st.$1 + 6);
      lift = math.log(ctr / globalCtr).clamp(-1.5, 1.5);
    }
    final a = (i.interest[sub] ?? 0) + 4 * lift;
    // Two-sided and non-saturating: "less" and downvotes now demote (they
    // were clamped away), heavy use keeps ordering instead of capping out.
    final wInterest = a >= 0 ? 1 + 0.6 * math.log(1 + a / 3) : math.exp(a / 4);

    final primary = fav || subd || a >= kEngagedInterest || explicitSub > 0;
    final base = fav ? 4.0 : (subd || explicitSub > 0 ? 2.5 : 0.4);
    final eSub = explicitSub > 0 ? 1.6 : (explicitSub < 0 ? 0.3 : 1.0);

    final kw = i.keywordScore?.call(p.title) ?? 0;
    final kwMult = math.exp(0.08 * kw); // ×0.62 … ×1.9
    final words = titleKeywords(p.title);
    String? likedTopic, dislikedTopic;
    for (final w in words) {
      final v = i.explicit.topics[w];
      if (v != null && v < 0) dislikedTopic ??= w;
      if (v != null && v > 0) likedTopic ??= w;
    }
    final eTopic =
        dislikedTopic != null ? 0.3 : (likedTopic != null ? 1.6 : 1.0);

    final vp = velPct(p);
    final age = ageHours(p);
    final recency = 1 / (1 + age / 24);
    final additive = math.max(1.0, vp * 30 + recency * 30 + 15);
    final quality = 0.5 + p.upvoteRatio;

    // Freshness: each faded impression costs 20%; opened posts mostly go;
    // posts already in the last top 10 make room on refresh.
    final shown = i.impressions?.call(p.id) ?? 0;
    final fatigue = math.pow(0.8, shown).toDouble();
    final openedPen = opened != null ? 0.15 : 1.0;
    final churn = i.previousTop.contains(p.id) ? 0.7 : 1.0;

    final s = additive * base * wInterest * eSub * kwMult * eTopic * quality *
        fatigue * openedPen * churn;

    // Explanation from what actually moved the score.
    final topKw = i.topKeyword?.call(p.title);
    final drivers = <(double, String)>[
      if (likedTopic != null) (math.log(1.6), 'You asked for more about “$likedTopic”'),
      if (explicitSub > 0) (math.log(1.6), 'You asked for more from r/${p.subreddit}'),
      if (fav) (math.log(4 / 2.5), '★ Favourite · r/${p.subreddit}'),
      if (a >= kEngagedInterest)
        (math.log(wInterest), 'Because you engage with r/${p.subreddit}'),
      if (topKw != null && kw > 0)
        (math.log(kwMult), 'Because you read about “$topKw”'),
    ]..sort((x, y) => y.$1.compareTo(x.$1));
    final String reason;
    if (drivers.isNotEmpty && drivers.first.$1 > math.log(1.15)) {
      reason = drivers.first.$2;
    } else if (age < 6 && p.score > 1000 && vp > 0.8) {
      reason = '🔥 Trending on Reddit';
    } else if (subd) {
      reason = 'From r/${p.subreddit}';
    } else if (c.source == 'community') {
      reason = 'Discover · r/${p.subreddit}, near communities you visit';
    } else {
      reason = 'Discover · r/${p.subreddit}';
    }

    final why = <String>[
      fav
          ? 'r/${p.subreddit} is one of your favourites'
          : subd
              ? 'You\'re subscribed to r/${p.subreddit}'
              : 'Discovery: you don\'t follow r/${p.subreddit}',
      if (explicitSub != 0)
        'You asked for ${explicitSub > 0 ? 'more' : 'less'} from '
            'r/${p.subreddit} (${pct(eSub)})',
      if ((wInterest - 1).abs() > 0.05)
        'Your activity in r/${p.subreddit} (${pct(wInterest)})',
      if (likedTopic != null) 'You asked for more about “$likedTopic” (×1.6)',
      if (dislikedTopic != null)
        'You asked for less about “$dislikedTopic” (×0.3)',
      if ((kwMult - 1).abs() > 0.05)
        'Topics you read${topKw != null ? ', like “$topKw”' : ''} '
            '(${pct(kwMult)})',
      if (vp > 0.8) 'Doing well in r/${p.subreddit} right now',
      if (shown >= 0.5)
        'Seen ${shown.round()}× before (${pct(fatigue)})',
      if (opened != null) 'You already opened it (×0.15)',
      'Source: ${_sourceLabel(c.source)}',
    ];

    return _Scored(c, s, !primary, reason, why, words.toSet());
  }

  final scored = <_Scored>[];
  for (final c in pool) {
    final s = score(c);
    if (s != null) scored.add(s);
  }

  // Same link in several places (crossposts, the same article): keep the
  // best-scoring one.
  final byUrl = <String, _Scored>{};
  final unique = <_Scored>[];
  for (final s in scored..sort((a, b) => b.score.compareTo(a.score))) {
    final key = _normalisedUrl(s.c.post);
    if (key == null) {
      unique.add(s);
    } else if (!byUrl.containsKey(key)) {
      byUrl[key] = s;
      unique.add(s);
    }
  }

  // Same story told in different subreddits: the second copy is allowed at
  // least 15 slots after the first, a third never. Stories from earlier
  // pages count.
  final stories = <(Set<String>, int count, int lastPos)>[];
  for (final t in i.previousTitles) {
    final w = titleKeywords(t).toSet();
    if (w.length >= 3) stories.add((w, 1, -1000));
  }
  int? storyOf(Set<String> words) {
    if (words.length < 3) return null;
    for (var k = 0; k < stories.length; k++) {
      final shared = stories[k].$1.intersection(words).length;
      if (shared >= 3 && shared / stories[k].$1.union(words).length >= 0.5) {
        return k;
      }
    }
    return null;
  }

  // Greedy placement: each slot takes the best remaining post after a
  // diversity discount (same subreddit in the last 8, same media type in
  // the last 4), alternating in discovery at an adaptive rate.
  final primaryPool = unique.where((s) => !s.discovery).toList();
  final discoveryPool = unique.where((s) => s.discovery).toList();
  final every = (6 / i.discoveryAppetite.clamp(0.6, 1.5)).round().clamp(4, 10);
  final placed = <_Scored>[];
  final dropped = <_Scored>{};

  _Scored? pick(List<_Scored> from) {
    _Scored? best;
    var bestV = -1.0;
    final recentSubs = placed.reversed.take(8).map((s) => s.c.post.subreddit);
    final recentTypes = placed.reversed.take(4).map((s) => s.c.post.type);
    for (final s in from) {
      if (dropped.contains(s)) continue;
      final k = storyOf(s.story);
      if (k != null &&
          (stories[k].$2 >= 2 || placed.length - stories[k].$3 < 15)) {
        if (stories[k].$2 >= 2) dropped.add(s);
        continue;
      }
      final sameSub =
          recentSubs.where((x) => x == s.c.post.subreddit).length;
      final sameType = recentTypes.where((x) => x == s.c.post.type).length;
      final v = s.score * math.pow(0.6, sameSub) * math.pow(0.85, sameType);
      if (v > bestV) {
        bestV = v;
        best = s;
      }
    }
    return best;
  }

  while (placed.length < pageSize) {
    final wantDiscovery = (placed.length + 1) % every == 0;
    final s = (wantDiscovery ? pick(discoveryPool) : null) ??
        pick(primaryPool) ??
        pick(discoveryPool);
    if (s == null) break;
    (s.discovery ? discoveryPool : primaryPool).remove(s);
    final k = storyOf(s.story);
    if (k != null) {
      stories[k] = (stories[k].$1, stories[k].$2 + 1, placed.length);
    } else if (s.story.length >= 3) {
      stories.add((s.story, 1, placed.length));
    }
    placed.add(s);
  }

  // Unplaced posts aren't thrown away: the best carry over to the next page
  // (the per-subreddit cap used to discard them for good).
  final leftovers = ([...primaryPool, ...discoveryPool]
        ..removeWhere(dropped.contains)
        ..sort((a, b) => b.score.compareTo(a.score)))
      .take(120)
      .map((s) => s.c)
      .toList();

  final meta = <String, ForYouMeta>{};
  final ranked = <Post>[];
  for (var k = 0; k < placed.length; k++) {
    final s = placed[k];
    ranked.add(s.c.post.copyWith(feedReason: s.reason));
    meta[s.c.post.id] = ForYouMeta(
        source: s.c.source, discovery: s.discovery, position: k, why: s.why);
  }
  return RankResult(ranked, leftovers, meta);
}

String _sourceLabel(String source) => switch (source) {
      'best' => 'your subscriptions (Best)',
      'rising' => 'rising in your subscriptions',
      'popular' => 'r/popular',
      'favourite' => 'a favourite community',
      'interest' => 'a community you engage with',
      'community' => 'a community you\'ve visited',
      'carry' => 'held over from the previous page',
      _ => source,
    };

/// A link post's URL without scheme, `www.`, tracking parameters or
/// fragment — to spot the same link posted in several places. Null for text
/// posts (their URL is their own permalink).
String? _normalisedUrl(Post p) {
  if (p.isSelf || p.url.isEmpty) return null;
  final u = Uri.tryParse(p.url);
  if (u == null || u.host.isEmpty) return null;
  final host = u.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
  final query = Map.of(u.queryParameters)
    ..removeWhere((k, _) => k.startsWith('utm_'));
  final q = (query.keys.toList()..sort()).map((k) => '$k=${query[k]}').join('&');
  return '$host${u.path}${q.isEmpty ? '' : '?$q'}';
}
