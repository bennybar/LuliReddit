import '../../models/subreddit.dart';
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

/// A subreddit you opened, with what it takes to list it again without asking
/// Reddit.
class RecentSubreddit {
  const RecentSubreddit({
    required this.name,
    required this.namePrefixed,
    this.iconUrl,
    this.subscribers = 0,
    this.visitedAt = 0,
  });

  final String name;
  final String namePrefixed;
  final String? iconUrl;
  final int subscribers;
  final int visitedAt; // millis since epoch

  Subreddit asSubreddit() => Subreddit(
      name: name,
      namePrefixed: namePrefixed,
      title: '',
      description: '',
      subscribers: subscribers,
      iconUrl: iconUrl);

  Map<String, dynamic> toJson() => {
        'name': name,
        'prefixed': namePrefixed,
        'icon': iconUrl,
        'members': subscribers,
        'ts': visitedAt,
      };

  factory RecentSubreddit.fromJson(Map<String, dynamic> j) => RecentSubreddit(
        name: j['name'] as String? ?? '',
        namePrefixed: j['prefixed'] as String? ?? '',
        iconUrl: j['icon'] as String?,
        subscribers: (j['members'] as num?)?.toInt() ?? 0,
        visitedAt: (j['ts'] as num?)?.toInt() ?? 0,
      );
}

/// The subreddits you opened last, newest first, per account and on-device
/// only. Whether you're subscribed doesn't matter (#63).
class RecentSubredditsController extends Notifier<List<RecentSubreddit>> {
  static const _base = 'recent_subreddits';
  static const _cap = 5;
  late String _key;

  @override
  List<RecentSubreddit> build() {
    _key = userScopedPrefsKey(ref, _base); // per-account
    final raw = ref.read(sharedPrefsProvider).getStringList(_key) ?? const [];
    return [
      for (final s in raw)
        RecentSubreddit.fromJson(jsonDecode(s) as Map<String, dynamic>),
    ];
  }

  /// [list] with [entry] first, once, whatever case its name came in.
  static List<RecentSubreddit> visited(
      List<RecentSubreddit> list, RecentSubreddit entry) {
    final name = entry.name.toLowerCase();
    return [
      entry,
      ...list.where((e) => e.name.toLowerCase() != name),
    ].take(_cap).toList();
  }

  void visit(Subreddit s) => _publish(visited(
      state,
      RecentSubreddit(
          name: s.name,
          namePrefixed: s.namePrefixed,
          iconUrl: s.iconUrl,
          subscribers: s.subscribers,
          visitedAt: DateTime.now().millisecondsSinceEpoch)));

  /// Removes entries older than [age], with History's own clear options.
  void clearOlderThan(Duration age) {
    final cutoff =
        DateTime.now().millisecondsSinceEpoch - age.inMilliseconds;
    _publish(state.where((e) => e.visitedAt >= cutoff).toList());
  }

  void clear() => _publish(const []);

  void _publish(List<RecentSubreddit> list) {
    state = list;
    ref
        .read(sharedPrefsProvider)
        .setStringList(_key, [for (final e in list) jsonEncode(e.toJson())]);
  }
}

final recentSubredditsProvider =
    NotifierProvider<RecentSubredditsController, List<RecentSubreddit>>(
        RecentSubredditsController.new);

/// Viewed post ids, for O(1) "seen?" checks (feeds dim read posts).
final historyIdsProvider = Provider<Set<String>>((ref) {
  return {for (final e in ref.watch(historyControllerProvider)) e.id};
});

/// Whether a post id has been viewed (for dimming in feeds).
final historyContainsProvider = Provider.family<bool, String>((ref, id) {
  return ref.watch(historyIdsProvider).contains(id);
});
