import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luli_for_reddit/core/widgets/collapsing_fab.dart';

void main() {
  testWidgets('hides its label when collapsed, and taps either way',
      (t) async {
    var taps = 0;
    Widget fab(bool expanded) => MaterialApp(
          home: Scaffold(
            body: Center(
              child: CollapsingFab(
                icon: Icons.edit_rounded,
                label: 'New post',
                expanded: expanded,
                onTap: () => taps++,
              ),
            ),
          ),
        );
    await t.pumpWidget(fab(true));
    expect(find.text('New post'), findsOneWidget);
    final wide = t.getSize(find.byType(CollapsingFab)).width;

    await t.pumpWidget(fab(false));
    await t.pumpAndSettle();
    final label = t.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
    expect(label.opacity, 0);
    expect(t.getSize(find.byType(CollapsingFab)).width, lessThan(wide));

    await t.tap(find.byType(CollapsingFab));
    expect(taps, 1);
  });
}
