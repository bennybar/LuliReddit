import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/widgets/loading.dart';
import 'media_folder.dart';

// Reddit's CDN (v.redd.it) closes the connection mid-stream for requests
// without a real User-Agent, so set one and allow a generous timeout.
final _downloadDio = Dio(BaseOptions(
  receiveTimeout: const Duration(seconds: 90),
  headers: const {
    'User-Agent':
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/124.0 Safari/537.36'
  },
));

const _muxChannel = MethodChannel('ilay/media_mux');

String mimeFor(String ext, bool isVideo) => switch (ext) {
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'jpg' || 'jpeg' => 'image/jpeg',
      'mp4' => 'video/mp4',
      _ => isVideo ? 'video/mp4' : 'image/jpeg',
    };

/// Downloads [url] into [path], reporting (received, total) every 128 KB
/// (total ≤ 0 when unknown). Cancelling [cancel] aborts a blocked connect or
/// read at once, not at the read timeout.
Future<void> downloadTo(String url, String path,
    {CancelToken? cancel, void Function(int, int)? onProgress}) {
  var lastEmit = 0;
  return _downloadDio.download(url, path,
      cancelToken: cancel,
      onReceiveProgress: onProgress == null
          ? null
          : (got, total) {
              if (got - lastEmit > 128 * 1024 || got == total) {
                lastEmit = got;
                onProgress(got, total);
              }
            });
}

/// Downloads a Reddit-hosted video (v.redd.it) into [out] *with its sound*: a
/// Reddit video's mp4 has none, the audio (if the video has any) is a separate
/// file named in its DASH playlist (DASH_AUDIO_128.mp4, CMAF_AUDIO_128.mp4…).
/// Both are downloaded next to [out] and put together, without re-encoding.
Future<void> downloadRedditVideo(String videoUrl, String out,
    {CancelToken? cancel, void Function(int, int)? onProgress}) async {
  final dir = File(out).parent.path;
  final stamp = DateTime.now().microsecondsSinceEpoch;
  final silent = '$dir/video_$stamp.mp4';
  final audio = '$dir/audio_$stamp.mp4';
  final mpd = '$dir/playlist_$stamp.mpd';
  try {
    await downloadTo(videoUrl, silent, cancel: cancel, onProgress: onProgress);
    final clean = videoUrl.split('?').first;
    final base = clean.substring(0, clean.lastIndexOf('/'));
    String? audioName;
    try {
      await downloadTo('$base/DASHPlaylist.mpd', mpd, cancel: cancel);
      audioName = audioTrack(await File(mpd).readAsString());
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
    } on FileSystemException {
      // no playlist: no sound
    }
    var gotAudio = false;
    if (audioName != null) {
      try {
        await downloadTo('$base/$audioName', audio,
            cancel: cancel, onProgress: onProgress);
        gotAudio = true;
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) rethrow;
      }
    }
    if (!(gotAudio && await _mux(silent, audio, out))) {
      await File(silent).copy(out); // no sound (a silent clip): the video as is
    }
  } finally {
    for (final f in [silent, audio, mpd]) {
      try {
        await File(f).delete();
      } on FileSystemException {
        // never written
      }
    }
  }
}

/// Puts [video]'s picture and [audio]'s sound into one mp4 (AVFoundation,
/// copying the samples as they are). False where it can't: then the caller
/// keeps the silent video.
Future<bool> _mux(String video, String audio, String out) async {
  try {
    await _muxChannel.invokeMethod<void>(
        'mux', {'video': video, 'audio': audio, 'out': out});
    return File(out).existsSync();
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}

/// The best audio file named in a DASH playlist, or null when the video has
/// no sound.
String? audioTrack(String mpd) {
  final sets = RegExp(r'<AdaptationSet\b[^>]*>.*?</AdaptationSet>',
          dotAll: true)
      .allMatches(mpd)
      .map((m) => m[0]!)
      .where((s) =>
          s.contains('contentType="audio"') || s.contains('mimeType="audio/'));
  final rep = RegExp(
      r'<Representation\b[^>]*?bandwidth="(\d+)"[^>]*>'
      r'.*?<BaseURL>([^<]+)</BaseURL>',
      dotAll: true);
  var best = -1;
  String? name;
  for (final set in sets) {
    for (final m in rep.allMatches(set)) {
      final bandwidth = int.parse(m[1]!);
      if (bandwidth > best) {
        best = bandwidth;
        name = m[2]!.trim();
      }
    }
  }
  return name;
}

/// Runs [work] behind a cancellable "[verb]… x / y MB" dialog, closed when
/// [work] ends however it ends. Cancel cancels the token [work] downloads
/// with, which ends it with a cancelled [DioException].
Future<T> runWithProgress<T>(
    BuildContext context,
    String verb,
    Future<T> Function(CancelToken cancel, void Function(int, int) onProgress)
        work) async {
  final cancel = CancelToken();
  final progress = ValueNotifier<(int, int)>((0, 0)); // (received, total)
  BuildContext? dialog;
  var finished = false;
  void close(BuildContext d) {
    final route = ModalRoute.of(d);
    if (route == null || !route.isActive) return;
    route.isCurrent
        ? Navigator.of(d).pop()
        : Navigator.of(d).removeRoute(route);
  }

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (ctx) {
      dialog = ctx;
      // Done before the dialog's first frame: close it right away.
      if (finished) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (ctx.mounted) close(ctx);
        });
      }
      return SavingDialog(
          progress: progress, verb: verb, onCancel: () => cancel.cancel());
    },
  );
  try {
    return await work(cancel, (got, total) => progress.value = (got, total));
  } finally {
    finished = true;
    final d = dialog;
    if (d != null && d.mounted) close(d);
  }
}

/// Downloads a media file to the folder picked in Settings, else the device
/// gallery/Photos' "Ilay" album, with a cancellable progress dialog showing
/// downloaded / total size. Reddit's own videos are saved with their sound.
Future<void> saveMediaToGallery(BuildContext context, String url,
    {required bool isVideo}) async {
  final folder = ProviderScope.containerOf(context).read(mediaFolderProvider);
  final messenger = ScaffoldMessenger.of(context);
  void say(String msg) =>
      messenger.showSnackBar(SnackBar(content: Text(msg)));
  final last = url.split('?').first.split('/').last;
  var ext = last.contains('.') ? last.split('.').last.toLowerCase() : '';
  if (ext.isEmpty || ext.length > 4) ext = isVideo ? 'mp4' : 'jpg';
  final ts = DateTime.now().millisecondsSinceEpoch;
  String? tmp;
  try {
    final msg = await runWithProgress(context, 'Saving',
        (cancel, onProgress) async {
      final dir = (await getTemporaryDirectory()).path;
      final path = tmp = '$dir/luli_$ts.$ext';
      if (isVideo && Uri.tryParse(url)?.host == 'v.redd.it') {
        await downloadRedditVideo(url, path,
            cancel: cancel, onProgress: onProgress);
      } else {
        await downloadTo(url, path, cancel: cancel, onProgress: onProgress);
      }
      if (folder != null &&
          await saveToMediaFolder(
              folder, path, 'ilay_$ts.$ext', mimeFor(ext, isVideo))) {
        return 'Saved to ${folder.name}';
      }
      if (isVideo) {
        await Gal.putVideo(path, album: 'Ilay');
      } else {
        await Gal.putImage(path, album: 'Ilay');
      }
      return folder == null
          ? 'Saved to your gallery'
          : "Couldn't open ${folder.name}, so saved to your gallery. "
              'Pick the folder again in Settings.';
    });
    say(msg);
  } on DioException catch (e) {
    say(CancelToken.isCancel(e) ? 'Download cancelled' : 'Could not save');
  } catch (e) {
    say('Could not save: ${'$e'.replaceFirst('Exception: ', '')}');
  } finally {
    final t = tmp;
    if (t != null) File(t).delete().ignore();
  }
}

/// The progress dialog of a save or a "Share as media" download: a wavy bar
/// (Material 3 Expressive) filling up when the size is known, travelling
/// otherwise.
class SavingDialog extends StatelessWidget {
  const SavingDialog(
      {super.key,
      required this.progress,
      required this.onCancel,
      this.verb = 'Saving'});
  final ValueNotifier<(int, int)> progress;
  final VoidCallback onCancel;
  final String verb;

  static String _mb(int bytes) => (bytes / 1048576).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        content: ValueListenableBuilder<(int, int)>(
          valueListenable: progress,
          builder: (_, v, __) {
            final received = v.$1, total = v.$2;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(total > 0
                    ? '$verb… ${_mb(received)} / ${_mb(total)} MB'
                    : '$verb…'),
                const SizedBox(height: 16),
                WavyProgress(
                  value: total > 0 ? (received / total).clamp(0.0, 1.0) : null,
                  label: verb,
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(onPressed: onCancel, child: const Text('Cancel')),
        ],
      ),
    );
  }
}
