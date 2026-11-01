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
  // Posts only; local, a day.
  dismiss('Dismiss (Home / For You)', Icons.close_rounded),
  // Posts only; local.
  hideSub('Hide subreddit 7 days (front page)',
      Icons.do_not_disturb_on_rounded),
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
/// Reveals the action's pill as you drag and fires on release past the
/// threshold. Pass [enabled] = false to disable. A [child] with no
/// background of its own (the Calm comment rows) passes [slideColor]: it's
/// filled with it while dragged, so it slides like a card. One with a margin
/// around its card passes it as [actionInset].
class SwipeActions extends StatefulWidget {
  const SwipeActions({
    super.key,
    required this.child,
    this.start,
    this.end,
    this.enabled = true,
    this.slideColor,
    this.actionInset = EdgeInsets.zero,
  });

  final Widget child;
  final SwipeSpec? start;
  final SwipeSpec? end;
  final bool enabled;
  final Color? slideColor;
  final EdgeInsetsGeometry actionInset;

  @override
  State<SwipeActions> createState() => _SwipeActionsState();
}

class _SwipeActionsState extends State<SwipeActions>
    with SingleTickerProviderStateMixin {
  double _dx = 0;
  bool _fired = false;
  static const _threshold = 64.0;
  // Springs the row back into place, the pill closing behind it.
  late final AnimationController _settle = AnimationController.unbounded(vsync: this)
    ..addListener(() => setState(() => _dx = _settle.value));

  // Far enough for the pill to take real space, with the row still in view.
  double get _maxDrag => MediaQuery.sizeOf(context).width * 0.45;

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  bool get _rtl => Directionality.of(context) == TextDirection.rtl;

  /// The action for a drag of [dx]: rightward is "start" in LTR, "end" in RTL.
  SwipeSpec? _specFor(double dx) =>
      (dx > 0) != _rtl ? widget.start : widget.end;

  void _update(DragUpdateDetails d) {
    _settle.stop();
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
    _settleBack();
  }

  void _settleBack() {
    _fired = false;
    _settle.value = _dx;
    _settle.animateTo(0,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic);
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
      onHorizontalDragCancel: _settleBack,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          // Gmail style (#52): a solid pill of the action's color fills the
          // space the row leaves (a small gap apart), so it reads as a second
          // card taking the row's place. Its icon grows up to the threshold
          // and pops past it.
          if (spec != null && _dx.abs() > 2)
            Positioned.fill(
              child: Padding(
                padding: widget.actionInset,
                child: Align(
                  alignment:
                      _dx > 0 ? Alignment.centerLeft : Alignment.centerRight,
                  child: Container(
                    width: (_dx.abs() - 6).clamp(0.0, double.infinity),
                    height: double.infinity,
                    clipBehavior: Clip.antiAlias,
                    decoration: ShapeDecoration(
                        color: spec.color, shape: const StadiumBorder()),
                    // Keeps its size in a thin pill, which clips it until
                    // there's room.
                    child: OverflowBox(
                      minWidth: 0,
                      maxWidth: double.infinity,
                      minHeight: 0,
                      maxHeight: double.infinity,
                      child: AnimatedScale(
                        scale: active ? 1.2 : 1,
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeOutBack,
                        child: Transform.scale(
                          scale: 0.7 +
                              0.3 * (_dx.abs() / _threshold).clamp(0.0, 1.0),
                          child: Icon(spec.icon,
                              size: 26,
                              color: spec.color.computeLuminance() > 0.5
                                  ? Colors.black
                                  : Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Transform.translate(
              offset: Offset(_dx, 0),
              // Always the same tree (switching would rebuild the row).
              child: ColoredBox(
                  color: _dx != 0
                      ? widget.slideColor ?? Colors.transparent
                      : Colors.transparent,
                  child: widget.child)),
        ],
      ),
    );
  }
}
