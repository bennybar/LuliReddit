import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/settings/settings_controller.dart';

/// Persists in-progress composer text so a long reply/post/message survives
/// navigating away, backgrounding, or a crash. Keyed by the compose target
/// (e.g. the parent fullname). Cleared on a successful submit. Local only.
class Drafts {
  Drafts(this._prefs);
  final SharedPreferences _prefs;

  String _k(String key) => 'draft_$key';

  String? get(String key) => _prefs.getString(_k(key));

  Future<void> save(String key, String value) => value.trim().isEmpty
      ? clear(key)
      : _prefs.setString(_k(key), value);

  Future<void> clear(String key) => _prefs.remove(_k(key));
}

final draftsProvider =
    Provider<Drafts>((ref) => Drafts(ref.read(sharedPrefsProvider)));
