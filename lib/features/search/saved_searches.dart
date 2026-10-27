import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../history/interest_store.dart' show userScopedPrefsKey;
import '../settings/settings_controller.dart';

/// A search kept to run again: its words, where (null = all of Reddit), sort
/// and time range.
class SavedSearch {
  const SavedSearch(this.query, this.subreddit, this.sort, this.time);
  final String query;
  final String? subreddit;
  final String sort;
  final String time;

  String get key => '${(subreddit ?? '').toLowerCase()}|'
      '${query.toLowerCase()}|$sort|$time';

  Map<String, dynamic> toJson() => {
        'q': query,
        if (subreddit != null) 'sr': subreddit,
        'sort': sort,
        't': time,
      };
}

/// Searches pinned from the search screen, per account (prefs
/// `saved_searches_<user>`). Newest first.
class SavedSearchesController extends Notifier<List<SavedSearch>> {
  late String _key;

  @override
  List<SavedSearch> build() {
    _key = userScopedPrefsKey(ref, 'saved_searches'); // per-account
    final raw = ref.read(sharedPrefsProvider).getString(_key);
    if (raw == null) return const [];
    try {
      return [
        for (final j in jsonDecode(raw) as List)
          if (j is Map && j['q'] is String)
            SavedSearch(
                j['q'] as String,
                j['sr'] as String?,
                j['sort'] as String? ?? 'relevance',
                j['t'] as String? ?? 'all'),
      ];
    } catch (_) {
      return const [];
    }
  }

  void add(SavedSearch s) =>
      _persist([s, ...state.where((e) => e.key != s.key)]);

  void remove(SavedSearch s) =>
      _persist(state.where((e) => e.key != s.key).toList());

  void _persist(List<SavedSearch> next) {
    state = next;
    ref.read(sharedPrefsProvider).setString(
        _key, jsonEncode([for (final s in next) s.toJson()]));
  }
}

final savedSearchesProvider =
    NotifierProvider<SavedSearchesController, List<SavedSearch>>(
        SavedSearchesController.new);
