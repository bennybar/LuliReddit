import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../core/widgets/image_decode.dart';

/// A feed video that autoplays (muted, looping) while it's on screen and pauses
/// when scrolled away. Tap opens the full-screen viewer (with sound).
class InlineVideo extends StatefulWidget {
  const InlineVideo({
    super.key,
    required this.url,
    required this.height,
    required this.onTap,
    this.poster,
  });

  final String url;
  final double height;
  final VoidCallback onTap;
  final String? poster;

  @override
  State<InlineVideo> createState() => _InlineVideoState();
}

class _InlineVideoState extends State<InlineVideo> {
  VideoPlayerController? _c;
  bool _ready = false;
  bool _muted = true;
  bool _visible = false;
  // The first frame has been decoded. Until then the video surface is blank,
  // so swapping the poster out as soon as the controller initialises made the
  // card flash empty for a moment as it scrolled in.
  bool _hasFrame = false;

  void _watchFirstFrame() {
    final c = _c;
    if (c == null || _hasFrame || c.value.position <= Duration.zero) return;
    c.removeListener(_watchFirstFrame);
    if (mounted) setState(() => _hasFrame = true);
  }

  // The player is created only once the card is mostly on screen, not when
  // it's built: the list builds cards ahead of the viewport, and a decoder
  // per nearby video competing while scrolling is what made scrolling past
  // videos stutter.
  void _setUp() {
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _c = c;
    c.setLooping(true);
    c.setVolume(_muted ? 0 : 1);
    c.addListener(_watchFirstFrame);
    c.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      if (_visible) c.play();
    }).catchError((_) {});
  }

  void _onVisibility(VisibilityInfo info) {
    final visible = info.visibleFraction > 0.6;
    if (visible == _visible) return;
    _visible = visible;
    if (visible && _c == null) {
      if (mounted) setState(_setUp);
      return;
    }
    final c = _c;
    if (c == null || !_ready) return;
    visible ? c.play() : c.pause();
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return VisibilityDetector(
      key: Key('inlinevid_${widget.url}'),
      onVisibilityChanged: _onVisibility,
      child: GestureDetector(
        onTap: widget.onTap,
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // The poster stays underneath; the video fades in on top once
              // it has a frame to show.
              if (widget.poster != null)
                CachedNetworkImage(
                    imageUrl: widget.poster!,
                    fit: BoxFit.cover,
                    memCacheWidth: feedDecodeWidth(context))
              else
                const ColoredBox(color: Colors.black12),
              if (_ready && c != null)
                AnimatedOpacity(
                  opacity: _hasFrame ? 1 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: FittedBox(
                    fit: BoxFit.cover,
                    clipBehavior: Clip.hardEdge,
                    child: SizedBox(
                      width: c.value.size.width,
                      height: c.value.size.height,
                      child: VideoPlayer(c),
                    ),
                  ),
                ),
              if (c != null && !_hasFrame)
                const Center(
                    child: SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(strokeWidth: 2))),
              // Mute / unmute toggle.
              if (_ready)
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _muted = !_muted);
                      c?.setVolume(_muted ? 0 : 1);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _muted
                            ? Icons.volume_off_rounded
                            : Icons.volume_up_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
