import 'dart:io' show Platform;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:chewie/chewie.dart';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../core/share.dart';
import '../../models/post.dart';

/// A left-edge swipe-to-go-back strip (iOS-style), safe to overlay on viewers
/// without stealing PhotoView pan / gallery paging (only the left 24px).
class _EdgeBack extends StatelessWidget {
  const _EdgeBack();
  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      top: 0,
      bottom: 0,
      width: 26,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) > 80) Navigator.of(context).maybePop();
        },
      ),
    );
  }
}

/// A transparent, fade-in route so the viewer feels like an overlay above the
/// content rather than a separate page.
Route<T> _overlayRoute<T>(Widget page) => PageRouteBuilder<T>(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    );

void openImageViewer(BuildContext context, String url, {String? title}) {
  Navigator.of(context).push(_overlayRoute(_ImageViewer(url: url, title: title)));
}

void openGalleryViewer(BuildContext context, List<GalleryImage> images,
    {String? title, int initialIndex = 0}) {
  if (images.isEmpty) return;
  Navigator.of(context).push(_overlayRoute(
      _GalleryViewer(images: images, title: title, initialIndex: initialIndex)));
}

void openVideoViewer(BuildContext context, String url,
    {String? title, String? downloadUrl}) {
  Navigator.of(context).push(_overlayRoute(
      _VideoViewer(url: url, title: title, downloadUrl: downloadUrl)));
}

/// Normalizes common host quirks to a directly-playable video URL
/// (e.g. Imgur `.gifv` → `.mp4`).
String resolveVideoUrl(String url) {
  if (url.endsWith('.gifv')) return url.replaceAll('.gifv', '.mp4');
  return url;
}

/// Downloads a media file to the device gallery/Photos, with a cancellable
/// progress dialog showing downloaded / total size.
Future<void> saveMediaToGallery(BuildContext context, String url,
    {required bool isVideo}) async {
  final messenger = ScaffoldMessenger.of(context);
  final nav = Navigator.of(context, rootNavigator: true);
  final cancel = CancelToken();
  final progress = ValueNotifier<(int, int)>((0, 0)); // (received, total)
  showDialog(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => _SavingDialog(
        progress: progress,
        onCancel: () => cancel.cancel('cancelled')),
  );
  try {
    final dir = await getTemporaryDirectory();
    final clean = url.split('?').first;
    var ext = clean.contains('.') ? clean.split('.').last.toLowerCase() : '';
    if (ext.isEmpty || ext.length > 4) ext = isVideo ? 'mp4' : 'jpg';
    final ts = DateTime.now().millisecondsSinceEpoch;
    final path = '${dir.path}/luli_$ts.$ext';
    // Reddit's CDN (v.redd.it) closes the connection mid-stream for requests
    // without a real User-Agent, so set one and allow a generous timeout.
    await Dio().download(
      url,
      path,
      cancelToken: cancel,
      options: Options(
        headers: const {
          'User-Agent':
              'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
                  '(KHTML, like Gecko) Chrome/124.0 Safari/537.36'
        },
        receiveTimeout: const Duration(seconds: 90),
      ),
      onReceiveProgress: (got, total) => progress.value = (got, total),
    );
    if (isVideo) {
      await Gal.putVideo(path, album: 'Luli');
    } else {
      await Gal.putImage(path, album: 'Luli');
    }
    nav.pop();
    messenger.showSnackBar(
        const SnackBar(content: Text('Saved to your gallery')));
  } on DioException catch (e) {
    nav.pop();
    if (CancelToken.isCancel(e)) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Download cancelled')));
    } else {
      messenger.showSnackBar(const SnackBar(content: Text('Could not save')));
    }
  } catch (e) {
    nav.pop();
    messenger.showSnackBar(SnackBar(
        content: Text('Could not save: ${'$e'.replaceFirst('Exception: ', '')}')));
  }
}

class _SavingDialog extends StatelessWidget {
  const _SavingDialog({required this.progress, required this.onCancel});
  final ValueNotifier<(int, int)> progress;
  final VoidCallback onCancel;

  static String _mb(int bytes) => (bytes / 1048576).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: ValueListenableBuilder<(int, int)>(
        valueListenable: progress,
        builder: (_, v, __) {
          final received = v.$1, total = v.$2;
          final frac = total > 0 ? received / total : null;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(value: frac, strokeWidth: 3),
              ),
              const SizedBox(width: 18),
              Flexible(
                child: Text(total > 0
                    ? 'Saving… ${_mb(received)} / ${_mb(total)} MB'
                    : 'Saving…'),
              ),
            ],
          );
        },
      ),
      actions: [
        TextButton(onPressed: onCancel, child: const Text('Cancel')),
      ],
    );
  }
}

/// Floating translucent controls (close + download + share + open) over a scrim.
class _ViewerControls extends StatelessWidget {
  const _ViewerControls(
      {this.title,
      this.sourceUrl,
      this.center,
      this.downloadUrl,
      this.downloadIsVideo = false});
  final String? title;
  final String? sourceUrl;
  final String? center;
  final String? downloadUrl;
  final bool downloadIsVideo;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x99000000), Color(0x00000000)],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              _RoundBtn(
                icon: Platform.isIOS
                    ? CupertinoIcons.xmark
                    : Icons.close_rounded,
                onTap: () => Navigator.of(context).maybePop(),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  center ?? title ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600),
                ),
              ),
              if (downloadUrl != null) ...[
                _RoundBtn(
                  icon: Platform.isIOS
                      ? CupertinoIcons.cloud_download
                      : Icons.download_rounded,
                  onTap: () => saveMediaToGallery(context, downloadUrl!,
                      isVideo: downloadIsVideo),
                ),
                const SizedBox(width: 4),
              ],
              if (sourceUrl != null) ...[
                _RoundBtn(
                  icon: Platform.isIOS
                      ? CupertinoIcons.share
                      : Icons.ios_share,
                  onTap: () => shareUrl(context, sourceUrl!),
                ),
                const SizedBox(width: 4),
                _RoundBtn(
                  icon: Platform.isIOS
                      ? CupertinoIcons.arrow_up_right_square
                      : Icons.open_in_new_rounded,
                  onTap: () => launchUrl(Uri.parse(sourceUrl!),
                      mode: LaunchMode.externalApplication),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // A solid, always-legible scrim circle. (A BackdropFilter blur on a tiny
    // circle renders unreliably over media, so we keep this simple and crisp.)
    // Clean iOS/Stories style: a white glyph with a soft shadow over the top
    // scrim. Uses GestureDetector (not IconButton) because the media Stack has
    // no Material ancestor, which would make IconButton taps silently no-op.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: Icon(
            icon,
            color: Colors.white,
            size: 26,
            shadows: const [Shadow(color: Colors.black54, blurRadius: 6)],
          ),
        ),
      ),
    );
  }
}

/// Shared immersive behaviour + swipe-down-to-dismiss with background fade.
mixin _ImmersiveDismiss<T extends StatefulWidget> on State<T> {
  double drag = 0;
  bool zoomed = false;
  bool showControls = true;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  double get bgOpacity => (1 - (drag.abs() / 500)).clamp(0.0, 1.0);

  void onDragUpdate(DragUpdateDetails d) {
    if (zoomed) return;
    setState(() => drag += d.delta.dy);
  }

  void onDragEnd(DragEndDetails d) {
    if (zoomed) return;
    if (drag.abs() > 130 || (d.primaryVelocity ?? 0).abs() > 800) {
      Navigator.of(context).maybePop();
    } else {
      setState(() => drag = 0);
    }
  }
}

class _ImageViewer extends StatefulWidget {
  const _ImageViewer({required this.url, this.title});
  final String url;
  final String? title;

  @override
  State<_ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<_ImageViewer> with _ImmersiveDismiss {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(color: Colors.black.withValues(alpha: bgOpacity)),
          ),
          Transform.translate(
            offset: Offset(0, drag),
            child: GestureDetector(
              onVerticalDragUpdate: onDragUpdate,
              onVerticalDragEnd: onDragEnd,
              child: PhotoView(
                imageProvider: CachedNetworkImageProvider(widget.url),
                backgroundDecoration:
                    const BoxDecoration(color: Colors.transparent),
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 4,
                onTapUp: (_, __, ___) =>
                    setState(() => showControls = !showControls),
                scaleStateChangedCallback: (s) =>
                    setState(() => zoomed = s != PhotoViewScaleState.initial),
                loadingBuilder: (_, __) => const Center(
                    child: CircularProgressIndicator(color: Colors.white)),
              ),
            ),
          ),
          AnimatedOpacity(
            opacity: showControls && drag.abs() < 8 ? 1 : 0,
            duration: const Duration(milliseconds: 150),
            child: _ViewerControls(
                title: widget.title,
                sourceUrl: widget.url,
                downloadUrl: widget.url),
          ),
          const _EdgeBack(),
        ],
      ),
    );
  }
}

class _GalleryViewer extends StatefulWidget {
  const _GalleryViewer(
      {required this.images, this.title, this.initialIndex = 0});
  final List<GalleryImage> images;
  final String? title;
  final int initialIndex;

  @override
  State<_GalleryViewer> createState() => _GalleryViewerState();
}

class _GalleryViewerState extends State<_GalleryViewer> with _ImmersiveDismiss {
  late final _controller = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(color: Colors.black.withValues(alpha: bgOpacity)),
          ),
          Transform.translate(
            offset: Offset(0, drag),
            child: GestureDetector(
              onVerticalDragUpdate: onDragUpdate,
              onVerticalDragEnd: onDragEnd,
              child: PhotoViewGallery.builder(
                pageController: _controller,
                itemCount: widget.images.length,
                onPageChanged: (i) => setState(() => _index = i),
                scaleStateChangedCallback: (s) =>
                    setState(() => zoomed = s != PhotoViewScaleState.initial),
                builder: (_, i) => PhotoViewGalleryPageOptions(
                  imageProvider: CachedNetworkImageProvider(widget.images[i].url),
                  minScale: PhotoViewComputedScale.contained,
                  maxScale: PhotoViewComputedScale.covered * 4,
                  onTapUp: (_, __, ___) =>
                      setState(() => showControls = !showControls),
                ),
                backgroundDecoration:
                    const BoxDecoration(color: Colors.transparent),
                loadingBuilder: (_, __) => const Center(
                    child: CircularProgressIndicator(color: Colors.white)),
              ),
            ),
          ),
          AnimatedOpacity(
            opacity: showControls && drag.abs() < 8 ? 1 : 0,
            duration: const Duration(milliseconds: 150),
            child: _ViewerControls(
              title: widget.title,
              center: '${_index + 1} / ${widget.images.length}',
              sourceUrl: widget.images[_index].url,
              downloadUrl: widget.images[_index].url,
            ),
          ),
          const _EdgeBack(),
        ],
      ),
    );
  }
}

class _VideoViewer extends StatefulWidget {
  const _VideoViewer({required this.url, this.title, this.downloadUrl});
  final String url;
  final String? title;
  final String? downloadUrl; // direct mp4 for saving (HLS can't be saved)

  @override
  State<_VideoViewer> createState() => _VideoViewerState();
}

class _VideoViewerState extends State<_VideoViewer> {
  VideoPlayerController? _video;
  ChewieController? _chewie;
  String? _error;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    _init();
  }

  Future<void> _init() async {
    try {
      final v = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await v.initialize();
      if (!mounted) return;
      setState(() {
        _video = v;
        _chewie = ChewieController(
          videoPlayerController: v,
          autoPlay: true,
          looping: true,
          aspectRatio: v.value.aspectRatio,
        );
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _chewie?.dispose();
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: _error != null
                ? Text('Could not play video.\n$_error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70))
                : _chewie == null
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Chewie(controller: _chewie!),
          ),
          _ViewerControls(
            title: widget.title,
            sourceUrl: widget.url,
            downloadUrl: (widget.downloadUrl != null &&
                    !widget.downloadUrl!.contains('.m3u8'))
                ? widget.downloadUrl
                : null,
            downloadIsVideo: true,
          ),
          const _EdgeBack(),
        ],
      ),
    );
  }
}
