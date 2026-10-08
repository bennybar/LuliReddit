import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/post.dart';
import '../history/interest_store.dart' show userScopedPrefsKey;
import '../settings/settings_controller.dart';

/// User content filters: hide posts whose title contains a keyword, whose link
/// domain matches, whose flair matches, or that come from a filtered
/// subreddit; optionally hide all NSFW posts and collapse AutoModerator
/// comments. Local-only, per-account — applied across every feed.
class ContentFilters {
  const ContentFilters({
    this.keywords = const [],
    this.domains = const [],
    this.flairs = const [],
    this.subreddits = const [],
    this.hideNsfw = false,
    this.collapseAutoMod = false,
  });

  final List<String> keywords;
  final List<String> domains;
  final List<String> flairs;
  final List<String> subreddits; // lowercase names, without "r/"
  final bool hideNsfw;
  final bool collapseAutoMod;

  bool get isEmpty =>
      keywords.isEmpty &&
      domains.isEmpty &&
      flairs.isEmpty &&
      subreddits.isEmpty &&
      !hideNsfw;

  /// Whole-word, any-script match: "cat" no longer hides "vacation".
  static bool _hasWord(String text, String word) => RegExp(
        '(?<![\\p{L}\\p{N}])${RegExp.escape(word)}(?![\\p{L}\\p{N}])',
        unicode: true,
        caseSensitive: false,
      ).hasMatch(text);

  /// Whether [p] is hidden. A filtered subreddit still shows on its own page
  /// ([viewingSubreddit]) — it's meant to keep it out of everything else.
  bool hides(Post p, {String? viewingSubreddit}) {
    if (hideNsfw && p.over18) return true;
    final sub = p.subreddit.toLowerCase();
    if (subreddits.contains(sub) && viewingSubreddit?.toLowerCase() != sub) {
      return true;
    }
    for (final k in keywords) {
      if (k.isNotEmpty && _hasWord(p.title, k)) return true;
    }
    final domain = p.domain.toLowerCase();
    for (final d in domains) {
      if (d.isNotEmpty && domain.contains(d)) return true;
    }
    final flair = (p.linkFlairText ?? '').toLowerCase();
    if (flair.isNotEmpty) {
      for (final f in flairs) {
        if (f.isNotEmpty && flair.contains(f)) return true;
      }
    }
    return false;
  }

  ContentFilters copyWith({
    List<String>? keywords,
    List<String>? domains,
    List<String>? flairs,
    List<String>? subreddits,
    bool? hideNsfw,
    bool? collapseAutoMod,
  }) =>
      ContentFilters(
        keywords: keywords ?? this.keywords,
        domains: domains ?? this.domains,
        flairs: flairs ?? this.flairs,
        subreddits: subreddits ?? this.subreddits,
        hideNsfw: hideNsfw ?? this.hideNsfw,
        collapseAutoMod: collapseAutoMod ?? this.collapseAutoMod,
      );
}

class ContentFiltersController extends Notifier<ContentFilters> {
  static const _base = 'content_filters';
  late String _key;

  @override
  ContentFilters build() {
    _key = userScopedPrefsKey(ref, _base);
    final raw = ref.read(sharedPrefsProvider).getString(_key);
    if (raw == null) return const ContentFilters();
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      List<String> g(String k) =>
          ((m[k] as List?) ?? const []).map((e) => e.toString()).toList();
      return ContentFilters(
        keywords: g('keywords'),
        domains: g('domains'),
        flairs: g('flairs'),
        subreddits: g('subreddits'),
        hideNsfw: m['hideNsfw'] == true,
        collapseAutoMod: m['collapseAutoMod'] == true,
      );
    } catch (_) {
      return const ContentFilters();
    }
  }

  void _set(ContentFilters next) {
    state = next;
    ref.read(sharedPrefsProvider).setString(
          _key,
          jsonEncode({
            'keywords': next.keywords,
            'domains': next.domains,
            'flairs': next.flairs,
            'subreddits': next.subreddits,
            'hideNsfw': next.hideNsfw,
            'collapseAutoMod': next.collapseAutoMod,
          }),
        );
  }

  List<String> _list(String type) => switch (type) {
        'keyword' => state.keywords,
        'domain' => state.domains,
        'subreddit' => state.subreddits,
        _ => state.flairs,
      };

  ContentFilters _withList(String type, List<String> v) => switch (type) {
        'keyword' => state.copyWith(keywords: v),
        'domain' => state.copyWith(domains: v),
        'subreddit' => state.copyWith(subreddits: v),
        _ => state.copyWith(flairs: v),
      };

  void add(String type, String value) {
    var v = value.trim().toLowerCase();
    if (type == 'subreddit') v = v.replaceFirst(RegExp(r'^/?r/'), '');
    if (v.isEmpty || _list(type).contains(v)) return;
    _set(_withList(type, [..._list(type), v]));
  }

  void remove(String type, String value) =>
      _set(_withList(type, [..._list(type)]..remove(value)));

  void setHideNsfw(bool v) => _set(state.copyWith(hideNsfw: v));
  void setCollapseAutoMod(bool v) => _set(state.copyWith(collapseAutoMod: v));
}

final contentFiltersProvider =
    NotifierProvider<ContentFiltersController, ContentFilters>(
        ContentFiltersController.new);
