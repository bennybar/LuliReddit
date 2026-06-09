import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';

/// Wraps [child] with horizontal swipe-to-vote: swipe right = upvote,
/// swipe left = downvote. Reveals a colored arrow as you drag and fires on
/// release past the threshold. Pass [enabled] = false to disable.
class SwipeActions extends StatefulWidget {
  const SwipeActions({
    super.key,
    required this.child,
    required this.onRight,
    required this.onLeft,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback onRight;
  final VoidCallback onLeft;
  final bool enabled;

  @override
  State<SwipeActions> createState() => _SwipeActionsState();
}

class _SwipeActionsState extends State<SwipeActions> {
  double _dx = 0;
  bool _fired = false;
  static const _threshold = 64.0;
  static const _maxDrag = 110.0;

  void _update(DragUpdateDetails d) {
    setState(() => _dx = (_dx + d.delta.dx).clamp(-_maxDrag, _maxDrag));
    if (!_fired && _dx.abs() >= _threshold) {
      _fired = true;
      HapticFeedback.selectionClick();
    } else if (_fired && _dx.abs() < _threshold) {
      _fired = false;
    }
  }

  void _end(DragEndDetails d) {
    if (_dx >= _threshold) {
      widget.onRight();
    } else if (_dx <= -_threshold) {
      widget.onLeft();
    }
    setState(() {
      _dx = 0;
      _fired = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final votes = Theme.of(context).extension<VoteColors>()!;
    final active = _dx.abs() >= _threshold;
    final right = _dx > 0;
    return GestureDetector(
      onHorizontalDragUpdate: _update,
      onHorizontalDragEnd: _end,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          if (_dx.abs() > 2)
            Positioned.fill(
              child: Container(
                alignment: right ? Alignment.centerLeft : Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 28),
                decoration: BoxDecoration(
                  color: (right ? votes.up : votes.down)
                      .withValues(alpha: active ? 0.22 : 0.10),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Icon(
                  right ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                  color: right ? votes.up : votes.down,
                  size: active ? 30 : 24,
                ),
              ),
            ),
          Transform.translate(offset: Offset(_dx, 0), child: widget.child),
        ],
      ),
    );
  }
}
