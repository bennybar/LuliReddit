import 'dart:async';
import 'dart:io' show Platform;

import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../core/media_links.dart';
import '../../core/open_link.dart';
import '../../core/redgifs.dart';
import '../../core/share.dart';
import '../../models/post.dart';
import '../feed/inline_video.dart';
import 'save_media.dart';

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

/// A video post's playable URL, without any network lookup: Reddit's own
/// stream when it hosts the video, a direct file link as-is, and otherwise
/// Reddit's mp4 copy of the embed (e.g. RedGifs), whose own URL is a web page.
String postVideoUrl(Post p) {
  final hosted = p.hlsUrl ?? p.fallbackVideoUrl;
  if (hosted != null) return hosted;
  final direct = resolveVideoUrl(p.url);
  final uri = Uri.tryParse(direct);
  if (uri != null && isVideoUrl(uri)) return direct;
  return p.gifMp4Url ?? direct;
}

/// A video post Ilay can't play itself — a YouTube / Vimeo / other embed with
/// no Reddit-hosted copy or direct file. It opens in its own app or the
/// browser (it used to land on a "can't be played" error screen).
bool isExternalVideo(Post p) {
  if (p.type != PostType.video ||
      p.hlsUrl != null ||
      p.fallbackVideoUrl != null ||
      p.gifMp4Url != null) {
    return false;
  }
  if (redgifsId(p.url) != null) return false;
  final u = Uri.tryParse(resolveVideoUrl(p.url));
  return u == null || !isVideoUrl(u);
}

/// Where an external video plays, for its feed label ("YouTube").
String externalVideoSource(Post p) {
  var d = p.domain.toLowerCase();
  if (d.startsWith('www.')) d = d.substring(4);
  if (d.startsWith('m.')) d = d.substring(2);
  if (d == 'youtu.be' || d.endsWith('youtube.com')) return 'YouTube';
  if (d.endsWith('vimeo.com')) return 'Vimeo';
  if (d.endsWith('twitch.tv')) return 'Twitch';
  if (d.endsWith('streamable.com')) return 'Streamable';
  return d.isEmpty ? 'Video' : d;
}

/// Opens a video post full-screen. RedGifs clips are resolved to their HD
/// file (with sound) first, falling back to Reddit's silent mp4 copy.
Future<void> openPostVideo(BuildContext context, Post p) async {
  if (isExternalVideo(p)) {
    // In the app that handles it (YouTube for a YouTube link), else the
    // browser.
    final uri = Uri.tryParse(p.url);
    if (uri == null) return;
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on PlatformException {
      // no app for it
    }
    if (!opened && context.mounted) openInBrowser(context, uri);
    return;
  }
  var src = postVideoUrl(p);
  var download = p.fallbackVideoUrl ?? src;
  if (p.hlsUrl == null &&
      p.fallbackVideoUrl == null &&
      redgifsId(p.url) != null) {
    final hd = await resolveRedgifs(p.url);
    if (hd != null) src = download = hd;
    if (!context.mounted) return;
  }
  openVideoViewer(context, src,
      title: p.title, downloadUrl: download, externalUrl: p.url);
}

/// The playable URL for a video link: imgur `.gifv` → `.mp4`; a bare
/// v.redd.it video (or one embedded in a post / comment as
/// `reddit.com/link/…/video/<id>/player`) → its HLS playlist, which the
/// player streams with sound; everything else unchanged.
String resolveVideoUrl(String url) {
  final u = Uri.tryParse(url);
  final v = (u == null ? null : inlineRedditVideo(u)) ??
      (u != null && u.host.toLowerCase() == 'v.redd.it' ? u : null);
  final segs = v?.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segs != null && segs.length == 1) {
    return 'https://v.redd.it/${segs.first}/HLSPlaylist.m3u8';
  }
  if (url.toLowerCase().split('?').first.endsWith('.gifv')) {
    return url.replaceAll(RegExp(r'\.gifv', caseSensitive: false), '.mp4');
  }
  return url;
}

/// Opens [url] in another app (browser / Reddit / player), not in-app.
Future<void> _openExternally(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.of(context);
  var opened = false;
  try {
    opened = await launchUrl(Uri.parse(url),
        mode: LaunchMode.externalApplication);
  } on PlatformException {
    // no app for it
  }
  if (!opened) {
    messenger.showSnackBar(
        const SnackBar(content: Text('No app can open this link.')));
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
                label: 'Close',
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
                      fontWeight: FontWeight.w600,
                      shadows: [
                        Shadow(color: Color(0x80000000), blurRadius: 6)
                      ]),
                ),
              ),
              if (downloadUrl != null) ...[
                _RoundBtn(
                  icon: Platform.isIOS
                      ? CupertinoIcons.cloud_download
                      : Icons.download_rounded,
                  label: 'Download',
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
                  label: 'Share',
                  onTap: () => shareUrl(context, sourceUrl!),
                ),
                const SizedBox(width: 4),
                _RoundBtn(
                  icon: Platform.isIOS
                      ? CupertinoIcons.arrow_up_right_square
                      : Icons.open_in_new_rounded,
                  label: 'Open in browser',
                  onTap: () => _openExternally(context, sourceUrl!),
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
  const _RoundBtn(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Clean iOS/Stories style: a white glyph with a soft shadow over the top
    // scrim (a BackdropFilter blur on a tiny circle renders unreliably over
    // media). Uses GestureDetector (not IconButton) because the media Stack
    // has no Material ancestor, which would make IconButton taps silently
    // no-op.
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
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
      ),
    );
  }
}

/// The top controls of the image / gallery viewers: fade with [visible],
/// and take no taps while hidden.
Widget _fadingControls(bool visible, Widget controls) => AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 150),
      child: IgnorePointer(ignoring: !visible, child: controls),
    );

/// A full-resolution image that failed to load.
Widget _brokenImage(BuildContext context, Object error, StackTrace? stack) =>
    const Center(
        child: Icon(Icons.broken_image_rounded,
            size: 48, color: Colors.white60));

/// Shared immersive behaviour + swipe-down-to-dismiss with background fade.
/// The feed's inline clip pauses while a viewer covers it.
mixin _ImmersiveDismiss<T extends StatefulWidget> on State<T> {
  double drag = 0;
  bool zoomed = false;
  bool showControls = true;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    InlineVideoPool.instance.setCovered(true);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    InlineVideoPool.instance.setCovered(false);
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
                errorBuilder: _brokenImage,
              ),
            ),
          ),
          _fadingControls(
            showControls && drag.abs() < 8,
            _ViewerControls(
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
  late int _index =
      widget.initialIndex.clamp(0, widget.images.length - 1).toInt();
  late final _controller = PageController(initialPage: _index);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _warm(_index));
  }

  // The images either side are loaded ahead, so paging shows them ready.
  void _warm(int i) {
    if (!mounted) return;
    for (final j in [i - 1, i + 1]) {
      if (j < 0 || j >= widget.images.length) continue;
      precacheImage(CachedNetworkImageProvider(widget.images[j].url), context)
          .ignore();
    }
  }

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
                onPageChanged: (i) {
                  setState(() {
                    _index = i;
                    zoomed = false;
                  });
                  _warm(i);
                },
                scaleStateChangedCallback: (s) =>
                    setState(() => zoomed = s != PhotoViewScaleState.initial),
                builder: (_, i) => PhotoViewGalleryPageOptions(
                  imageProvider: CachedNetworkImageProvider(widget.images[i].url),
                  minScale: PhotoViewComputedScale.contained,
                  maxScale: PhotoViewComputedScale.covered * 4,
                  onTapUp: (_, __, ___) =>
                      setState(() => showControls = !showControls),
                  errorBuilder: _brokenImage,
                ),
                backgroundDecoration:
                    const BoxDecoration(color: Colors.transparent),
                loadingBuilder: (_, __) => const Center(
                    child: CircularProgressIndicator(color: Colors.white)),
              ),
            ),
          ),
          _fadingControls(
            showControls && drag.abs() < 8,
            _ViewerControls(
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
  final _pool = InlineVideoPool.instance;
  VideoPlayerController? _video; // set once playing; drives the UI
  // Owned from creation so dispose() always releases it, even if the viewer
  // closes while it's still initializing (it used to leak, and could start
  // playing with no screen).
  VideoPlayerController? _controller;
  // The feed card's own player (see InlineVideoPool.borrow): given back on
  // close, not disposed.
  bool _borrowed = false;
  String? _error;
  bool _controls = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    _pool.setCovered(true);
    // The clip playing in the feed: carry on with it, from the same frame
    // and with nothing downloaded again.
    final lent = _pool.borrow(widget.url);
    if (lent != null) {
      _borrowed = true;
      _controller = _video = lent;
      videoSound(lent, muted: false);
      lent
        ..addListener(_watchError)
        ..play();
      _scheduleHide();
    } else {
      _init();
    }
  }

  Future<void> _init() async {
    // Full screen takes the audio session (pauses the user's music).
    final v = _controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.url),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false));
    try {
      await v.initialize();
      if (!mounted) return;
      await v.setLooping(true);
      // Carry on from where the feed card was.
      final at = _pool.position(widget.url);
      if (at != null && mounted) await v.seekTo(at);
      if (!mounted) return;
      await v.play();
      if (!mounted) return;
      v.addListener(_watchError);
      setState(() => _video = v);
      _scheduleHide();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _watchError() {
    final v = _video;
    if (v != null && v.value.hasError && _error == null && mounted) {
      setState(() => _error = v.value.errorDescription ?? 'Playback error');
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

  Future<void> _seekTo(Duration target) async {
    final v = _video;
    if (v == null) return;
    final max = v.value.duration;
    await v.seekTo(target < Duration.zero
        ? Duration.zero
        : (target > max ? max : target));
    _scheduleHide();
  }

  static const _ten = Duration(seconds: 10);

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
    final c = _controller;
    c?.removeListener(_watchError);
    if (_borrowed && c != null) {
      _pool.giveBack(c);
    } else {
      c?.dispose();
    }
    _pool.setCovered(false);
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
            onPressed: () => _openExternally(context, link),
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
          if (v != null && _error == null)
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
              sourceUrl: widget.externalUrl ?? widget.url,
              // A direct mp4 for saving (an HLS playlist can't be saved).
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
                  _circleBtn(Icons.replay_10_rounded, 'Back 10 seconds',
                      () => _seekTo(v.value.position - _ten)),
                  const SizedBox(width: 28),
                  _circleBtn(
                      value.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      'Play/pause',
                      _togglePlay,
                      big: true),
                  const SizedBox(width: 28),
                  _circleBtn(Icons.forward_10_rounded, 'Forward 10 seconds',
                      () => _seekTo(v.value.position + _ten)),
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
                        child: _Scrubber(value: value, onSeek: _seekTo),
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

  Widget _circleBtn(IconData icon, String label, VoidCallback onTap,
      {bool big = false}) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: big ? 72 : 56,
          height: big ? 72 : 56,
          decoration: const BoxDecoration(
              color: Colors.black45, shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white, size: big ? 40 : 28),
        ),
      ),
    );
  }
}

/// An ~8px thick progress bar you can tap or drag to seek. For screen
/// readers it's a slider: the position read out, and swipe up / down to
/// seek.
class _Scrubber extends StatefulWidget {
  const _Scrubber({required this.value, required this.onSeek});
  final VideoPlayerValue value;
  final ValueChanged<Duration> onSeek;

  @override
  State<_Scrubber> createState() => _ScrubberState();
}

class _ScrubberState extends State<_Scrubber> {
  double? _drag; // the fraction under the finger while dragging

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    final ms = value.duration.inMilliseconds;
    final played = _drag ??
        (ms > 0 ? (value.position.inMilliseconds / ms).clamp(0.0, 1.0) : 0.0);
    final bufferedEnd = value.buffered
        .fold<int>(0, (m, r) => math.max(m, r.end.inMilliseconds));
    final buffered = ms > 0 ? (bufferedEnd / ms).clamp(0.0, 1.0) : 0.0;
    void seek(double f) {
      if (ms > 0) {
        widget.onSeek(
            Duration(milliseconds: (f.clamp(0.0, 1.0) * ms).round()));
      }
    }

    final pct = (played * 100).round();
    return Semantics(
      slider: true,
      label: 'Video position',
      value: '$pct%',
      increasedValue: '${math.min(pct + 5, 100)}%',
      decreasedValue: '${math.max(pct - 5, 0)}%',
      onIncrease: ms > 0 ? () => seek(played + 0.05) : null,
      onDecrease: ms > 0 ? () => seek(played - 0.05) : null,
      child: LayoutBuilder(builder: (context, box) {
        double frac(double x) => (x / box.maxWidth).clamp(0.0, 1.0);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => seek(frac(d.localPosition.dx)),
          onHorizontalDragStart: (d) =>
              setState(() => _drag = frac(d.localPosition.dx)),
          onHorizontalDragUpdate: (d) =>
              setState(() => _drag = frac(d.localPosition.dx)),
          onHorizontalDragEnd: (_) {
            final f = _drag;
            if (f != null) seek(f);
            setState(() => _drag = null);
          },
          onHorizontalDragCancel: () => setState(() => _drag = null),
          child: SizedBox(
            height: 26,
            width: double.infinity,
            child: CustomPaint(painter: _ScrubberPainter(played, buffered)),
          ),
        );
      }),
    );
  }
}

class _ScrubberPainter extends CustomPainter {
  _ScrubberPainter(this.played, this.buffered);
  final double played;
  final double buffered;

  @override
  void paint(Canvas canvas, Size size) {
    const h = 8.0;
    final top = (size.height - h) / 2;
    void bar(double fraction, Color color) {
      if (fraction <= 0) return;
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(0, top, size.width * fraction, h),
              const Radius.circular(h / 2)),
          Paint()..color = color);
    }

    bar(1, Colors.white24);
    bar(buffered, Colors.white38);
    bar(played, Colors.white);
  }

  @override
  bool shouldRepaint(_ScrubberPainter old) =>
      old.played != played || old.buffered != buffered;
}
