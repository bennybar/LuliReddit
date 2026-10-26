import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../history/interest_store.dart' show userScopedPrefsKey;

/// One AI thread summary, kept with enough of its post to list it and open
/// it again.
class SavedSummary {
  const SavedSummary({
    required this.postId,
    required this.subreddit,
    required this.title,
    required this.permalink,
    required this.style,
    required this.model,
    required this.text,
    required this.createdAt,
  });

  final String postId;
  final String subreddit;
  final String title;
  final String permalink;
  final String style; // the style's label
  final String model;
  final String text;
  final int createdAt; // millis since epoch

  // Same field names as the Android app's file.
  Map<String, dynamic> toJson() => {
        'postId': postId,
        'subreddit': subreddit,
        'title': title,
        'permalink': permalink,
        'style': style,
        'model': model,
        'text': text,
        'createdAt': createdAt,
      };

  static SavedSummary fromJson(Map<String, dynamic> m) => SavedSummary(
        postId: m['postId'] as String? ?? '',
        subreddit: m['subreddit'] as String? ?? '',
        title: m['title'] as String? ?? '',
        permalink: m['permalink'] as String? ?? '',
        style: m['style'] as String? ?? '',
        model: m['model'] as String? ?? '',
        text: m['text'] as String? ?? '',
        createdAt: (m['createdAt'] as num?)?.toInt() ?? 0,
      );
}

/// The posts you've summarized (newest first), per account, on this device
/// only — the Summaries screen. A post summarized again replaces its older
/// entry. Kept to the last [_max].
class SummaryStore extends Notifier<List<SavedSummary>> {
  static const _max = 200;
  late String _name;
  // The account's file hasn't loaded yet: summaries made meanwhile wait
  // here, so they're merged into it instead of overwriting it.
  bool _loaded = false;
  final _early = <SavedSummary>[];
  // One write at a time, in order: parallel writes could land out of order.
  Future<void> _io = Future.value();

  @override
  List<SavedSummary> build() {
    _name = userScopedPrefsKey(ref, 'summaries');
    _loaded = false;
    _early.clear();
    _load(_name);
    return const [];
  }

  static Future<File> _file(String name) async =>
      File('${(await getApplicationSupportDirectory()).path}/$name.json');

  Future<void> _load(String name) async {
    var list = <SavedSummary>[];
    try {
      final f = await _file(name);
      if (f.existsSync()) {
        list = [
          for (final m in jsonDecode(await f.readAsString()) as List)
            SavedSummary.fromJson((m as Map).cast<String, dynamic>())
        ];
      }
    } catch (_) {}
    if (name != _name) return; // the account changed meanwhile
    _loaded = true;
    for (final s in _early) {
      list = _with(list, s);
    }
    final pending = _early.isNotEmpty;
    _early.clear();
    state = list;
    if (pending) _save();
  }

  static List<SavedSummary> _with(List<SavedSummary> list, SavedSummary s) =>
      [s, ...list.where((x) => x.postId != s.postId)].take(_max).toList();

  void add(SavedSummary s) {
    state = _with(state, s);
    if (!_loaded) {
      _early.add(s);
      return;
    }
    _save();
  }

  void remove(String postId) => removeAll({postId});

  void removeAll(Set<String> postIds) {
    state = [
      for (final s in state)
        if (!postIds.contains(s.postId)) s
    ];
    _save();
  }

  void _save() {
    final name = _name;
    final list = state;
    _io = _io.then((_) async {
      try {
        // Write a temp file and swap it in, so a crash mid-write can't
        // truncate it.
        final f = await _file(name);
        final tmp = File('${f.path}.tmp');
        await tmp.writeAsString(
            jsonEncode([for (final s in list) s.toJson()]));
        await tmp.rename(f.path);
      } catch (_) {}
    });
  }
}

final summaryStoreProvider =
    NotifierProvider<SummaryStore, List<SavedSummary>>(SummaryStore.new);
