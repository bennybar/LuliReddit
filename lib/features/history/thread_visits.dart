import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/settings_controller.dart';
import 'interest_store.dart' show userScopedPrefsKey;

/// When each thread was last opened (post id → millis since epoch), so
/// comments posted since can be highlighted on the next visit. Local-only,
/// per-account, bounded, and only recorded while history tracking is on.
class ThreadVisits extends Notifier<Map<String, int>> {
  static const _base = 'thread_visits';
  static const _cap = 300;
  late String _key;

  @override
  Map<String, int> build() {
    _key = userScopedPrefsKey(ref, _base);
    final raw = ref.read(sharedPrefsProvider).getString(_key);
    if (raw == null) return {};
    try {
      return {
        for (final e in (jsonDecode(raw) as Map<String, dynamic>).entries)
          e.key: (e.value as num).toInt()
      };
    } catch (_) {
      return {};
    }
  }

  /// The previous visit to [postId], or null on a first visit.
  DateTime? lastVisit(String postId) {
    final ms = state[postId];
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  void clear() {
    state = {};
    ref.read(sharedPrefsProvider).remove(_key);
  }

  void record(String postId) {
    if (!ref.read(settingsControllerProvider).trackHistory) return;
    final next = {...state}..remove(postId);
    next[postId] = DateTime.now().millisecondsSinceEpoch; // newest last
    while (next.length > _cap) {
      next.remove(next.keys.first);
    }
    state = next;
    ref.read(sharedPrefsProvider).setString(_key, jsonEncode(next));
  }
}

final threadVisitsProvider =
    NotifierProvider<ThreadVisits, Map<String, int>>(ThreadVisits.new);
