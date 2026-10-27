import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luli_for_reddit/features/media/save_media.dart';

/// Kotlin's DownloadCancelTest: Cancel in the progress dialog stops a
/// download blocked on a server that never answers (a local one, here).
void main() {
  test('cancel stops a download blocked on a silent server', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final held = <Socket>[];
    server.listen(held.add); // accepts, never answers
    final dir = await Directory.systemTemp.createTemp('ilay-dl');
    try {
      final cancel = CancelToken();
      final download = downloadTo(
          'http://127.0.0.1:${server.port}/x', '${dir.path}/x.bin',
          cancel: cancel);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final started = DateTime.now();
      cancel.cancel();
      Object? error;
      try {
        await download.timeout(const Duration(seconds: 2));
      } catch (e) {
        error = e;
      }
      expect(error, isA<DioException>());
      expect(CancelToken.isCancel(error as DioException), isTrue);
      expect(DateTime.now().difference(started).inMilliseconds,
          lessThan(2000));
    } finally {
      for (final s in held) {
        s.destroy();
      }
      await server.close();
      await dir.delete(recursive: true);
    }
  });
}
