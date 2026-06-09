import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/settings_controller.dart';

/// On-device interest model: a per-subreddit affinity score that learns from
/// the user's own actions (upvote / downvote / save / open). Entirely local —
/// it never leaves the device and powers the "For You (Beta)" feed. This is the
/// transparent stand-in for Reddit's server-side ML, which third-party clients
/// cannot access.
class InterestStore extends Notifier<Map<String, double>> {
  static const _key = 'interest_weights';

  @override
  Map<String, double> build() {
    final raw = ref.read(sharedPrefsProvider).getString(_key);
    if (raw == null) return {};
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return {for (final e in m.entries) e.key: (e.value as num).toDouble()};
    } catch (_) {
      return {};
    }
  }

  double weightFor(String subreddit) => state[subreddit.toLowerCase()] ?? 0;

  void bump(String subreddit, double delta) {
    if (subreddit.isEmpty) return;
    // Only learn when history/personalization tracking is enabled.
    if (!ref.read(settingsControllerProvider).trackHistory) return;
    final key = subreddit.toLowerCase();
    final next = ((state[key] ?? 0) + delta).clamp(-8.0, 40.0);
    state = {...state, key: next};
    _persist();
  }

  /// Top affinity subreddits above [min], strongest first.
  List<String> top(int n, {double min = 1.0}) {
    final entries = state.entries.where((e) => e.value >= min).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in entries.take(n)) e.key];
  }

  void clear() {
    state = {};
    ref.read(sharedPrefsProvider).remove(_key);
  }

  void _persist() =>
      ref.read(sharedPrefsProvider).setString(_key, jsonEncode(state));
}

final interestStoreProvider =
    NotifierProvider<InterestStore, Map<String, double>>(InterestStore.new);

/// Subreddits the user muted from the "For You" feed (local only).
class MutedSubsController extends Notifier<Set<String>> {
  static const _key = 'muted_subs';

  @override
  Set<String> build() =>
      (ref.read(sharedPrefsProvider).getStringList(_key) ?? const []).toSet();

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
