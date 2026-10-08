import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How many Home posts the reader has found so far on the current load, for
/// the live counter (0 = still opening the page).
final redditHomeProgressProvider = StateProvider<int>((ref) => 0);

/// Home's loading state: a small deck of post cards shuffling while a live
/// counter shows how many posts have been found. Shown when there's no saved
/// Home page to paint instead (first open, or switching to Home).
class HomeLoadingDeck extends ConsumerStatefulWidget {
  const HomeLoadingDeck({super.key});

  @override
  ConsumerState<HomeLoadingDeck> createState() => _HomeLoadingDeckState();
}

class _HomeLoadingDeckState extends ConsumerState<HomeLoadingDeck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _riffle = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect "remove animations": a still deck, the counter still counts.
    if (MediaQuery.disableAnimationsOf(context)) {
      _riffle.stop();
    } else if (!_riffle.isAnimating) {
      _riffle.repeat();
    }
  }

  @override
  void dispose() {
    _riffle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final found = ref.watch(redditHomeProgressProvider);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 230,
            height: 170,
            child: AnimatedBuilder(
              animation: _riffle,
              builder: (_, __) {
                final t = _riffle.value;
                // The top card is flicked out to the right, then slides back
                // in *behind* the others: it switches sides at 41%.
                final behind = t >= 0.41;
                final top = Transform.translate(
                  offset: Offset(_lerpPath(t, 0, 110, 0), _lerpPath(t, 0, -14, 0)),
                  child: Transform.rotate(
                    angle: _lerpPath(t, 0, 16, -2) * math.pi / 180,
                    child: _DeckCard(cs: cs, accent: true),
                  ),
                );
                return Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    if (behind) top,
                    Transform.translate(
                      offset: const Offset(-8, 0),
                      child: Transform.rotate(
                          angle: -8 * math.pi / 180,
                          child: _DeckCard(cs: cs)),
                    ),
                    Transform.translate(
                      offset: const Offset(6, 0),
                      child: Transform.rotate(
                          angle: 5 * math.pi / 180, child: _DeckCard(cs: cs)),
                    ),
                    if (!behind) top,
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 18),
          Text.rich(
            found == 0
                ? const TextSpan(text: 'Opening your Home…')
                : TextSpan(children: [
                    const TextSpan(text: 'Found '),
                    TextSpan(
                        text: '$found',
                        style: TextStyle(
                            color: cs.primary, fontWeight: FontWeight.w800)),
                    TextSpan(text: found == 1 ? ' post' : ' posts'),
                    const TextSpan(text: ' in your Home'),
                  ]),
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  /// Out to [peak] over the first 40%, back to [end] by 80%, then settle at 0.
  static double _lerpPath(double t, double start, double peak, double end) {
    final ease = Curves.easeInOutCubic;
    if (t < 0.4) return start + (peak - start) * ease.transform(t / 0.4);
    if (t < 0.8) return peak + (end - peak) * ease.transform((t - 0.4) / 0.4);
    return end * (1 - (t - 0.8) / 0.2);
  }
}

class _DeckCard extends StatelessWidget {
  const _DeckCard({required this.cs, this.accent = false});
  final ColorScheme cs;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    Widget bar(double w) => Container(
          width: w,
          height: 7,
          decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(5)),
        );
    return Container(
      width: 150,
      height: 120,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.surfaceContainerHighest),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 14,
              offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          bar(60),
          const SizedBox(height: 6),
          bar(128),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: accent ? cs.primaryContainer : cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(9),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Deals a freshly loaded Home card into the feed: it rises from below with a
/// slight tilt, staggered by [index], once. Used for the first few cards after
/// the loading deck.
class DealIn extends StatefulWidget {
  const DealIn(
      {super.key,
      required this.index,
      required this.animate,
      required this.child});
  final int index;
  // Read once, when the card first appears: only cards that arrive right
  // after the loading deck are dealt; ones rebuilt later just show.
  final bool animate;
  final Widget child;

  @override
  State<DealIn> createState() => _DealInState();
}

class _DealInState extends State<DealIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 600));

  @override
  void initState() {
    super.initState();
    if (!widget.animate) {
      _c.value = 1;
      return;
    }
    Future<void>.delayed(Duration(milliseconds: 100 * widget.index), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    final tilt = [-6.0, 5.0, -3.0][widget.index % 3];
    final rise = 180.0 - 60 * (widget.index % 3);
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (_, child) {
        final t = Curves.easeOutCubic.transform(_c.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, rise * (1 - t)),
            child: Transform.rotate(
              angle: tilt * (1 - t) * math.pi / 180,
              child: Transform.scale(scale: 0.85 + 0.15 * t, child: child),
            ),
          ),
        );
      },
    );
  }
}
