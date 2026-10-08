import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/settings_controller.dart';

/// A folder the user picked to save media into (Android, via the Storage
/// Access Framework). [uri] is the persisted tree URI, [name] its display
/// path such as "Pictures/Reddit".
class MediaFolder {
  const MediaFolder(this.uri, this.name);
  final String uri;
  final String name;
}

const _channel = MethodChannel('ilay/media_folder');

/// Where saved media goes: a picked folder, or null for the gallery's
/// "Ilay" album.
class MediaFolderController extends Notifier<MediaFolder?> {
  static const _uriKey = 'mediaFolderUri', _nameKey = 'mediaFolderName';

  @override
  MediaFolder? build() {
    if (!Platform.isAndroid) return null;
    final p = ref.read(sharedPrefsProvider);
    final uri = p.getString(_uriKey);
    return uri == null ? null : MediaFolder(uri, p.getString(_nameKey) ?? '');
  }

  /// Opens the system folder picker; keeps the current choice on cancel.
  Future<void> pick() async {
    final res = await _channel.invokeMapMethod<String, String>('pick');
    if (res == null) return;
    final p = ref.read(sharedPrefsProvider);
    await p.setString(_uriKey, res['uri']!);
    await p.setString(_nameKey, res['name']!);
    state = MediaFolder(res['uri']!, res['name']!);
  }

  /// Back to saving into the gallery.
  Future<void> useGallery() async {
    final p = ref.read(sharedPrefsProvider);
    await p.remove(_uriKey);
    await p.remove(_nameKey);
    state = null;
  }
}

final mediaFolderProvider =
    NotifierProvider<MediaFolderController, MediaFolder?>(
        MediaFolderController.new);

/// Copies the downloaded file at [path] into [folder] as [name]. False when
/// the folder is no longer accessible (removed, or a grant lost on restore).
Future<bool> saveToMediaFolder(
    MediaFolder folder, String path, String name, String mime) async {
  try {
    return await _channel.invokeMethod<bool>('save', {
          'tree': folder.uri,
          'path': path,
          'name': name,
          'mime': mime,
        }) ??
        false;
  } on PlatformException {
    return false;
  }
}
