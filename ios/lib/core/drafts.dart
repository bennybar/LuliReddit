import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/auth/auth_controller.dart';
import '../features/settings/settings_controller.dart';

/// An unfinished reply / message / post: its composer [key] ("reply_t1_…",
/// "msgreply_t4_…", "compose_msg", "compose_post"), its [text] (JSON for the
/// message and post composers) and [info]: where it goes, for the Drafts list.
class Draft {
  const Draft(this.key, this.text, this.info, this.savedAt);
  final String key;
  final String text;
  final Map<String, dynamic>? info;
  final int savedAt;
}

/// Persists in-progress composer text so a long reply/post/message survives
/// navigating away, backgrounding or a crash. Keyed by the signed-in account
/// and the compose target (e.g. the parent fullname), so another account never
/// sees or sends it; a draft from before accounts were part of the key moves
/// to the first account that opens it. Cleared on a successful submit. Local
/// only.
///
/// Next to each draft, [save]'s `info` says where it goes (post title,
/// subreddit, recipient) so You → Drafts can list and reopen it.
class Drafts {
  Drafts(this._prefs, this._username, this._changed);
  final SharedPreferences _prefs;
  final String _username;
  final void Function() _changed;

  String get _suffix =>
      _username.isEmpty ? '' : '_${_username.toLowerCase()}';

  // Per account, moving a pre-account draft over on first use.
  String _scoped(String base) {
    final key = '$base$_suffix';
    if (key != base && !_prefs.containsKey(key) && _prefs.containsKey(base)) {
      final legacy = _prefs.getString(base);
      if (legacy != null) _prefs.setString(key, legacy);
      _prefs.remove(base);
    }
    return key;
  }

  String _k(String key) => _scoped('draft_$key');
  String _infoKey(String key) => _scoped('draftinfo_$key');

  String? get(String key) => _prefs.getString(_k(key));

  Future<void> save(String key, String value,
      {Map<String, dynamic>? info}) async {
    if (value.trim().isEmpty) return clear(key);
    await _prefs.setString(_k(key), value);
    final stamped = {...?info, 'at': DateTime.now().millisecondsSinceEpoch};
    await _prefs.setString(_infoKey(key), jsonEncode(stamped));
    _changed();
  }

  Future<void> clear(String key) {
    final done =
        Future.wait([_prefs.remove(_k(key)), _prefs.remove(_infoKey(key))]);
    // The prefs cache is already updated: a swiped-away row leaves the list
    // in the same frame.
    _changed();
    return done;
  }

  /// This account's drafts, newest first.
  List<Draft> list() {
    if (_username.isEmpty) return const [];
    final suffix = _suffix;
    final out = <Draft>[];
    for (final full in _prefs.getKeys()) {
      if (!full.startsWith('draft_') || !full.endsWith(suffix)) continue;
      final key = full.substring(6, full.length - suffix.length);
      if (key.isEmpty) continue;
      final text = _prefs.getString(full);
      if (text == null || text.trim().isEmpty) continue;
      Map<String, dynamic>? info;
      try {
        final raw = _prefs.getString('draftinfo_$key$suffix');
        if (raw != null) info = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {/* no info */}
      final at = (info?['at'] as num?)?.toInt() ?? 0;
      out.add(Draft(key, text, info, at));
    }
    out.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return out;
  }
}

/// Bumped on every save / clear, so the Drafts list and count refresh.
final draftChangesProvider = StateProvider<int>((ref) => 0);

final draftsProvider = Provider<Drafts>((ref) {
  final user = ref.watch(authControllerProvider
      .select((s) => s.valueOrNull?.username ?? ''));
  return Drafts(ref.read(sharedPrefsProvider), user,
      () => ref.read(draftChangesProvider.notifier).state++);
});

/// This account's drafts, newest first.
final draftListProvider = Provider<List<Draft>>((ref) {
  ref.watch(draftChangesProvider);
  return ref.watch(draftsProvider).list();
});
