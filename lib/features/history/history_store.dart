import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/post.dart';
import '../settings/settings_controller.dart';

/// A locally-stored record of a viewed post. History is **on-device only** —
/// Reddit does not sync "viewed" state to third-party clients.
class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.subreddit,
    required this.title,
    required this.permalink,
  });

  final String id;
  final String subreddit;
  final String title;
  final String permalink;

  Map<String, dynamic> toJson() =>
      {'id': id, 'sub': subreddit, 'title': title, 'permalink': permalink};

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
        id: j['id'] as String? ?? '',
        subreddit: j['sub'] as String? ?? '',
        title: j['title'] as String? ?? '',
        permalink: j['permalink'] as String? ?? '',
      );
}

class HistoryController extends Notifier<List<HistoryEntry>> {
  static const _key = 'history';
  static const _cap = 500;

  @override
  List<HistoryEntry> build() {
    final raw = ref.read(sharedPrefsProvider).getStringList(_key) ?? const [];
    return [
      for (final s in raw)
        HistoryEntry.fromJson(jsonDecode(s) as Map<String, dynamic>),
    ];
  }

  void markViewed(Post p) {
    final entry = HistoryEntry(
        id: p.id, subreddit: p.subreddit, title: p.title, permalink: p.permalink);
    final list = [entry, ...state.where((e) => e.id != p.id)];
    if (list.length > _cap) list.removeRange(_cap, list.length);
    state = list;
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
