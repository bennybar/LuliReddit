import 'package:cached_network_image/cached_network_image.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../core/share.dart';
import '../../models/post.dart';

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

void openVideoViewer(BuildContext context, String url, {String? title}) {
  Navigator.of(context).push(_overlayRoute(_VideoViewer(url: url, title: title)));
}

/// Normalizes common host quirks to a directly-playable video URL
/// (e.g. Imgur `.gifv` → `.mp4`).
String resolveVideoUrl(String url) {
  if (url.endsWith('.gifv')) return url.replaceAll('.gifv', '.mp4');
  return url;
}

/// Floating translucent controls (close + open-in-browser) over a top scrim.
class _ViewerControls extends StatelessWidget {
  const _ViewerControls({this.title, this.sourceUrl, this.center});
  final String? title;
  final String? sourceUrl;
  final String? center;

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
                icon: Icons.close_rounded,
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
              if (sourceUrl != null) ...[
                _RoundBtn(
                  icon: Icons.share_outlined,
                  onTap: () => shareUrl(sourceUrl!),
                ),
                const SizedBox(width: 4),
                _RoundBtn(
                  icon: Icons.open_in_new_rounded,
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
    return Material(
      color: Colors.black.withValues(alpha: 0.4),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, color: Colors.white),
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
            child:
                _ViewerControls(title: widget.title, sourceUrl: widget.url),
          ),
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
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoViewer extends StatefulWidget {
  const _VideoViewer({required this.url, this.title});
  final String url;
  final String? title;

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
          _ViewerControls(title: widget.title, sourceUrl: widget.url),
        ],
      ),
    );
  }
}
