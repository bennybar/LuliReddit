import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luli_for_reddit/features/feed/swipe_actions.dart';

void main() {
  Future<List<String>> swipe(WidgetTester t, TextDirection dir, double dx,
      {bool endSide = true}) async {
    final fired = <String>[];
    await t.pumpWidget(Directionality(
      textDirection: dir,
      child: SwipeActions(
        start: SwipeSpec(Icons.add, Colors.green, () => fired.add('start')),
        end: endSide
            ? SwipeSpec(Icons.remove, Colors.red, () => fired.add('end'))
            : null,
        child: const SizedBox(width: 300, height: 80),
      ),
    ));
    await t.drag(find.byType(SizedBox), Offset(dx, 0));
    await t.pumpAndSettle();
    return fired;
  }

  testWidgets('LTR: right = start, left = end', (t) async {
    expect(await swipe(t, TextDirection.ltr, 120), ['start']);
    expect(await swipe(t, TextDirection.ltr, -120), ['end']);
  });

  testWidgets('RTL mirrors the directions', (t) async {
    expect(await swipe(t, TextDirection.rtl, -120), ['start']);
    expect(await swipe(t, TextDirection.rtl, 120), ['end']);
  });

  testWidgets('a side with no action does nothing', (t) async {
    expect(await swipe(t, TextDirection.ltr, -120, endSide: false), isEmpty);
  });
}
