import 'dart:async';
import 'dart:io' show Platform;

import 'package:cached_network_image/cached_network_image.dart';
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
    {String? title, String? downloadUrl, String? externalUrl}) {
  Navigator.of(context).push(_overlayRoute(_VideoViewer(
      url: url,
      title: title,
      downloadUrl: downloadUrl,
      externalUrl: externalUrl)));
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
      await Gal.putVideo(path, album: 'Ilay');
    } else {
      await Gal.putImage(path, album: 'Ilay');
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
  const _VideoViewer(
      {required this.url, this.title, this.downloadUrl, this.externalUrl});
  final String url;
  final String? title;
  final String? downloadUrl; // direct mp4 for saving (HLS can't be saved)
  final String? externalUrl; // original link, for "open in browser" fallback

  @override
  State<_VideoViewer> createState() => _VideoViewerState();
}

class _VideoViewerState extends State<_VideoViewer> {
  VideoPlayerController? _video;
  String? _error;
  bool _controls = true;
  Timer? _hideTimer;

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
      await v.setLooping(true);
      await v.play();
      setState(() => _video = v);
      _scheduleHide();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    // Only auto-hide while playing; keep controls up when paused.
    if (_video?.value.isPlaying ?? false) {
      _hideTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _controls = false);
      });
    }
  }

  // Tapping the video only toggles the overlay — it never changes play state.
  void _toggleControls() {
    setState(() => _controls = !_controls);
    if (_controls) _scheduleHide();
  }

  void _togglePlay() {
    final v = _video;
    if (v == null) return;
    setState(() => v.value.isPlaying ? v.pause() : v.play());
    _scheduleHide();
  }

  Future<void> _seekBy(int seconds) async {
    final v = _video;
    if (v == null) return;
    final target = v.value.position + Duration(seconds: seconds);
    final max = v.value.duration;
    await v.seekTo(target < Duration.zero
        ? Duration.zero
        : (target > max ? max : target));
    _scheduleHide();
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _hideTimer?.cancel();
    _video?.dispose();
    super.dispose();
  }

  Widget _errorView(BuildContext context) {
    final link = widget.externalUrl ?? widget.url;
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.videocam_off_rounded, color: Colors.white54, size: 48),
          const SizedBox(height: 14),
          const Text(
            "This video can't be played in the app — its format isn't "
            'supported on this device.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 15),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => launchUrl(Uri.parse(link),
                mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('Open in browser'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final v = _video;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (_error != null)
            Center(child: _errorView(context))
          else if (v == null)
            const Center(child: CircularProgressIndicator(color: Colors.white))
          else
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleControls,
                child: Center(
                  child: AspectRatio(
                    aspectRatio: v.value.aspectRatio,
                    child: VideoPlayer(v),
                  ),
                ),
              ),
            ),
          // Playback controls overlay (tap the video to show/hide).
          if (v != null)
            AnimatedOpacity(
              opacity: _controls ? 1 : 0,
              duration: const Duration(milliseconds: 150),
              child: IgnorePointer(
                ignoring: !_controls,
                child: _videoControls(v),
              ),
            ),
          if (_controls || _error != null)
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

  Widget _videoControls(VideoPlayerController v) {
    return Stack(
      children: [
        // Center transport: −10s · play/pause · +10s.
        Positioned.fill(
          child: Container(
            color: Colors.black26,
            child: ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: v,
              builder: (_, value, __) => Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _circleBtn(Icons.replay_10_rounded, () => _seekBy(-10)),
                  const SizedBox(width: 28),
                  _circleBtn(
                      value.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      _togglePlay,
                      big: true),
                  const SizedBox(width: 28),
                  _circleBtn(Icons.forward_10_rounded, () => _seekBy(10)),
                ],
              ),
            ),
          ),
        ),
        // Bottom: time + draggable scrubber.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
              child: ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: v,
                builder: (_, value, __) => Row(
                  children: [
                    Text(_fmt(value.position),
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12)),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: SizedBox(
                          height: 26,
                          child: VideoProgressIndicator(
                            v,
                            allowScrubbing: true,
                            // height − 2×vertical padding = ~8px thick bar.
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            colors: const VideoProgressColors(
                              playedColor: Colors.white,
                              bufferedColor: Colors.white38,
                              backgroundColor: Colors.white24,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Text(_fmt(value.duration),
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _circleBtn(IconData icon, VoidCallback onTap, {bool big = false}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: big ? 72 : 56,
        height: big ? 72 : 56,
        decoration: const BoxDecoration(
            color: Colors.black45, shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white, size: big ? 40 : 28),
      ),
    );
  }
}
