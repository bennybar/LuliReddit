import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/post.dart';
import 'media_viewers.dart';

/// An inline, swipeable gallery preview with a page counter and dot indicator.
/// Tapping any image opens the full-screen viewer at that index.
class GalleryCarousel extends StatefulWidget {
  const GalleryCarousel(
      {super.key, required this.images, this.title, this.height});
  final List<GalleryImage> images;
  final String? title;

  /// When set, the carousel is a fixed-height (cover-cropped) banner instead of
  /// sizing to the first image's aspect ratio.
  final double? height;

  @override
  State<GalleryCarousel> createState() => _GalleryCarouselState();
}

class _GalleryCarouselState extends State<GalleryCarousel> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final first = widget.images.first;
    final aspect = (first.width != null &&
            first.height != null &&
            first.height! > 0)
        ? (first.width! / first.height!).clamp(0.5, 2.0)
        : 16 / 9;

    final stack = Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: widget.images.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => openGalleryViewer(context, widget.images,
                    title: widget.title, initialIndex: i),
                child: CachedNetworkImage(
                  imageUrl: widget.images[i].url,
                  fit: BoxFit.cover,
                  placeholder: (_, __) =>
                      Container(color: cs.surfaceContainerHighest),
                  errorWidget: (_, __, ___) => Container(
                    color: cs.surfaceContainerHighest,
                    child: Icon(Icons.broken_image_outlined,
                        color: cs.onSurfaceVariant),
                  ),
                ),
              ),
            ),
            // Counter badge
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(10)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.collections_rounded,
                        size: 14, color: Colors.white),
                    const SizedBox(width: 4),
                    Text('${_index + 1}/${widget.images.length}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
            // Dot indicator
            if (widget.images.length > 1)
              Positioned(
                bottom: 8,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < widget.images.length; i++)
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i == _index
                              ? Colors.white
                              : Colors.white54,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: widget.height != null
          ? SizedBox(height: widget.height, width: double.infinity, child: stack)
          : AspectRatio(aspectRatio: aspect, child: stack),
    );
  }
}
