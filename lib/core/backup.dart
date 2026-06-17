import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Exports / imports all local SharedPreferences — settings, the on-device
/// For You model, history, mutes, content filters, etc. API credentials and
/// tokens live in secure storage and are intentionally NOT included, so a
/// restore never moves your login between devices.
class Backup {
  static bool _skip(String key) => key.startsWith('draft_'); // transient

  static String export(SharedPreferences p) {
    final data = <String, dynamic>{};
    for (final k in p.getKeys()) {
      if (_skip(k)) continue;
      final v = p.get(k);
      if (v is bool) {
        data[k] = {'t': 'b', 'v': v};
      } else if (v is int) {
        data[k] = {'t': 'i', 'v': v};
      } else if (v is double) {
        data[k] = {'t': 'd', 'v': v};
      } else if (v is String) {
        data[k] = {'t': 's', 'v': v};
      } else if (v is List) {
        data[k] = {'t': 'l', 'v': v};
      }
    }
    return const JsonEncoder.withIndent('  ')
        .convert({'app': 'ilay_for_reddit', 'version': 1, 'data': data});
  }

  /// Writes [json] to a temp file for sharing; returns the file path.
  static Future<String> writeTempFile(String json) async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/ilay-backup.json');
    await f.writeAsString(json);
    return f.path;
  }

  /// Restores from a backup [json] string. Returns the number of keys written.
  static Future<int> import(SharedPreferences p, String json) async {
    final decoded = jsonDecode(json);
    if (decoded is! Map || decoded['data'] is! Map) {
      throw const FormatException('Not a valid Ilay backup file.');
    }
    final data = (decoded['data'] as Map);
    var n = 0;
    for (final entry in data.entries) {
      final m = entry.value;
      if (m is! Map) continue;
      final key = entry.key.toString();
      final v = m['v'];
      switch (m['t']) {
        case 'b':
          await p.setBool(key, v as bool);
          n++;
        case 'i':
          await p.setInt(key, (v as num).toInt());
          n++;
        case 'd':
          await p.setDouble(key, (v as num).toDouble());
          n++;
        case 's':
          await p.setString(key, v as String);
          n++;
        case 'l':
          await p.setStringList(
              key, (v as List).map((x) => x.toString()).toList());
          n++;
      }
    }
    return n;
  }
}
