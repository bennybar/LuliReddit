import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/providers.dart';
import '../../models/post.dart';
import '../auth/auth_controller.dart';
import '../history/history_store.dart';
import '../history/interest_store.dart';
import '../settings/settings_controller.dart';

/// Cold start: the first time For You runs for an account, seed its model
/// from the user's own Reddit activity (their upvoted and saved posts — data
/// Reddit already holds for them, nothing third-party) plus local history,
/// so day one already prefers what they actually like. Once per account,
/// and only while history tracking is on.
Future<void> seedForYouIfNeeded(Ref ref) async {
  if (!ref.read(settingsControllerProvider).trackHistory) return;
  final session = ref.read(authControllerProvider).valueOrNull;
  if (session == null || session.anonymous || session.username.isEmpty) {
    return;
  }
  final prefs = ref.read(sharedPrefsProvider);
  final key = userScopedPrefsKey(ref, 'fy_seeded');
  if (prefs.getBool(key) ?? false) return;
  await prefs.setBool(key, true); // don't retry every page on failure

  final repo = ref.read(redditRepositoryProvider);
  final user = session.username;
  final results = await Future.wait([
    repo
        .getUserPosts(user, where: 'upvoted', limit: 100)
        .then((l) => l.items)
        .catchError((_) => const <Post>[]),
    repo
        .getUserSaved(user, limit: 100)
        .then((l) => l.items.whereType<Post>().toList())
        .catchError((_) => const <Post>[]),
  ]);
  final upvoted = results[0], saved = results[1];

  final deltas = <String, double>{};
  void add(String sub, double d) {
    final k = sub.toLowerCase();
    deltas[k] = ((deltas[k] ?? 0) + d).clamp(0.0, 6.0);
  }

  for (final p in upvoted) {
    add(p.subreddit, 1);
  }
  for (final p in saved) {
    add(p.subreddit, 2);
  }
  for (final e in ref.read(historyControllerProvider)) {
    add(e.subreddit, 0.3);
  }
  ref.read(interestStoreProvider.notifier).seed(deltas);
  ref.read(keywordStoreProvider.notifier).seedTitles(
      [for (final p in [...upvoted, ...saved]) p.title], 0.3);
}

// ---------------------------------------------------------------------------
// Last ranked page, for an instant first paint
// ---------------------------------------------------------------------------

Future<File> _cacheFile(String user) async => File(
    '${(await getApplicationSupportDirectory()).path}/foryou_${user.toLowerCase()}.json');

/// Saves the first ranked page (raw post data + each post's reason).
Future<void> saveForYouPage(String user, List<Post> posts,
    Map<String, dynamic>? Function(String id) raw) async {
  try {
    final rows = [
      for (final p in posts.take(40))
        if (raw(p.id) != null) {'raw': raw(p.id), 'reason': p.feedReason},
    ];
    await (await _cacheFile(user)).writeAsString(jsonEncode(rows));
  } catch (_) {/* best effort */}
}

/// The saved page, minus posts opened since (they'd only be demoted now).
Future<List<Post>?> loadForYouPage(String user, Set<String> opened) async {
  try {
    final f = await _cacheFile(user);
    if (!f.existsSync()) return null;
    final rows = jsonDecode(await f.readAsString()) as List;
    final posts = [
      for (final r in rows)
        Post.fromData(((r as Map)['raw'] as Map).cast<String, dynamic>())
            .copyWith(feedReason: r['reason'] as String?),
    ].where((p) => !opened.contains(p.id)).toList();
    return posts.isEmpty ? null : posts;
  } catch (_) {
    return null;
  }
}
