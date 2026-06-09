import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

/// Tiny on-disk JSON cache for GET responses, used as a fallback when the
/// network is unavailable (best-effort offline reading).
class ResponseCache {
  Directory? _dir;

  Future<Directory> _ensureDir() async {
    if (_dir != null) return _dir!;
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}/luli_cache');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return _dir = dir;
  }

  String _key(String key) => md5.convert(utf8.encode(key)).toString();

  Future<void> write(String key, Object? data) async {
    try {
      if (data == null) return;
      final dir = await _ensureDir();
      final f = File('${dir.path}/${_key(key)}.json');
      await f.writeAsString(jsonEncode(data));
    } catch (_) {/* caching is best-effort */}
  }

  Future<dynamic> read(String key) async {
    try {
      final dir = await _ensureDir();
      final f = File('${dir.path}/${_key(key)}.json');
      if (!f.existsSync()) return null;
      return jsonDecode(await f.readAsString());
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    try {
      final dir = await _ensureDir();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      _dir = null;
    } catch (_) {}
  }
}
