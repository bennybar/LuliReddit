import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// What a swipe on a post or comment does (Settings → Swipe actions).
enum SwipeAction {
  none('Nothing', Icons.block_rounded),
  upvote('Upvote', Icons.arrow_upward_rounded),
  downvote('Downvote', Icons.arrow_downward_rounded),
  save('Save', Icons.bookmark_rounded),
  reply('Reply', Icons.reply_rounded),
  hide('Hide', Icons.visibility_off_rounded), // posts only
  collapse('Collapse', Icons.unfold_less_rounded); // comments only

  const SwipeAction(this.label, this.icon);
  final String label;
  final IconData icon;

  static SwipeAction parse(String? name, SwipeAction fallback) =>
      SwipeAction.values.asNameMap()[name] ?? fallback;
}

/// One side of a swipe: what it shows while dragging, and what it does.
class SwipeSpec {
  const SwipeSpec(this.icon, this.color, this.onTrigger);
  final IconData icon;
  final Color color;
  final VoidCallback onTrigger;
}

/// Wraps [child] with horizontal swipe actions. [start] fires when swiping
/// from the start edge toward the end (rightward in left-to-right languages,
/// leftward in Hebrew/Arabic), [end] the other way. A null side does nothing.
/// Reveals the action's icon as you drag and fires on release past the
/// threshold. Pass [enabled] = false to disable.
class SwipeActions extends StatefulWidget {
  const SwipeActions({
    super.key,
    required this.child,
    this.start,
    this.end,
    this.enabled = true,
  });

  final Widget child;
  final SwipeSpec? start;
  final SwipeSpec? end;
  final bool enabled;

  @override
  State<SwipeActions> createState() => _SwipeActionsState();
}

class _SwipeActionsState extends State<SwipeActions> {
  double _dx = 0;
  bool _fired = false;
  static const _threshold = 64.0;
  static const _maxDrag = 110.0;

  bool get _rtl => Directionality.of(context) == TextDirection.rtl;

  /// The action for a drag of [dx]: rightward is "start" in LTR, "end" in RTL.
  SwipeSpec? _specFor(double dx) =>
      (dx > 0) != _rtl ? widget.start : widget.end;

  void _update(DragUpdateDetails d) {
    final next = (_dx + d.delta.dx).clamp(-_maxDrag, _maxDrag);
    // A side with no action doesn't move.
    if (_specFor(next) == null && next != 0) return;
    setState(() => _dx = next);
    if (!_fired && _dx.abs() >= _threshold) {
      _fired = true;
      HapticFeedback.selectionClick();
    } else if (_fired && _dx.abs() < _threshold) {
      _fired = false;
    }
  }

  void _end(DragEndDetails d) {
    if (_dx.abs() >= _threshold) _specFor(_dx)?.onTrigger();
    setState(() {
      _dx = 0;
      _fired = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || (widget.start == null && widget.end == null)) {
      return widget.child;
    }
    final active = _dx.abs() >= _threshold;
    final spec = _dx == 0 ? null : _specFor(_dx);
    return GestureDetector(
      onHorizontalDragUpdate: _update,
      onHorizontalDragEnd: _end,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          if (spec != null && _dx.abs() > 2)
            Positioned.fill(
              child: Container(
                alignment:
                    _dx > 0 ? Alignment.centerLeft : Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 28),
                decoration: BoxDecoration(
                  color: spec.color.withValues(alpha: active ? 0.22 : 0.10),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Icon(spec.icon,
                    color: spec.color, size: active ? 30 : 24),
              ),
            ),
          Transform.translate(offset: Offset(_dx, 0), child: widget.child),
        ],
      ),
    );
  }
}
