import 'dart:math' as math;
import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_new_shapes/material_new_shapes.dart' hide Cubic;

// Material 3 Expressive's LoadingIndicator, as in Compose's material3: seven
// shapes morph into each other on a spring every 650ms, each morph adding a
// quarter turn, over a slow global spin.
const _morphIntervalMs = 650;
const _globalRotationMs = 4666;
// The active indicator's share of the container (38dp of 48dp).
const _activeScale = 38 / 48;

final List<RoundedPolygon> _shapes = [
  MaterialShapes.softBurst,
  MaterialShapes.cookie9Sided,
  MaterialShapes.pentagon,
  MaterialShapes.pill,
  MaterialShapes.sunny,
  MaterialShapes.cookie4Sided,
  MaterialShapes.oval,
].map((p) => p.normalized()).toList();

// Built once, on first use: matching two shapes' curves isn't free.
final List<Morph> _morphs = [
  for (var i = 0; i < _shapes.length; i++)
    Morph(_shapes[i], _shapes[(i + 1) % _shapes.length]),
];

final Morph _determinate =
    Morph(MaterialShapes.circle.normalized(), _shapes.first);

// One scale for every shape, so none outgrows the container as it turns
// (Compose's calculateScaleFactor).
final double _scaleFactor = () {
  var f = 1.0;
  for (final p in [..._shapes, MaterialShapes.circle.normalized()]) {
    final b = p.calculateBounds();
    final m = p.calculateMaxBounds();
    final sx = (b[2] - b[0]) / (m[2] - m[0]);
    final sy = (b[3] - b[1]) / (m[3] - m[1]);
    f = math.min(f, math.max(sx, sy));
  }
  return f;
}();

// The morph's spring (damping 0.6, stiffness 200), as a function of time.
final _morphSpring = SpringSimulation(
    SpringDescription.withDampingRatio(mass: 1, stiffness: 200, ratio: 0.6),
    0,
    1,
    0);

/// Material 3 Expressive's loading indicator (morphing shapes), in place of
/// the plain spinner. [size] is the container (48 by default); the shape
/// fills 38/48 of it. [value]: a determinate progress (a circle morphing
/// into a burst), as pull to refresh shows while you pull. Inside a button
/// pass the button's content colour as [color].
///
/// It only animates while visible: muted with its route or tab (TickerMode,
/// an IndexedStack), and still when the system asks to reduce motion.
class Loading extends StatefulWidget {
  const Loading(
      {super.key, this.size = 48, this.color, this.value, this.label})
      : _content = false;

  /// In the content colour around it (a button's, a list tile's icons), as
  /// Kotlin passes `LocalContentColor.current`: the default primary vanishes
  /// on a filled or disabled button.
  const Loading.onContent({super.key, this.size = 24})
      : color = null,
        value = null,
        label = null,
        _content = true;

  final double size;
  final Color? color;
  final double? value;
  final String? label;
  final bool _content;

  @override
  State<Loading> createState() => _LoadingState();
}

class _LoadingState extends State<Loading> with SingleTickerProviderStateMixin {
  final _clock = ValueNotifier<Duration>(Duration.zero);
  late final Ticker _ticker = createTicker((t) => _clock.value = t);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(Loading old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final run = widget.value == null &&
        !(MediaQuery.maybeDisableAnimationsOf(context) ?? false) &&
        Visibility.of(context);
    if (run && !_ticker.isActive) {
      _ticker.start();
    } else if (!run && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value?.clamp(0.0, 1.0);
    return Semantics(
      label: widget.label ?? 'Loading',
      role: value == null
          ? SemanticsRole.loadingSpinner
          : SemanticsRole.progressBar,
      minValue: value == null ? null : '0',
      maxValue: value == null ? null : '100',
      value: value == null ? null : '${(value * 100).round()}',
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.square(widget.size),
          painter: _LoadingPainter(
            clock: _clock,
            color: widget.color ??
                (widget._content ? IconTheme.of(context).color : null) ??
                Theme.of(context).colorScheme.primary,
            value: value,
          ),
        ),
      ),
    );
  }
}

class _LoadingPainter extends CustomPainter {
  _LoadingPainter({required this.clock, required this.color, this.value})
      : super(repaint: clock);
  final ValueNotifier<Duration> clock;
  final Color color;
  final double? value;
  final Path _path = Path();

  @override
  void paint(Canvas canvas, Size size) {
    final double degrees;
    final Path path;
    final v = value;
    if (v != null) {
      path = _determinate.toPath(progress: v, path: _path);
      degrees = v * 180;
    } else {
      final ms = clock.value.inMilliseconds;
      final step = ms ~/ _morphIntervalMs;
      final morph =
          _morphSpring.x((ms % _morphIntervalMs) / 1000).clamp(0.0, 1.2);
      path = _morphs[step % _morphs.length]
          .toPath(progress: morph, path: _path);
      degrees = (ms % _globalRotationMs) / _globalRotationMs * 360 +
          (step % 4 + morph) * 90;
    }
    final side = size.shortestSide * _activeScale * _scaleFactor;
    canvas
      ..save()
      ..translate(size.width / 2, size.height / 2)
      ..rotate(degrees * math.pi / 180)
      ..scale(side)
      ..translate(-0.5, -0.5)
      ..drawPath(path, Paint()..color = color)
      ..restore();
  }

  @override
  bool shouldRepaint(_LoadingPainter old) =>
      old.color != color || old.value != value || old.clock != clock;
}

/// Pull to refresh with the Expressive loading indicator on its tonal
/// container: while pulling it morphs a circle towards a burst, then morphs
/// on its own while [onRefresh] runs. Flutter's [RefreshIndicator] (without
/// its spinner) still decides when a pull counts, so the gesture is the same.
class RefreshBox extends StatefulWidget {
  const RefreshBox(
      {super.key,
      required this.onRefresh,
      required this.child,
      this.edgeOffset = 0});
  final RefreshCallback onRefresh;
  final Widget child;
  final double edgeOffset;

  @override
  State<RefreshBox> createState() => RefreshBoxState();
}

class RefreshBoxState extends State<RefreshBox>
    with SingleTickerProviderStateMixin {
  final _inner = GlobalKey<RefreshIndicatorState>();
  // How far the indicator has come down: 1 is armed (and where it rests
  // while refreshing); up to 1.5 when pulled further.
  late final _pull = AnimationController(vsync: this, upperBound: 1.5);
  RefreshIndicatorStatus? _status;
  double? _drag; // pixels pulled past the top, while a pull is tracked

  /// Shows the indicator and refreshes, as a pull would.
  Future<void> show() => _inner.currentState?.show() ?? Future.value();

  @override
  void dispose() {
    _pull.dispose();
    super.dispose();
  }

  void _onStatus(RefreshIndicatorStatus? s) {
    setState(() => _status = s);
    switch (s) {
      case RefreshIndicatorStatus.snap:
      case RefreshIndicatorStatus.refresh:
        _pull.animateTo(1,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic);
      case RefreshIndicatorStatus.done:
      case RefreshIndicatorStatus.canceled:
        _drag = null;
        _pull.animateTo(0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInCubic);
      default:
    }
  }

  // Mirrors RefreshIndicator's own drag maths: it arms at a sixth of the
  // viewport.
  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axisDirection != AxisDirection.down) {
      return false;
    }
    if (n is ScrollStartNotification &&
        n.dragDetails != null &&
        n.metrics.extentBefore == 0) {
      _drag = 0;
    } else if (_drag != null &&
        (_status == RefreshIndicatorStatus.drag ||
            _status == RefreshIndicatorStatus.armed)) {
      if (n is ScrollUpdateNotification) {
        _drag = _drag! - (n.scrollDelta ?? 0);
      } else if (n is OverscrollNotification) {
        _drag = _drag! - n.overscroll;
      }
      _pull.value =
          (_drag! / (n.metrics.viewportDimension / 6)).clamp(0.0, 1.5);
    }
    if (n is ScrollEndNotification) _drag = null;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final refreshing = _status == RefreshIndicatorStatus.snap ||
        _status == RefreshIndicatorStatus.refresh;
    return Stack(
      children: [
        RefreshIndicator.noSpinner(
          key: _inner,
          onRefresh: widget.onRefresh,
          onStatusChange: _onStatus,
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: widget.child,
          ),
        ),
        Positioned(
          top: widget.edgeOffset,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _pull,
              builder: (context, child) {
                final p = _pull.value;
                if (p == 0) return const SizedBox.shrink();
                // Slides down from above the top edge, resting 16 below it.
                final dy = -48.0 +
                    64 * math.min(p, 1.0) +
                    24 * math.max(p - 1, 0.0);
                return Transform.translate(
                  offset: Offset(0, dy),
                  child: Center(
                    child: Material(
                      color: cs.primaryContainer,
                      shape: const CircleBorder(),
                      elevation: 2,
                      child: Loading(
                        size: 48,
                        color: cs.onPrimaryContainer,
                        value: refreshing ? null : math.min(p, 1.0),
                        label: 'Refresh',
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Material 3 Expressive's LinearWavyProgressIndicator: the filled part is a
/// travelling wave, with a gap before the flat track and a stop dot at its
/// end. [value] null: indeterminate (wavy segments sweep across).
class WavyProgress extends StatefulWidget {
  const WavyProgress({super.key, this.value, this.label});
  final double? value;
  final String? label;

  @override
  State<WavyProgress> createState() => _WavyProgressState();
}

class _WavyProgressState extends State<WavyProgress>
    with SingleTickerProviderStateMixin {
  final _clock = ValueNotifier<Duration>(Duration.zero);
  late final Ticker _ticker = createTicker((t) => _clock.value = t);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final run = !(MediaQuery.maybeDisableAnimationsOf(context) ?? false) &&
        Visibility.of(context);
    if (run && !_ticker.isActive) {
      _ticker.start();
    } else if (!run && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final value = widget.value?.clamp(0.0, 1.0);
    return Semantics(
      label: widget.label,
      role: value == null
          ? SemanticsRole.loadingSpinner
          : SemanticsRole.progressBar,
      minValue: value == null ? null : '0',
      maxValue: value == null ? null : '100',
      value: value == null ? null : '${(value * 100).round()}',
      child: RepaintBoundary(
        child: CustomPaint(
          size: const Size(double.infinity, 10),
          painter: _WavyPainter(
            clock: _clock,
            value: value,
            active: cs.primary,
            track: cs.secondaryContainer,
          ),
        ),
      ),
    );
  }
}

class _WavyPainter extends CustomPainter {
  _WavyPainter(
      {required this.clock,
      required this.value,
      required this.active,
      required this.track})
      : super(repaint: clock);
  final ValueNotifier<Duration> clock;
  final double? value;
  final Color active;
  final Color track;

  static const _stroke = 4.0;
  static const _gap = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final s = clock.value.inMicroseconds / 1e6;
    final w = size.width;
    final cy = size.height / 2;
    final amp = (size.height - _stroke) / 2;
    final line = Paint()
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    // A wave from x0 to x1 (stroke ends included), travelling one
    // wavelength a second.
    void wave(double x0, double x1, double wavelength, double a) {
      x0 += _stroke / 2;
      x1 -= _stroke / 2;
      if (x1 < x0) return;
      final path = Path();
      for (var x = x0;; x += 2) {
        final xx = math.min(x, x1);
        final y = cy + a * math.sin(2 * math.pi * (xx / wavelength - s));
        xx == x0 ? path.moveTo(xx, y) : path.lineTo(xx, y);
        if (xx >= x1) break;
      }
      canvas.drawPath(path, line..color = active);
    }

    void flat(double x0, double x1) {
      x0 += _stroke / 2;
      x1 -= _stroke / 2;
      if (x1 < x0) return;
      canvas.drawLine(Offset(x0, cy), Offset(x1, cy), line..color = track);
    }

    final v = value;
    if (v != null) {
      final end = w * v;
      // The wave flattens near the ends, as Compose's does.
      final a = v < 0.1 || v > 0.95 ? 0.0 : amp;
      if (end > 0) wave(0, end, 32, a);
      flat(end > 0 ? end + _gap : 0, w);
      // The stop dot marks where 100% is.
      canvas.drawCircle(
          Offset(w - _stroke / 2, cy), _stroke / 2, Paint()..color = active);
      return;
    }
    // Indeterminate: Material's two-line sweep (1.8s cycle) with waves.
    final t = (s % 1.8) / 1.8;
    double seg(double t, double start, double len, Curve c) =>
        c.transform(((t - start) / len).clamp(0.0, 1.0));
    final h1 = seg(t, 0, 0.4, const Cubic(0.2, 0, 0.8, 1));
    final t1 = seg(t, 0.2, 0.45, const Cubic(0.4, 0, 1, 1));
    final h2 = seg(t, 0.55, 0.45, const Cubic(0, 0, 0.65, 1));
    final t2 = seg(t, 0.75, 0.25, const Cubic(0.1, 0, 0.45, 1));
    final segments = [(t1 * w, h1 * w), (t2 * w, h2 * w)];
    var x = 0.0;
    for (final (a, b) in segments) {
      if (b - a < 1) continue;
      flat(x, a - _gap);
      wave(a, b, 20, amp);
      x = b + _gap;
    }
    flat(x, w);
  }

  @override
  bool shouldRepaint(_WavyPainter old) =>
      old.value != value || old.active != active || old.track != track;
}
