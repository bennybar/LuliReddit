import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../history/interest_store.dart';
import '../settings/settings_controller.dart';

// Supporting stores for "For You". All local and per account.

Map<String, dynamic> _readJson(Ref ref, String key) {
  final raw = ref.read(sharedPrefsProvider).getString(key);
  if (raw == null) return {};
  try {
    return jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {
    return {};
  }
}

void _writeJson(Ref ref, String key, Object value) =>
    ref.read(sharedPrefsProvider).setString(key, jsonEncode(value));

// ---------------------------------------------------------------------------
// Explicit choices
// ---------------------------------------------------------------------------

/// "More / Less from r/x" and "More / Less about 'topic'": what the user
/// *asked* for, kept apart from learned behaviour. Doesn't fade, isn't wiped
/// by resetting a learned weight, and works with history tracking off —
/// explicit controls shouldn't depend on passive tracking.
class ExplicitPrefs {
  const ExplicitPrefs({this.subs = const {}, this.topics = const {}});
  final Map<String, int> subs; // lowercase subreddit → +1 / −1
  final Map<String, int> topics; // keyword (titleKeywords form) → +1 / −1

  bool get isEmpty => subs.isEmpty && topics.isEmpty;
}

class ExplicitPrefsController extends Notifier<ExplicitPrefs> {
  static const _base = 'fy_explicit';
  late String _key;

  @override
  ExplicitPrefs build() {
    _key = userScopedPrefsKey(ref, _base);
    final m = _readJson(ref, _key);
    Map<String, int> g(String k) => {
          for (final e in ((m[k] as Map?) ?? const {}).entries)
            '${e.key}': (e.value as num).toInt()
        };
    return ExplicitPrefs(subs: g('subs'), topics: g('topics'));
  }

  void _set(ExplicitPrefs p) {
    state = p;
    _writeJson(ref, _key, {'subs': p.subs, 'topics': p.topics});
  }

  /// [value] +1 (more), −1 (less) or 0 (forget).
  void setSub(String sub, int value) {
    final next = {...state.subs}..remove(sub.toLowerCase());
    if (value != 0) next[sub.toLowerCase()] = value;
    _set(ExplicitPrefs(subs: next, topics: state.topics));
  }

  void setTopic(String topic, int value) {
    final next = {...state.topics}..remove(topic);
    if (value != 0) next[topic] = value;
    _set(ExplicitPrefs(subs: state.subs, topics: next));
  }

  void clear() => _set(const ExplicitPrefs());
}

final explicitPrefsProvider =
    NotifierProvider<ExplicitPrefsController, ExplicitPrefs>(
        ExplicitPrefsController.new);

// ---------------------------------------------------------------------------
// Per-subreddit exposure vs engagement
// ---------------------------------------------------------------------------

/// How often each subreddit's posts were seen in For You vs engaged with
/// (opened, read 30s+, voted). Lets the ranker learn *rates*: a subreddit you
/// keep scrolling past fades on its own, and a niche one you always open
/// rises even with few impressions. Decays like the interest model.
class SubStatsController extends Notifier<Map<String, (double, double)>> {
  static const _base = 'fy_substats';
  static const _decayPerDay = 0.95;
  static const _cap = 400;
  late String _key;
  int? _ts;

  @override
  Map<String, (double, double)> build() {
    _key = userScopedPrefsKey(ref, _base);
    final m = _readJson(ref, _key);
    _ts = (m['_ts'] as num?)?.toInt();
    final f = decayFactor(_ts, _decayPerDay);
    return {
      for (final e in m.entries)
        if (!e.key.startsWith('_'))
          e.key: ((e.value[0] as num) * f, (e.value[1] as num) * f),
    };
  }

  void _add(String sub, double impr, double eng) {
    if (!ref.read(settingsControllerProvider).trackHistory) return;
    final f = decayFactor(_ts, _decayPerDay);
    final next = {
      for (final e in state.entries)
        if (e.value.$1 * f >= 0.05) e.key: (e.value.$1 * f, e.value.$2 * f)
    };
    final key = sub.toLowerCase();
    final cur = next.remove(key) ?? (0.0, 0.0);
    next[key] = (cur.$1 + impr, cur.$2 + eng);
    while (next.length > _cap) {
      next.remove(next.keys.first);
    }
    _ts = DateTime.now().millisecondsSinceEpoch;
    state = next;
    _writeJson(ref, _key, {
      '_ts': _ts,
      for (final e in next.entries) e.key: [e.value.$1, e.value.$2],
    });
  }

  void impression(String sub) => _add(sub, 1, 0);
  void engaged(String sub) => _add(sub, 0, 1);

  void clear() {
    state = {};
    ref.read(sharedPrefsProvider).remove(_key);
  }
}

final subStatsProvider =
    NotifierProvider<SubStatsController, Map<String, (double, double)>>(
        SubStatsController.new);

// ---------------------------------------------------------------------------
// Word rarity (IDF)
// ---------------------------------------------------------------------------

/// How many candidate titles each word appeared in (decayed), so learned
/// keywords are weighted by how distinctive they are: "verstappen" says far
/// more about you than "help". Updated from every For You build.
class DocFreqController extends Notifier<Map<String, double>> {
  static const _base = 'fy_docfreq';
  static const _decayPerDay = 0.9;
  static const _cap = 2000;
  late String _key;
  int? _ts;
  double _docs = 0; // decayed number of titles seen

  @override
  Map<String, double> build() {
    _key = userScopedPrefsKey(ref, _base);
    final m = _readJson(ref, _key);
    _ts = (m['_ts'] as num?)?.toInt();
    final f = decayFactor(_ts, _decayPerDay);
    _docs = ((m['_n'] as num?)?.toDouble() ?? 0) * f;
    return {
      for (final e in m.entries)
        if (!e.key.startsWith('_')) e.key: (e.value as num).toDouble() * f,
    };
  }

  void observe(Iterable<String> titles) {
    final f = decayFactor(_ts, _decayPerDay);
    final next = {for (final e in state.entries) e.key: e.value * f};
    var docs = _docs * f;
    for (final t in titles) {
      docs += 1;
      for (final w in titleKeywords(t).toSet()) {
        next.remove(w);
        next[w] = (state[w] ?? 0) * f + 1; // re-insert: recency order
      }
    }
    while (next.length > _cap) {
      next.remove(next.keys.first);
    }
    _ts = DateTime.now().millisecondsSinceEpoch;
    _docs = docs;
    state = next;
    _writeJson(ref, _key, {...next, '_ts': _ts, '_n': docs});
  }

  /// Rarity weight for [word], normalised so a typical word is ~1: rare words
  /// count up to 2×, very common ones as little as 0.2×.
  double idf(String word) {
    if (_docs < 50) return 1; // not enough data yet
    final v = math.log((_docs + 1) / ((state[word] ?? 0) + 1));
    final typical = math.log((_docs + 1) / 4); // seen in ~3 of N titles
    return (v / typical).clamp(0.2, 2.0);
  }

  void clear() {
    state = {};
    _docs = 0;
    ref.read(sharedPrefsProvider).remove(_key);
  }
}

final docFreqProvider =
    NotifierProvider<DocFreqController, Map<String, double>>(
        DocFreqController.new);

// ---------------------------------------------------------------------------
// Local metrics
// ---------------------------------------------------------------------------

/// Rolling 7-day counters of how For You performs (impressions, opens,
/// 30s+ reads, votes, More/Less taps, split by primary vs discovery and by
/// source). On-device only, never uploaded, and only kept while history
/// tracking is on. Shown on a hidden debug screen in Manage For You, and used
/// to adapt how much discovery the feed mixes in.
class ForYouMetrics extends Notifier<Map<String, Map<String, int>>> {
  static const _base = 'fy_metrics';
  late String _key;

  static String _day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  Map<String, Map<String, int>> build() {
    _key = userScopedPrefsKey(ref, _base);
    final m = _readJson(ref, _key);
    return {
      for (final e in m.entries)
        e.key: {
          for (final c in (e.value as Map).entries)
            '${c.key}': (c.value as num).toInt()
        },
    };
  }

  void count(String metric, [int n = 1]) {
    if (!ref.read(settingsControllerProvider).trackHistory) return;
    final now = DateTime.now();
    final keep = {
      for (var i = 0; i < 7; i++) _day(now.subtract(Duration(days: i)))
    };
    final today = _day(now);
    final next = {
      for (final e in state.entries)
        if (keep.contains(e.key)) e.key: {...e.value}
    };
    final bucket = next.putIfAbsent(today, () => {});
    bucket[metric] = (bucket[metric] ?? 0) + n;
    state = next;
    _writeJson(ref, _key, next);
  }

  /// Totals over the last 7 days.
  Map<String, int> totals() {
    final out = <String, int>{};
    for (final day in state.values) {
      day.forEach((k, v) => out[k] = (out[k] ?? 0) + v);
    }
    return out;
  }

  /// How often discovery posts get opened relative to primary ones (1 =
  /// same). Drives the adaptive discovery share; 1 until there's data.
  double discoveryAppetite() {
    final t = totals();
    final di = t['impr.discovery'] ?? 0, pi = t['impr.primary'] ?? 0;
    if (di < 30 || pi < 30) return 1;
    final dr = ((t['open.discovery'] ?? 0) + 1) / (di + 6);
    final pr = ((t['open.primary'] ?? 0) + 1) / (pi + 6);
    return dr / pr;
  }

  void clear() {
    state = {};
    ref.read(sharedPrefsProvider).remove(_key);
  }
}

final forYouMetricsProvider =
    NotifierProvider<ForYouMetrics, Map<String, Map<String, int>>>(
        ForYouMetrics.new);

// ---------------------------------------------------------------------------
// Why each post is in the feed
// ---------------------------------------------------------------------------

/// What the ranker knew about a post it placed: where it came from, whether
/// it was a discovery pick, and the factors behind its score (for "Why am I
/// seeing this?" and the metrics).
class ForYouMeta {
  const ForYouMeta({
    required this.source,
    required this.discovery,
    required this.position,
    required this.why,
  });
  final String source; // best / rising / popular / favourite / interest / community
  final bool discovery;
  final int position; // 0-based slot on its page
  final List<String> why;
}

final forYouMetaProvider =
    StateProvider<Map<String, ForYouMeta>>((ref) => const {});
