import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A spring (mass 1) as a Flutter [Curve] over its settling [duration], so
/// implicit animations (AnimatedContainer, AnimatedSize, sheets…) can move
/// like Compose's `spring()`. Under-damped springs overshoot a little.
class Spring extends Curve {
  const Spring(this.damping, this.stiffness);
  final double damping;
  final double stiffness;

  double get _w => math.sqrt(stiffness);

  /// When the spring is within 0.1% of its target.
  Duration get duration {
    final decay = damping < 1 ? damping * _w : _w * 0.7;
    return Duration(milliseconds: (math.log(1000) / decay * 1000).round());
  }

  @override
  double transformInternal(double t) {
    final s = t * duration.inMilliseconds / 1000;
    final w = _w;
    if (damping >= 1) {
      // Critically damped: no overshoot (the "effects" springs).
      return 1 - math.exp(-w * s) * (1 + w * s);
    }
    final wd = w * math.sqrt(1 - damping * damping);
    final e = math.exp(-damping * w * s);
    return 1 -
        e * (math.cos(wd * s) + damping * w / wd * math.sin(wd * s));
  }
}

/// Material 3 Expressive's motion scheme (`MotionScheme.expressive()`):
/// bouncy spatial springs for things that move or change shape, and
/// non-bouncing effects springs for colour and opacity.
abstract final class Motion {
  static const fastSpatial = Spring(0.6, 800);
  static const defaultSpatial = Spring(0.8, 380);
  static const slowSpatial = Spring(0.8, 200);
  static const fastEffects = Spring(1, 3800);
  static const defaultEffects = Spring(1, 1600);
}

/// Bottom sheets slide up on the default spatial spring, and leave quickly
/// (a spring played backwards would bounce up first).
final sheetMotion = AnimationStyle(
  curve: Motion.defaultSpatial,
  duration: Motion.defaultSpatial.duration,
  reverseCurve: Curves.easeOutCubic,
  reverseDuration: const Duration(milliseconds: 200),
);
