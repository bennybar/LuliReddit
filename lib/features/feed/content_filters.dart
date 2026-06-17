import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/post.dart';
import '../history/interest_store.dart' show userScopedPrefsKey;
import '../settings/settings_controller.dart';

/// User content filters: hide posts whose title contains a keyword, whose link
/// domain matches, or whose flair matches. Local-only, per-account — applied
/// across every feed.
class ContentFilters {
  const ContentFilters({
    this.keywords = const [],
    this.domains = const [],
    this.flairs = const [],
  });

  final List<String> keywords;
  final List<String> domains;
  final List<String> flairs;

  bool get isEmpty => keywords.isEmpty && domains.isEmpty && flairs.isEmpty;

  bool hides(Post p) {
    final title = p.title.toLowerCase();
    for (final k in keywords) {
      if (k.isNotEmpty && title.contains(k)) return true;
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
          keywords: g('keywords'), domains: g('domains'), flairs: g('flairs'));
    } catch (_) {
      return const ContentFilters();
    }
  }

  void _persist() => ref.read(sharedPrefsProvider).setString(
        _key,
        jsonEncode({
          'keywords': state.keywords,
          'domains': state.domains,
          'flairs': state.flairs,
        }),
      );

  void add(String type, String value) {
    final v = value.trim().toLowerCase();
    if (v.isEmpty) return;
    final k = [...state.keywords], d = [...state.domains], f = [...state.flairs];
    final target = type == 'keyword' ? k : (type == 'domain' ? d : f);
    if (!target.contains(v)) target.add(v);
    state = ContentFilters(keywords: k, domains: d, flairs: f);
    _persist();
  }

  void remove(String type, String value) {
    final k = [...state.keywords], d = [...state.domains], f = [...state.flairs];
    (type == 'keyword' ? k : (type == 'domain' ? d : f)).remove(value);
    state = ContentFilters(keywords: k, domains: d, flairs: f);
    _persist();
  }
}

final contentFiltersProvider =
    NotifierProvider<ContentFiltersController, ContentFilters>(
        ContentFiltersController.new);
