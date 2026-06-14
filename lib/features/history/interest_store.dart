import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../settings/settings_controller.dart';

/// Suffix that keys all learning stores to the active account, so taste
/// profiles never leak between accounts. '' while logged out / loading.
String _userSuffix(Ref ref) {
  final u = ref.watch(
      authControllerProvider.select((s) => s.valueOrNull?.username ?? ''));
  return u.isEmpty ? '' : '_${u.toLowerCase()}';
}

/// One-time migration: pre-multi-account installs stored under the bare key.
String userScopedPrefsKey(Ref ref, String baseKey) {
  final key = '$baseKey${_userSuffix(ref)}';
  final prefs = ref.read(sharedPrefsProvider);
  if (key != baseKey &&
      !prefs.containsKey(key) &&
      prefs.containsKey(baseKey)) {
    final legacy = prefs.get(baseKey);
    if (legacy is String) prefs.setString(key, legacy);
    if (legacy is List) prefs.setStringList(key, legacy.cast<String>());
    prefs.remove(baseKey);
  }
  return key;
}

/// On-device interest model: a per-subreddit affinity score that learns from
/// the user's own actions (upvote / downvote / save / open / comment / share).
/// Entirely local — it never leaves the device and powers "For You (Beta)".
/// Weights decay daily so the feed tracks your *current* taste.
class InterestStore extends Notifier<Map<String, double>> {
  static const _base = 'interest_weights';
  static const _decayPerDay = 0.95;
  late String _key;

  @override
  Map<String, double> build() {
    _key = userScopedPrefsKey(ref, _base);
    final prefs = ref.read(sharedPrefsProvider);
    final raw = prefs.getString(_key);
    if (raw == null) return {};
    Map<String, double> weights;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      weights = {
        for (final e in m.entries)
          if (e.key != '_ts') e.key: (e.value as num).toDouble()
      };
      // Daily exponential decay since the last persist.
      final ts = (m['_ts'] as num?)?.toInt();
      if (ts != null) {
        final days = DateTime.now()
                .difference(DateTime.fromMillisecondsSinceEpoch(ts))
                .inHours /
            24.0;
        if (days > 0.04) {
          final f = math.pow(_decayPerDay, days).toDouble();
          weights = {
            for (final e in weights.entries)
              if ((e.value * f).abs() >= 0.3) e.key: e.value * f
          };
          _persistMap(weights);
        }
      }
    } catch (_) {
      return {};
    }
    return weights;
  }

  double weightFor(String subreddit) => state[subreddit.toLowerCase()] ?? 0;

  void bump(String subreddit, double delta) {
    if (subreddit.isEmpty) return;
    // Only learn when history/personalization tracking is enabled.
    if (!ref.read(settingsControllerProvider).trackHistory) return;
    final key = subreddit.toLowerCase();
    final next = ((state[key] ?? 0) + delta).clamp(-8.0, 40.0);
    state = {...state, key: next};
    _persistMap(state);
  }

  /// Top affinity subreddits above [min], strongest first.
  List<String> top(int n, {double min = 1.0}) {
    final entries = state.entries.where((e) => e.value >= min).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in entries.take(n)) e.key];
  }

  /// Forgets the learned affinity for one subreddit (used by the "Manage For
  /// You" screen to undo a "show less"/"show more"). Works regardless of the
  /// track-history setting.
  void reset(String subreddit) {
    final key = subreddit.toLowerCase();
    if (!state.containsKey(key)) return;
    state = {...state}..remove(key);
    _persistMap(state);
  }

  void clear() {
    state = {};
    ref.read(sharedPrefsProvider).remove(_key);
  }

  void _persistMap(Map<String, double> m) =>
      ref.read(sharedPrefsProvider).setString(
          _key, jsonEncode({...m, '_ts': DateTime.now().millisecondsSinceEpoch}));
}

final interestStoreProvider =
    NotifierProvider<InterestStore, Map<String, double>>(InterestStore.new);

/// Subreddits the user muted from the "For You" feed (local only).
class MutedSubsController extends Notifier<Set<String>> {
  static const _base = 'muted_subs';
  late String _key;

  @override
  Set<String> build() {
    _key = userScopedPrefsKey(ref, _base);
    return (ref.read(sharedPrefsProvider).getStringList(_key) ?? const [])
        .toSet();
  }

  bool contains(String sub) => state.contains(sub.toLowerCase());

  void toggle(String sub) {
    final key = sub.toLowerCase();
    final next = {...state};
    next.contains(key) ? next.remove(key) : next.add(key);
    state = next;
    ref.read(sharedPrefsProvider).setStringList(_key, next.toList());
  }
}

final mutedSubsProvider =
    NotifierProvider<MutedSubsController, Set<String>>(MutedSubsController.new);

// ---------------------------------------------------------------------------
// Keyword affinity — a tiny on-device content model over post titles.
// ---------------------------------------------------------------------------

const _stopwords = {
  'this', 'that', 'with', 'from', 'have', 'what', 'when', 'where', 'will',
  'just', 'like', 'your', 'about', 'they', 'them', 'their', 'there', 'been',
  'were', 'after', 'before', 'into', 'over', 'under', 'than', 'then',
  'because', 'would', 'could', 'should', 'these', 'those', 'only', 'some',
  'most', 'more', 'very', 'much', 'many', 'made', 'make', 'makes', 'making',
  'years', 'year', 'today', 'every', 'first', 'people', 'reddit', 'post',
  'does', 'doesn', 'while', 'being', 'still', 'until', 'never', 'always',
  'getting', 'here', 'looks', 'thing', 'things', 'someone', 'anyone',
};

/// Tokenizes a post title into learnable keywords.
List<String> titleKeywords(String title) {
  final words = title
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .split(RegExp(r'\s+'));
  return [
    for (final w in words)
      if (w.length >= 4 &&
          !_stopwords.contains(w) &&
          !RegExp(r'^\d+$').hasMatch(w))
        w
  ].take(14).toList();
}

/// Learns which title keywords you engage with (upvote/save → +, downvote →
/// −). Powers within-subreddit taste ("F1 but not NBA") and keyword-matched
/// discovery. Local-only; decays like the interest store.
class KeywordStore extends Notifier<Map<String, double>> {
  static const _base = 'keyword_weights';
  static const _cap = 400;
  late String _key;

  @override
  Map<String, double> build() {
    _key = userScopedPrefsKey(ref, _base);
    final raw = ref.read(sharedPrefsProvider).getString(_key);
    if (raw == null) return {};
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      var weights = {
        for (final e in m.entries)
          if (e.key != '_ts') e.key: (e.value as num).toDouble()
      };
      final ts = (m['_ts'] as num?)?.toInt();
      if (ts != null) {
        final days = DateTime.now()
                .difference(DateTime.fromMillisecondsSinceEpoch(ts))
                .inHours /
            24.0;
        if (days > 0.04) {
          final f = math.pow(0.97, days).toDouble();
          weights = {
            for (final e in weights.entries)
              if ((e.value * f).abs() >= 0.2) e.key: e.value * f
          };
          _persist(weights);
        }
      }
      return weights;
    } catch (_) {
      return {};
    }
  }

  /// Learns from a post title. [delta] applies per keyword (+1 up, −1 down).
  void bumpTitle(String title, double delta) {
    if (!ref.read(settingsControllerProvider).trackHistory) return;
    final words = titleKeywords(title);
    if (words.isEmpty) return;
    final next = {...state};
    for (final w in words) {
      next[w] = ((next[w] ?? 0) + delta).clamp(-10.0, 10.0);
    }
    // Keep the map bounded: drop the weakest signals.
    if (next.length > _cap) {
      final entries = next.entries.toList()
        ..sort((a, b) => a.value.abs().compareTo(b.value.abs()));
      for (final e in entries.take(next.length - _cap)) {
        next.remove(e.key);
      }
    }
    state = next;
    _persist(next);
  }

  /// Total affinity of a title against the learned keywords.
  double scoreTitle(String title) {
    if (state.isEmpty) return 0;
    var sum = 0.0;
    for (final w in titleKeywords(title)) {
      sum += state[w] ?? 0;
    }
    return sum.clamp(-6.0, 8.0);
  }

  /// The strongest learned keyword present in [title] (for explainability).
  String? topKeywordIn(String title) {
    String? best;
    var bestW = 2.0; // only surface meaningful signals
    for (final w in titleKeywords(title)) {
      final v = state[w] ?? 0;
      if (v > bestW) {
        bestW = v;
        best = w;
      }
    }
    return best;
  }

  void clear() {
    state = {};
    ref.read(sharedPrefsProvider).remove(_key);
  }

  void _persist(Map<String, double> m) =>
      ref.read(sharedPrefsProvider).setString(
          _key, jsonEncode({...m, '_ts': DateTime.now().millisecondsSinceEpoch}));
}

final keywordStoreProvider =
    NotifierProvider<KeywordStore, Map<String, double>>(KeywordStore.new);

// ---------------------------------------------------------------------------
// Impressions — posts shown in For You but never opened get demoted.
// ---------------------------------------------------------------------------

/// Counts how many times a post was *shown* in the For You feed. Posts shown
/// twice without being opened are demoted on the next build, so refreshes feel
/// fresh without requiring mark-as-read. Bounded (~600 ids), per-account.
class ImpressionStore extends Notifier<Map<String, int>> {
  static const _base = 'fy_impressions';
  static const _cap = 600;
  late String _key;
  final _pending = <String>{};
  bool _flushScheduled = false;

  @override
  Map<String, int> build() {
    _key = userScopedPrefsKey(ref, _base);
    final raw = ref.read(sharedPrefsProvider).getString(_key);
    if (raw == null) return {};
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return {for (final e in m.entries) e.key: (e.value as num).toInt()};
    } catch (_) {
      return {};
    }
  }

  /// Records one impression. Batched + deduped per session, so it's cheap to
  /// call from widget build methods.
  void record(String postId) {
    if (postId.isEmpty || _pending.contains(postId)) return;
    _pending.add(postId);
    if (_flushScheduled) return;
    _flushScheduled = true;
    Future<void>.delayed(const Duration(seconds: 2), _flush);
  }

  void _flush() {
    _flushScheduled = false;
    if (_pending.isEmpty) return;
    final next = {...state};
    for (final id in _pending) {
      next[id] = (next[id] ?? 0) + 1;
    }
    _pending.clear();
    if (next.length > _cap) {
      final keys = next.keys.toList();
      for (final k in keys.take(next.length - _cap)) {
        next.remove(k);
      }
    }
    state = next;
    ref.read(sharedPrefsProvider).setString(_key, jsonEncode(next));
  }

  void clear() {
    state = {};
    ref.read(sharedPrefsProvider).remove(_key);
  }
}

final impressionStoreProvider =
    NotifierProvider<ImpressionStore, Map<String, int>>(ImpressionStore.new);
