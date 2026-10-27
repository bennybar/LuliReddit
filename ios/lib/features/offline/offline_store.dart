import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/providers.dart';
import '../../models/post.dart';
import '../history/interest_store.dart' show userScopedPrefsKey;
import '../settings/settings_controller.dart';

/// A thread saved for reading later / offline.
class OfflineThread {
  const OfflineThread({
    required this.id,
    required this.subreddit,
    required this.title,
    required this.savedAt,
  });

  final String id;
  final String subreddit;
  final String title;
  final int savedAt; // millis since epoch

  Map<String, dynamic> toJson() =>
      {'id': id, 'sub': subreddit, 'title': title, 'at': savedAt};

  static OfflineThread fromJson(Map<String, dynamic> m) => OfflineThread(
        id: m['id'] as String,
        subreddit: m['sub'] as String,
        title: m['title'] as String,
        savedAt: (m['at'] as num).toInt(),
      );
}

/// Where saved threads live: app support storage, which (unlike the
/// temporary response cache) the system doesn't clear.
Future<File> _threadFile(String postId) async {
  final dir = Directory('${(await getApplicationSupportDirectory()).path}'
      '/offline_threads');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return File('${dir.path}/$postId.json');
}

/// The saved comments response for [postId], or null if it wasn't saved.
Future<List<dynamic>?> readOfflineThread(String postId) async {
  try {
    final f = await _threadFile(postId);
    if (!f.existsSync()) return null;
    return jsonDecode(await f.readAsString()) as List<dynamic>;
  } catch (_) {
    return null;
  }
}

/// "Read later": threads saved with their comments for offline reading.
/// The list is per account; the files are keyed by post id.
class OfflineController extends Notifier<List<OfflineThread>> {
  static const _base = 'offline_threads';
  late String _key;

  @override
  List<OfflineThread> build() {
    _key = userScopedPrefsKey(ref, _base);
    final raw = ref.read(sharedPrefsProvider).getString(_key);
    if (raw == null) return const [];
    try {
      return [
        for (final m in jsonDecode(raw) as List)
          OfflineThread.fromJson((m as Map).cast<String, dynamic>())
      ];
    } catch (_) {
      return const [];
    }
  }

  bool contains(String postId) => state.any((t) => t.id == postId);

  void _persist(List<OfflineThread> next) {
    state = next;
    ref.read(sharedPrefsProvider).setString(
        _key, jsonEncode([for (final t in next) t.toJson()]));
  }

  /// Downloads [post]'s thread (up to 500 comments) and its images.
  Future<void> save(BuildContext context, Post post) async {
    final raw = await ref.read(redditRepositoryProvider).getCommentsRaw(
        subreddit: post.subreddit, postId: post.id, limit: 500);
    await (await _threadFile(post.id)).writeAsString(jsonEncode(raw));
    // Images go into the regular image cache, so the post renders offline.
    final urls = <String>{
      if (post.previewUrl != null) post.previewUrl!,
      if (post.previewMedUrl != null) post.previewMedUrl!,
      for (final g in post.gallery) g.url,
    };
    if (context.mounted) {
      for (final u in urls) {
        precacheImage(CachedNetworkImageProvider(u), context,
            onError: (_, __) {});
      }
    }
    _persist([
      OfflineThread(
          id: post.id,
          subreddit: post.subreddit,
          title: post.title,
          savedAt: DateTime.now().millisecondsSinceEpoch),
      ...state.where((t) => t.id != post.id),
    ]);
  }

  Future<void> remove(String postId) async {
    _persist(state.where((t) => t.id != postId).toList());
    try {
      final f = await _threadFile(postId);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {/* best effort */}
  }
}

final offlineProvider =
    NotifierProvider<OfflineController, List<OfflineThread>>(
        OfflineController.new);
