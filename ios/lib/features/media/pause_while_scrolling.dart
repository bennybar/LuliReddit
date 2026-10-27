import 'package:flutter/widgets.dart';

/// Tells the media inside a scrolling list whether it's scrolling right now
/// (from the list's scroll notifications), so animated images can pause
/// meanwhile ([PauseWhileScrolling]).
class ListScrolling extends StatefulWidget {
  const ListScrolling({super.key, required this.child});
  final Widget child;

  @override
  State<ListScrolling> createState() => _ListScrollingState();
}

class _ListScrollingState extends State<ListScrolling> {
  final _scrolling = ValueNotifier(false);

  @override
  void dispose() {
    _scrolling.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        // The list itself, not a gallery or code block scrolled sideways.
        if (n.metrics.axis == Axis.vertical) {
          if (n is ScrollStartNotification) _scrolling.value = true;
          if (n is ScrollEndNotification) _scrolling.value = false;
        }
        return false;
      },
      child: _Scrolling(notifier: _scrolling, child: widget.child),
    );
  }
}

class _Scrolling extends InheritedNotifier<ValueNotifier<bool>> {
  const _Scrolling({required super.notifier, required super.child});
}

/// An animated image (GIF, animated WebP) in [child] stops on its current
/// frame while the surrounding [ListScrolling] list scrolls, and plays again
/// when it stops: decoding GIF frames out of step with the scroll made a
/// thread with GIFs drop frames. Only these widgets rebuild on a scroll
/// start / end, not the list.
class PauseWhileScrolling extends StatelessWidget {
  const PauseWhileScrolling({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scrolling = context
            .dependOnInheritedWidgetOfExactType<_Scrolling>()
            ?.notifier
            ?.value ??
        false;
    // Image pauses its animation while TickerMode is off.
    return TickerMode(enabled: !scrolling, child: child);
  }
}
