import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/post.dart';
import '../settings/settings_controller.dart';
import 'interest_store.dart' show userScopedPrefsKey;

/// A locally-stored record of a viewed post. History is **on-device only** —
/// Reddit does not sync "viewed" state to third-party clients.
class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.subreddit,
    required this.title,
    required this.permalink,
    this.viewedAt = 0,
  });

  final String id;
  final String subreddit;
  final String title;
  final String permalink;
  final int viewedAt; // millis since epoch; 0 = legacy/unknown

  Map<String, dynamic> toJson() => {
        'id': id,
        'sub': subreddit,
        'title': title,
        'permalink': permalink,
        'ts': viewedAt,
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
        id: j['id'] as String? ?? '',
        subreddit: j['sub'] as String? ?? '',
        title: j['title'] as String? ?? '',
        permalink: j['permalink'] as String? ?? '',
        viewedAt: (j['ts'] as num?)?.toInt() ?? 0,
      );
}

class HistoryController extends Notifier<List<HistoryEntry>> {
  static const _base = 'history';
  static const _cap = 500;
  late String _key;

  @override
  List<HistoryEntry> build() {
    _key = userScopedPrefsKey(ref, _base); // per-account
    final raw = ref.read(sharedPrefsProvider).getStringList(_key) ?? const [];
    return [
      for (final s in raw)
        HistoryEntry.fromJson(jsonDecode(s) as Map<String, dynamic>),
    ];
  }

  void markViewed(Post p) {
    final entry = HistoryEntry(
        id: p.id,
        subreddit: p.subreddit,
        title: p.title,
        permalink: p.permalink,
        viewedAt: DateTime.now().millisecondsSinceEpoch);
    final list = [entry, ...state.where((e) => e.id != p.id)];
    if (list.length > _cap) list.removeRange(_cap, list.length);
    state = list;
    _persist();
  }

  void removeViewed(String id) {
    state = state.where((e) => e.id != id).toList();
    _persist();
  }

  /// Removes entries older than [age]. Legacy entries (no timestamp) count as
  /// old and are removed too.
  void clearOlderThan(Duration age) {
    final cutoff =
        DateTime.now().millisecondsSinceEpoch - age.inMilliseconds;
    state = state.where((e) => e.viewedAt >= cutoff).toList();
    _persist();
  }

  void clear() {
    state = [];
    _persist();
  }

  void _persist() {
    ref
        .read(sharedPrefsProvider)
        .setStringList(_key, [for (final e in state) jsonEncode(e.toJson())]);
  }
}

final historyControllerProvider =
    NotifierProvider<HistoryController, List<HistoryEntry>>(
        HistoryController.new);

/// Whether a post id has been viewed (for dimming in feeds).
final historyContainsProvider = Provider.family<bool, String>((ref, id) {
  return ref.watch(historyControllerProvider).any((e) => e.id == id);
});
