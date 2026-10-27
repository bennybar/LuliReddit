import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../history/interest_store.dart' show userScopedPrefsKey;
import '../settings/settings_controller.dart';

/// A per-account set of ids that each expire [_ttl] (read each time, so a
/// setting can change it) after being added, persisted as "id:millis" strings
/// under [_baseKey]. Local only — nothing is sent to Reddit. Used for posts
/// you hid (Settings → Hide posts for), posts swiped away ("Dismiss", a day)
/// and subreddits hidden from the front page ("Hide r/… for 7 days").
class ExpiringIds extends Notifier<Set<String>> {
  ExpiringIds(this._baseKey, this._ttl);
  final String _baseKey;
  final Duration Function(Ref ref) _ttl;

  late String _key;
  final _since = <String, int>{};
  // Wakes up when the next entry expires, so it un-hides while the app stays
  // open.
  Timer? _expiry;

  @override
  Set<String> build() {
    _key = userScopedPrefsKey(ref, _baseKey); // per-account
    ref.onDispose(() => _expiry?.cancel());
    _since.clear();
    for (final row
        in ref.read(sharedPrefsProvider).getStringList(_key) ?? const []) {
      final i = row.lastIndexOf(':');
      final t = int.tryParse(row.substring(i + 1));
      if (i > 0 && t != null) _since[row.substring(0, i)] = t;
    }
    return _save(); // drops the expired ones
  }

  void add(String id) {
    _since[id] = DateTime.now().millisecondsSinceEpoch;
    state = _save();
  }

  void remove(String id) {
    if (_since.remove(id) != null) state = _save();
  }

  /// Re-applies the expiry (the time-to-live setting changed).
  void refresh() => state = _save();

  /// Drops the expired ids, persists the rest and returns them.
  Set<String> _save() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final ttl = _ttl(ref).inMilliseconds;
    _since.removeWhere((_, t) => now - t > ttl);
    ref.read(sharedPrefsProvider).setStringList(
        _key, [for (final e in _since.entries) '${e.key}:${e.value}']);
    _expiry?.cancel();
    if (_since.isNotEmpty) {
      final next = _since.values.reduce((a, b) => a < b ? a : b);
      final wait = (next + ttl - now).clamp(0, ttl) + 1000;
      _expiry = Timer(Duration(milliseconds: wait), refresh);
    }
    return {..._since.keys};
  }
}

/// Posts you hid, kept out of every feed for Settings → Hide posts for
/// (hiding on Reddit only takes effect on the next fetch).
final hiddenPostsProvider = NotifierProvider<ExpiringIds, Set<String>>(
  () => ExpiringIds('hiddenPostIds', (ref) {
    return Duration(
        days: ref.read(settingsControllerProvider).hiddenPostDays);
  }),
);

/// Posts swiped away with "Dismiss" in Home / For You (kept a day).
final dismissedPostsProvider = NotifierProvider<ExpiringIds, Set<String>>(
  () => ExpiringIds('dismissedPosts', (_) => const Duration(days: 1)),
);

/// Subreddits (lowercase) hidden from the front page for 7 days.
final hiddenHomeSubsProvider = NotifierProvider<ExpiringIds, Set<String>>(
  () => ExpiringIds('hiddenHomeSubs', (_) => const Duration(days: 7)),
);
