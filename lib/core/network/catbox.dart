import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Uploads bytes to catbox.moe — a free, anonymous file host (no account / API
/// key) that accepts both images and video. Returns the public direct URL.
///
/// Used for media that Reddit can't host natively: videos in comment replies and
/// any attachment in a private message (Reddit's comment/message APIs are
/// markdown-text only). The file is reachable by anyone with the (unguessable)
/// URL — surface that to the user before uploading.
Future<String> uploadToCatbox({
  required Uint8List bytes,
  required String filename,
}) async {
  final form = FormData();
  form.fields.add(const MapEntry('reqtype', 'fileupload'));
  form.files.add(
    MapEntry('fileToUpload', MultipartFile.fromBytes(bytes, filename: filename)),
  );
  final dio = Dio();
  final res = await dio.post(
    'https://catbox.moe/user/api.php',
    data: form,
    options: Options(responseType: ResponseType.plain),
  );
  final url = (res.data is String ? res.data as String : '${res.data}').trim();
  if (!url.startsWith('http')) {
    throw Exception('Upload failed: ${url.isEmpty ? 'empty response' : url}');
  }
  return url;
}
