import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pasteboard/pasteboard.dart';

/// A piece of media the user wants to attach to a reply or message, already read
/// into memory and ready to upload (to Reddit for inline comment images, or to
/// Catbox for videos / message attachments).
class MediaAttachment {
  MediaAttachment({
    required this.bytes,
    required this.filename,
    required this.mimeType,
    required this.isVideo,
  });

  final Uint8List bytes;
  final String filename;
  final String mimeType;
  final bool isVideo;

  String get sizeLabel {
    final kb = bytes.length / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(0)} KB';
    return '${(kb / 1024).toStringAsFixed(1)} MB';
  }
}

String _mimeForImage(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.png')) return 'image/png';
  if (n.endsWith('.gif')) return 'image/gif';
  if (n.endsWith('.webp')) return 'image/webp';
  return 'image/jpeg';
}

Future<MediaAttachment?> pickImageAttachment() async {
  final x = await ImagePicker().pickImage(source: ImageSource.gallery);
  if (x == null) return null;
  return MediaAttachment(
    bytes: await x.readAsBytes(),
    filename: x.name,
    mimeType: x.mimeType ?? _mimeForImage(x.name),
    isVideo: false,
  );
}

Future<MediaAttachment?> pickVideoAttachment() async {
  final x = await ImagePicker().pickVideo(source: ImageSource.gallery);
  if (x == null) return null;
  return MediaAttachment(
    bytes: await x.readAsBytes(),
    filename: x.name.isEmpty ? 'video.mp4' : x.name,
    mimeType: x.mimeType ?? 'video/mp4',
    isVideo: true,
  );
}

/// Reads an image off the system clipboard (a pasted screenshot/copy). Returns
/// null if the clipboard holds no image.
Future<MediaAttachment?> pasteImageAttachment() async {
  final bytes = await Pasteboard.image;
  if (bytes == null || bytes.isEmpty) return null;
  return MediaAttachment(
    bytes: bytes,
    filename: 'pasted.png',
    mimeType: 'image/png',
    isVideo: false,
  );
}

/// Takes images, GIFs and stickers sent by the keyboard (Gboard, Samsung
/// Keyboard…) as an attachment, like one picked from the gallery. For a
/// composer's TextField. Android only: Flutter's iOS text input doesn't take
/// images from the keyboard (iOS GIF keyboards copy them, and Paste image
/// takes them from there).
ContentInsertionConfiguration keyboardMedia(
        ValueChanged<MediaAttachment> onMedia, ValueChanged<String> onError) =>
    ContentInsertionConfiguration(onContentInserted: (c) {
      final data = c.data;
      if (data == null || data.isEmpty) {
        onError("Couldn't read the keyboard's image");
        return;
      }
      final ext = c.mimeType.split('/').last;
      onMedia(MediaAttachment(
        bytes: data,
        filename: 'keyboard.${ext == 'jpeg' ? 'jpg' : ext}',
        mimeType: c.mimeType,
        isVideo: false,
      ));
    });
