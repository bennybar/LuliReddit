import 'dart:ui';

import 'package:flutter/material.dart';

/// Wraps media with a frosted blur + "NSFW" label until tapped to reveal.
/// When [blur] is false it renders [child] unchanged.
class NsfwBlur extends StatefulWidget {
  const NsfwBlur({super.key, required this.blur, required this.child});
  final bool blur;
  final Widget child;

  @override
  State<NsfwBlur> createState() => _NsfwBlurState();
}

class _NsfwBlurState extends State<NsfwBlur> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.blur || _revealed) return widget.child;
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
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
