import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/media_links.dart';
import '../../core/redgifs.dart';
import '../../models/post.dart';
import 'media_viewers.dart';
import 'save_media.dart';

/// Shared files are kept this long (the receiving app reads them after the
/// share sheet closes), then deleted.
const _keep = Duration(minutes: 30);

/// Whether "Share as media" applies: images, GIFs, galleries and videos Ilay
/// can download (Reddit-hosted or RedGifs).
bool canShareAsMedia(Post p) => switch (p.type) {
      PostType.image || PostType.gif => true,
      PostType.gallery => p.gallery.isNotEmpty,
      PostType.video => !isExternalVideo(p) &&
          (p.fallbackVideoUrl != null || redgifsId(p.url) != null),
      _ => false,
    };

/// "Share as media": downloads the post's image(s) or video and hands the
/// files themselves to the share sheet, rather than a link. They live in the
/// app's temporary folder only until shared: deleted [_keep] later (or at the
/// next share, if the app was closed meanwhile).
Future<void> shareAsMedia(BuildContext context, Post post) async {
  final messenger = ScaffoldMessenger.of(context);
  void say(String msg) =>
      messenger.showSnackBar(SnackBar(content: Text(msg)));
  // Anchors the iPad popover.
  Rect? origin;
  final box = context.findRenderObject();
  if (box is RenderBox && box.hasSize) {
    origin = box.localToGlobal(Offset.zero) & box.size;
  }
  Directory? dir;
  try {
    final files = await runWithProgress(context, 'Downloading',
        (cancel, onProgress) async {
      final root =
          Directory('${(await getTemporaryDirectory()).path}/share_media');
      // Anything left over from shares older than _keep.
      if (await root.exists()) {
        final now = DateTime.now();
        await for (final f in root.list()) {
          if (now.difference((await f.stat()).modified) > _keep) {
            await f.delete(recursive: true);
          }
        }
      }
      final d = dir = await Directory(
              '${root.path}/${DateTime.now().millisecondsSinceEpoch}')
          .create(recursive: true);
      final files = await _download(post, d.path, cancel, onProgress);
      if (files.isEmpty) throw StateError('No media');
      return files;
    });
    await Share.shareXFiles([
      for (final f in files)
        XFile(f, mimeType: mimeFor(f.split('.').last, f.endsWith('.mp4'))),
    ], sharePositionOrigin: origin);
    final d = dir!;
    Timer(_keep, () => d.delete(recursive: true).ignore());
  } on DioException catch (e) {
    dir?.delete(recursive: true).ignore();
    say(CancelToken.isCancel(e)
        ? 'Share cancelled'
        : "Couldn't download the media to share");
  } catch (_) {
    dir?.delete(recursive: true).ignore();
    say("Couldn't download the media to share");
  }
}

/// Downloads [post]'s media into [dir]: one file, or one per gallery image.
Future<List<String>> _download(Post post, String dir, CancelToken cancel,
    void Function(int, int) onProgress) async {
  String target(String url, String fallbackExt, [int i = 0]) {
    final name = url.split('?').first.split('/').last;
    final dot = name.lastIndexOf('.');
    var ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
    if (ext.length < 3 || ext.length > 4) ext = fallbackExt;
    return '$dir/ilay_${post.id}${i > 0 ? '_$i' : ''}.$ext';
  }

  Future<String> fetch(String url, String path) async {
    await downloadTo(url, path, cancel: cancel, onProgress: onProgress);
    return path;
  }

  Future<String> image(String url, [int i = 0]) =>
      fetch(url, target(url, 'jpg', i));

  switch (post.type) {
    case PostType.image:
      final u = Uri.tryParse(post.url);
      return [
        await image(u != null && isImageUrl(u)
            ? post.url
            : post.previewUrl ?? post.url)
      ];
    // Reddit's mp4 version of a GIF is a fraction of the size; apps play it
    // like a GIF.
    case PostType.gif:
      final mp4 = post.gifMp4Url;
      return [
        mp4 != null
            ? await fetch(mp4, target(mp4, 'mp4'))
            : await image(post.url)
      ];
    case PostType.gallery:
      return [
        for (var i = 0; i < post.gallery.length; i++)
          await image(post.gallery[i].url, i),
      ];
    case PostType.video:
      final redgifs =
          post.fallbackVideoUrl == null && redgifsId(post.url) != null
              ? await resolveRedgifs(post.url)
              : null;
      final video = redgifs ?? post.fallbackVideoUrl;
      if (video == null) return const [];
      final out = '$dir/ilay_${post.id}.mp4';
      if (redgifs != null) return [await fetch(video, out)];
      await downloadRedditVideo(video, out,
          cancel: cancel, onProgress: onProgress);
      return [out];
    default:
      return const [];
  }
}
