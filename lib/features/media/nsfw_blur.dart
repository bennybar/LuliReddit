import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Wraps media with a frosted blur + "NSFW" label until tapped to reveal.
/// When [blur] is false it renders [child] unchanged.
///
/// Given Reddit's pre-blurred copy ([blurredImageUrl]) it just draws that:
/// a live [BackdropFilter] re-blurs the media on every frame, which is one
/// of the most expensive things a scrolling list can do.
class NsfwBlur extends StatefulWidget {
  const NsfwBlur(
      {super.key, required this.blur, required this.child, this.blurredImageUrl});
  final bool blur;
  final Widget child;
  final String? blurredImageUrl;

  @override
  State<NsfwBlur> createState() => _NsfwBlurState();
}

class _NsfwBlurState extends State<NsfwBlur> {
  bool _revealed = false;

  Widget _frost({required Widget child}) {
    final url = widget.blurredImageUrl;
    if (url == null) {
      return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24), child: child);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => const ColoredBox(color: Colors.black),
          placeholder: (_, __) => const ColoredBox(color: Colors.black),
        ),
        child,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.blur || _revealed) return widget.child;
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: _frost(
              child: Material(
                color: Colors.black.withValues(alpha: 0.25),
                child: InkWell(
                  onTap: () => setState(() => _revealed = true),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.visibility_off_rounded,
                            color: Colors.white, size: 32),
                        SizedBox(height: 8),
                        Text('NSFW · tap to view',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
