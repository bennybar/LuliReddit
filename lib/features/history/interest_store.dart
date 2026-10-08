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

/// Exponential decay factor for the time since [tsMillis].
double decayFactor(int? tsMillis, double perDay) {
  if (tsMillis == null) return 1;
  final days = DateTime.now()
          .difference(DateTime.fromMillisecondsSinceEpoch(tsMillis))
          .inMinutes /
      (60 * 24);
  return days <= 0 ? 1 : math.pow(perDay, days).toDouble();
}

/// On-device interest model: a per-subreddit affinity score that learns from
/// the user's own actions (upvote / downvote / save / open / comment / share).
/// Entirely local — it never leaves the device and powers "For You (Beta)".
/// Weights decay daily so the feed tracks your *current* taste.
class InterestStore extends Notifier<Map<String, double>> {
  static const _base = 'interest_weights';
  static const _decayPerDay = 0.95;
  late String _key;
  int? _ts; // when the weights were last decayed + saved

  @override
  Map<String, double> build() {
    _key = userScopedPrefsKey(ref, _base);
    final raw = ref.read(sharedPrefsProvider).getString(_key);
    if (raw == null) return {};
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      _ts = (m['_ts'] as num?)?.toInt();
      return _decayed({
        for (final e in m.entries)
          if (!e.key.startsWith('_')) e.key: (e.value as num).toDouble()
      });
    } catch (_) {
      return {};
    }
  }

  /// Applies the decay owed since the last save. Done on every change, not
  /// just at startup: an app left running for days used to save undecayed
  /// weights with a fresh timestamp, losing that decay for good.
  Map<String, double> _decayed(Map<String, double> w) {
    final f = decayFactor(_ts, _decayPerDay);
    if (f > 0.999) return w;
    return {
      for (final e in w.entries)
        if ((e.value * f).abs() >= 0.3) e.key: e.value * f
    };
  }

  double weightFor(String subreddit) => state[subreddit.toLowerCase()] ?? 0;

  void bump(String subreddit, double delta) {
    if (subreddit.isEmpty || delta == 0) return;
    // Only learn when history/personalization tracking is enabled.
    if (!ref.read(settingsControllerProvider).trackHistory) return;
    final key = subreddit.toLowerCase();
    final current = _decayed(state);
    final next = ((current[key] ?? 0) + delta).clamp(-8.0, 40.0);
    _persist({...current, key: next});
  }

  /// Seeds affinity from the user's own history (cold start); never lowers.
  void seed(Map<String, double> deltas) {
    if (deltas.isEmpty) return;
    final current = _decayed(state);
    _persist({
      ...current,
      for (final e in deltas.entries)
        e.key: ((current[e.key] ?? 0) + e.value).clamp(-8.0, 40.0),
    });
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
    _persist({...state}..remove(key));
  }

  void clear() {
    state = {};
    ref.read(sharedPrefsProvider).remove(_key);
  }

  void _persist(Map<String, double> m) {
    _ts = DateTime.now().millisecondsSinceEpoch;
    state = m;
    ref.read(sharedPrefsProvider).setString(_key, jsonEncode({...m, '_ts': _ts}));
  }
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
  // Hebrew function words.
  'של', 'את', 'על', 'זה', 'גם', 'לא', 'מה', 'אני', 'יש', 'כל', 'עם', 'אם',
  'או', 'זו', 'הוא', 'היא', 'הם', 'כי', 'אבל', 'רק', 'עוד', 'כך', 'אז',
  'היום', 'אחרי', 'לפני', 'אחד', 'אחת',
};

final _nonWord = RegExp(r'[^\p{L}\p{N}\s]', unicode: true);
final _upper = RegExp(r'\p{Lu}', unicode: true);
final _letter = RegExp(r'\p{L}', unicode: true);
final _digit = RegExp(r'\d');
// Scripts where short words carry meaning: Hebrew, Arabic, CJK, Hangul.
final _shortScript = RegExp(
    r'[֐-׿؀-ۿ぀-ヿ㐀-鿿가-힯]');
final _hebrew = RegExp(r'[֐-׿]');

/// Tokenizes a post title into learnable keywords — any script, not just
/// ASCII (Hebrew titles used to yield nothing). Latin words need 4+ letters,
/// Hebrew/Arabic/CJK 2+; short acronyms and model names (F1, NBA, AI, PS5)
/// are kept. Hebrew's definite article / "and" prefix (ה, ו) is stripped so
/// "הבחירות" and "בחירות" learn as one word.
List<String> titleKeywords(String title) {
  final out = <String>[];
  for (final w in title.replaceAll(_nonWord, ' ').split(RegExp(r'\s+'))) {
    if (w.isEmpty) continue;
    var t = w.toLowerCase();
    if (_shortScript.hasMatch(t)) {
      if (_hebrew.hasMatch(t) &&
          t.length >= 4 &&
          (t.startsWith('ה') || t.startsWith('ו'))) {
        t = t.substring(1);
      }
      if (t.length >= 2 && !_stopwords.contains(t)) out.add(t);
    } else if (w.length <= 3 &&
        w.length >= 2 &&
        ((w == w.toUpperCase() && _upper.hasMatch(w)) ||
            (_letter.hasMatch(w) && _digit.hasMatch(w)))) {
      out.add(t); // acronym / model name
    } else if (t.length >= 4 &&
        !_stopwords.contains(t) &&
        !RegExp(r'^\d+$').hasMatch(t)) {
      out.add(t);
    }
    if (out.length == 14) break;
  }
  return out;
}

/// Learns which title keywords you engage with (upvote/save → +, downvote →
/// −). Powers within-subreddit taste ("F1 but not NBA") and keyword-matched
/// discovery. Local-only; decays like the interest store.
class KeywordStore extends Notifier<Map<String, double>> {
  static const _base = 'keyword_weights';
  static const _cap = 400;
  static const _decayPerDay = 0.97;
  late String _key;
  int? _ts;
  // When each word was last reinforced (days since epoch), so a full store
  // evicts what's weak *and* stale — not the word that just arrived.
  Map<String, int> _lastUsed = {};

  static int _today() =>
      DateTime.now().millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;

  @override
  Map<String, double> build() {
    _key = userScopedPrefsKey(ref, _base);
    final raw = ref.read(sharedPrefsProvider).getString(_key);
    if (raw == null) return {};
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      _ts = (m['_ts'] as num?)?.toInt();
      _lastUsed = {
        for (final e in ((m['_lu'] as Map?) ?? const {}).entries)
          '${e.key}': (e.value as num).toInt()
      };
      return _decayed({
        for (final e in m.entries)
          if (!e.key.startsWith('_')) e.key: (e.value as num).toDouble()
      });
    } catch (_) {
      return {};
    }
  }

  Map<String, double> _decayed(Map<String, double> w) {
    final f = decayFactor(_ts, _decayPerDay);
    if (f > 0.999) return w;
    return {
      for (final e in w.entries)
        if ((e.value * f).abs() >= 0.2) e.key: e.value * f
    };
  }

  /// Learns from a post title. [delta] applies per keyword (+1 up, −1 down).
  void bumpTitle(String title, double delta) {
    if (delta == 0) return;
    if (!ref.read(settingsControllerProvider).trackHistory) return;
    final words = titleKeywords(title);
    if (words.isEmpty) return;
    final next = _decayed(state);
    final today = _today();
    for (final w in words) {
      next[w] = ((next[w] ?? 0) + delta).clamp(-10.0, 10.0);
      _lastUsed[w] = today;
    }
    _evict(next, keep: words.toSet());
    _persist(next);
  }

  /// Seeds weights for a batch of titles (cold start).
  void seedTitles(Iterable<String> titles, double delta) {
    final next = _decayed(state);
    final today = _today();
    for (final t in titles) {
      for (final w in titleKeywords(t)) {
        next[w] = ((next[w] ?? 0) + delta).clamp(-10.0, 10.0);
        _lastUsed[w] = today;
      }
    }
    _evict(next);
    _persist(next);
  }

  // Bounded: drop the words with the least |weight| × recency.
  void _evict(Map<String, double> m, {Set<String> keep = const {}}) {
    if (m.length <= _cap) return;
    final today = _today();
    double value(MapEntry<String, double> e) =>
        e.value.abs() *
        math.exp(-(today - (_lastUsed[e.key] ?? today - 60)) / 30);
    final victims = (m.entries.where((e) => !keep.contains(e.key)).toList()
          ..sort((a, b) => value(a).compareTo(value(b))))
        .take(m.length - _cap)
        .map((e) => e.key)
        .toList();
    for (final k in victims) {
      m.remove(k);
      _lastUsed.remove(k);
    }
  }

  /// Total affinity of a title against the learned keywords, each word
  /// weighted by how distinctive it is ([idf], 1 = average).
  double scoreTitle(String title, {double Function(String word)? idf}) {
    if (state.isEmpty) return 0;
    var sum = 0.0;
    for (final w in titleKeywords(title)) {
      sum += (state[w] ?? 0) * (idf?.call(w) ?? 1);
    }
    return sum.clamp(-6.0, 8.0);
  }

  /// The strongest learned keyword present in [title] (for explainability),
  /// preferring distinctive words over generic ones like "help".
  String? topKeywordIn(String title, {double Function(String word)? idf}) {
    String? best;
    var bestW = 2.0; // only surface meaningful signals
    for (final w in titleKeywords(title)) {
      final v = (state[w] ?? 0) * (idf?.call(w) ?? 1);
      if (v > bestW) {
        bestW = v;
        best = w;
      }
    }
    return best;
  }

  /// Forgets one learned word (Manage For You → Topics → Reset).
  void reset(String word) {
    if (!state.containsKey(word)) return;
    _lastUsed.remove(word);
    _persist({...state}..remove(word));
  }

  void clear() {
    state = {};
    _lastUsed = {};
    ref.read(sharedPrefsProvider).remove(_key);
  }

  void _persist(Map<String, double> m) {
    _ts = DateTime.now().millisecondsSinceEpoch;
    state = m;
    _lastUsed.removeWhere((k, _) => !m.containsKey(k));
    ref.read(sharedPrefsProvider).setString(
        _key, jsonEncode({...m, '_ts': _ts, '_lu': _lastUsed}));
  }
}

final keywordStoreProvider =
    NotifierProvider<KeywordStore, Map<String, double>>(KeywordStore.new);

// ---------------------------------------------------------------------------
// Impressions — posts shown in For You but never opened get demoted.
// ---------------------------------------------------------------------------

/// Counts how many times each post was *seen* in the For You feed (≥60% on
/// screen for a second). The count fades — halving every 24h — so a post you
/// skimmed once isn't buried for good, and is counted at most once per app
/// session. Bounded (~600 ids), per-account, and only kept while history
/// tracking is on.
class ImpressionStore extends Notifier<Map<String, (double, int)>> {
  static const _base = 'fy_impressions';
  static const _cap = 600;
  late String _key;
  final _session = <String>{}; // ids already counted this app session
  final _pending = <String>{};
  bool _flushScheduled = false;

  @override
  Map<String, (double, int)> build() {
    _key = userScopedPrefsKey(ref, _base);
    final raw = ref.read(sharedPrefsProvider).getString(_key);
    if (raw == null) return {};
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      return {
        for (final e in (jsonDecode(raw) as Map<String, dynamic>).entries)
          e.key: e.value is List
              ? ((e.value[0] as num).toDouble(), (e.value[1] as num).toInt())
              : ((e.value as num).toDouble(), now), // legacy: plain count
      };
    } catch (_) {
      return {};
    }
  }

  /// How many times [postId] has been seen, faded (halves every 24h).
  double count(String postId) {
    final v = state[postId];
    if (v == null) return 0;
    return v.$1 * decayFactor(v.$2, 0.5);
  }

  /// Records one impression (cheap: batched, once per session per post).
  void record(String postId) {
    if (postId.isEmpty || !_session.add(postId)) return;
    if (!ref.read(settingsControllerProvider).trackHistory) return;
    _pending.add(postId);
    if (_flushScheduled) return;
    _flushScheduled = true;
    Future<void>.delayed(const Duration(seconds: 2), _flush);
  }

  void _flush() {
    _flushScheduled = false;
    if (_pending.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final next = {...state};
    for (final id in _pending) {
      next.remove(id); // re-insert last: insertion order = recency
      next[id] = (count(id) + 1, now);
    }
    _pending.clear();
    while (next.length > _cap) {
      next.remove(next.keys.first);
    }
    state = next;
    ref.read(sharedPrefsProvider).setString(_key,
        jsonEncode({for (final e in next.entries) e.key: [e.value.$1, e.value.$2]}));
  }

  void clear() {
    state = {};
    ref.read(sharedPrefsProvider).remove(_key);
  }
}

final impressionStoreProvider =
    NotifierProvider<ImpressionStore, Map<String, (double, int)>>(
        ImpressionStore.new);
