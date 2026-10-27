import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/widgets/image_decode.dart';
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
                  memCacheWidth: feedDecodeWidth(context),
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

/// A gallery as a Material 3 multi-browse carousel: a large image with the
/// next ones peeking beside it, each opening the full-screen viewer at that
/// image. Feeds use it unless Settings › Gallery carousel in feeds is off
/// (then [GalleryCarousel], one image at a time).
class GalleryM3Carousel extends StatelessWidget {
  const GalleryM3Carousel(
      {super.key, required this.images, this.title, this.height = 300});
  final List<GalleryImage> images;
  final String? title;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final n = images.length;
    final scroll = ScrollConfiguration.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(builder: (context, box) {
          final weights = multiBrowseWeights(box.maxWidth, n);
          return SizedBox(
            height: height,
            // A fling moves several images, not one (Kotlin's
            // multiBrowseFlingBehavior): long galleries go quicker. The
            // carousel takes the ambient physics when itemSnapping is off.
            child: ScrollConfiguration(
              behavior: scroll.copyWith(
                  physics: MultiBrowsePhysics(
                          weights.first / weights.reduce((a, b) => a + b))
                      .applyTo(scroll.getScrollPhysics(context))),
              child: CarouselView.weighted(
                flexWeights: weights,
                // 8 between items, as Kotlin's itemSpacing.
                padding: const EdgeInsets.symmetric(horizontal: 4),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28)),
                backgroundColor: cs.surfaceContainerHighest,
                onTap: (i) => openGalleryViewer(context, images,
                    title: title, initialIndex: i),
                children: [
                  for (var i = 0; i < n; i++)
                    Semantics(
                      image: true,
                      label: 'Image ${i + 1} of $n',
                      child: CachedNetworkImage(
                        imageUrl: images[i].url,
                        fit: BoxFit.cover,
                        // Gallery images are full size (often 12MP photos):
                        // decode at screen width, as the feed's prefetcher.
                        memCacheWidth: feedDecodeWidth(context),
                        placeholder: (_, __) =>
                            ColoredBox(color: cs.surfaceContainerHighest),
                        errorWidget: (_, __, ___) => Center(
                          child: Icon(Icons.broken_image_outlined,
                              color: cs.onSurfaceVariant),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        }),
        Padding(
          padding: const EdgeInsets.only(left: 4, top: 8),
          child: Row(
            children: [
              Icon(Icons.collections_rounded,
                  size: 14, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Text('$n images · tap one to view',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Material 3's multi-browse fling (Compose's multiBrowseFlingBehavior): a
/// fling travels as far as its speed carries it, then settles on the nearest
/// item, so a quick one skips several. [fraction]: the large item's share
/// of the carousel's width (one item's step).
/// Item widths for a multi-browse carousel [width] wide, as Compose's
/// HorizontalMultiBrowseCarousel(preferredItemWidth = 280dp) lays them out:
/// a 280 large image, a small one of up to 56 (Compose's maximum small item
/// size; at least 40), and a medium one with what's left. Each width includes
/// the item's 4 + 4 padding, the 8 between images.
List<int> multiBrowseWeights(double width, int count) {
  const gap = 8.0;
  final large = (280 + gap).clamp(0.0, width * 0.8);
  final rest = width - large;
  if (count == 2 || rest < 2 * (40 + gap)) {
    return [large.round(), rest.round().clamp(1, 1 << 30)];
  }
  final small = (rest / 2).clamp(40 + gap, 56 + gap);
  return [large.round(), (rest - small).round(), small.round()];
}

class MultiBrowsePhysics extends ScrollPhysics {
  const MultiBrowsePhysics(this.fraction, {super.parent});
  final double fraction;

  @override
  MultiBrowsePhysics applyTo(ScrollPhysics? ancestor) =>
      MultiBrowsePhysics(fraction, parent: buildParent(ancestor));

  /// Where a fling of [velocity] from [pixels] comes to rest: the nearest
  /// item to where it would coast to.
  double snapTarget(double pixels, double velocity, double viewport,
      double min, double max, Tolerance tolerance) {
    final step = viewport * fraction;
    final coast = velocity.abs() < tolerance.velocity
        ? pixels
        : ClampingScrollSimulation(position: pixels, velocity: velocity)
            .x(double.infinity);
    return ((coast / step).roundToDouble() * step).clamp(min, max);
  }

  @override
  Simulation? createBallisticSimulation(
      ScrollMetrics position, double velocity) {
    if (position.outOfRange) {
      return super.createBallisticSimulation(position, velocity);
    }
    final tolerance = toleranceFor(position);
    final target = snapTarget(
        position.pixels,
        velocity,
        position.viewportDimension,
        position.minScrollExtent,
        position.maxScrollExtent,
        tolerance);
    if ((target - position.pixels).abs() < tolerance.distance) return null;
    return ScrollSpringSimulation(spring, position.pixels, target, velocity,
        tolerance: tolerance);
  }
}
