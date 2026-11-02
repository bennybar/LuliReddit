import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luli_for_reddit/core/widgets/collapsing_fab.dart';

void main() {
  testWidgets('shows its label only while expanded, and taps either way',
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
    expect(find.text('New post'), findsNothing);
    expect(t.getSize(find.byType(CollapsingFab)).width, lessThan(wide));

    await t.tap(find.byType(CollapsingFab));
    expect(taps, 1);
  });
}
