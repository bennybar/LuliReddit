import 'package:flutter/widgets.dart';

/// Ignores pointer input for a short window after it first appears, then becomes
/// interactive. Used to wrap freshly-opened bottom sheets so the gesture that
/// opened them (a tap or a press-and-hold) can't "fall through" and immediately
/// trigger the item under the finger.
class TapGuard extends StatefulWidget {
  const TapGuard({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 300),
  });

  final Widget child;
  final Duration duration;

  @override
  State<TapGuard> createState() => _TapGuardState();
}

class _TapGuardState extends State<TapGuard> {
  bool _ignore = true;

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.duration, () {
      if (mounted) setState(() => _ignore = false);
    });
  }

  @override
  Widget build(BuildContext context) =>
      IgnorePointer(ignoring: _ignore, child: widget.child);
}
