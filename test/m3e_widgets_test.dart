import 'dart:ui' show CheckedState, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luli_for_reddit/core/theme/app_theme.dart';
import 'package:luli_for_reddit/core/theme/motion.dart';
import 'package:luli_for_reddit/core/widgets/connected_choice.dart';
import 'package:luli_for_reddit/core/widgets/loading.dart';
import 'package:luli_for_reddit/core/widgets/pick_one_menu.dart';
import 'package:luli_for_reddit/core/widgets/toggles.dart';
import 'package:luli_for_reddit/features/media/gallery_carousel.dart';

Widget app(Widget child, {bool reduceMotion = false}) => MaterialApp(
      theme: AppTheme.light(null),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Scaffold(body: Center(child: child)),
      ),
    );

SemanticsData semanticsOf(WidgetTester t, Finder f) =>
    t.getSemantics(f).getSemanticsData();

void main() {
  group('Loading', () {
    testWidgets('morphs as a loading spinner for screen readers',
        (t) async {
      final h = t.ensureSemantics();
      await t.pumpWidget(app(const Loading()));
      await t.pump(const Duration(milliseconds: 700));
      expect(t.getSize(find.byType(Loading)), const Size(48, 48));
      final s = semanticsOf(t, find.byType(Loading));
      expect(s.role, SemanticsRole.loadingSpinner);
      expect(s.label, 'Loading');
      // It keeps animating while shown.
      expect(t.binding.transientCallbackCount, greaterThan(0));
      h.dispose();
    });

    testWidgets('a determinate one is a progress bar', (t) async {
      final h = t.ensureSemantics();
      await t.pumpWidget(app(const Loading(value: 0.5)));
      final s = semanticsOf(t, find.byType(Loading));
      expect(s.role, SemanticsRole.progressBar);
      expect(s.value, '50');
      expect(t.binding.transientCallbackCount, 0);
      h.dispose();
    });

    testWidgets('stays still when reduce motion is on', (t) async {
      await t.pumpWidget(app(const Loading(), reduceMotion: true));
      expect(t.binding.transientCallbackCount, 0);
    });

    testWidgets('stops in a hidden IndexedStack tab', (t) async {
      await t.pumpWidget(app(const IndexedStack(
          index: 0, children: [SizedBox(), Loading()])));
      expect(t.binding.transientCallbackCount, 0);
      await t.pumpWidget(app(const IndexedStack(
          index: 1, children: [SizedBox(), Loading()])));
      expect(t.binding.transientCallbackCount, greaterThan(0));
    });

    testWidgets('onContent takes the button content colour', (t) async {
      await t.pumpWidget(app(
          FilledButton.icon(
              onPressed: null,
              icon: const Loading.onContent(),
              label: const Text('Send'))));
      expect(t.getSize(find.byType(Loading)), const Size(24, 24));
    });
  });

  group('WavyProgress', () {
    testWidgets('reports its value as a progress bar', (t) async {
      final h = t.ensureSemantics();
      await t.pumpWidget(app(const SizedBox(
          width: 200, child: WavyProgress(value: 0.25, label: 'Saving'))));
      final s = semanticsOf(t, find.byType(WavyProgress));
      expect(s.role, SemanticsRole.progressBar);
      expect(s.value, '25');
      expect(s.label, 'Saving');
      h.dispose();
    });

    testWidgets('the wave holds still when reduce motion is on', (t) async {
      await t.pumpWidget(app(const SizedBox(width: 200, child: WavyProgress()),
          reduceMotion: true));
      expect(t.binding.transientCallbackCount, 0);
    });
  });

  group('RefreshBox', () {
    testWidgets('a pull refreshes and shows the loading indicator',
        (t) async {
      var refreshed = 0;
      await t.pumpWidget(app(RefreshBox(
        onRefresh: () async {
          refreshed++;
          await Future<void>.delayed(const Duration(milliseconds: 500));
        },
        child: ListView(children: const [SizedBox(height: 2000)]),
      )));
      expect(find.byType(Loading), findsNothing);
      await t.fling(find.byType(ListView), const Offset(0, 400), 1000);
      await t.pump();
      expect(find.byType(Loading), findsOneWidget);
      await t.pump(const Duration(milliseconds: 300));
      expect(refreshed, 1);
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(seconds: 1));
      expect(find.byType(Loading), findsNothing);
    });

    testWidgets('show() refreshes without a pull', (t) async {
      final key = GlobalKey<RefreshBoxState>();
      var refreshed = 0;
      await t.pumpWidget(app(RefreshBox(
        key: key,
        onRefresh: () async => refreshed++,
        child: ListView(children: const [SizedBox(height: 2000)]),
      )));
      key.currentState!.show();
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(refreshed, 1);
      await t.pump(const Duration(seconds: 1));
    });
  });

  group('toggles', () {
    testWidgets('ToggleButton reads as on/off and flips', (t) async {
      final h = t.ensureSemantics();
      var on = false;
      await t.pumpWidget(app(StatefulBuilder(
        builder: (_, set) => ToggleButton(
          checked: on,
          onChanged: (v) => set(() => on = v),
          tonal: true,
          child: Text(on ? 'Joined' : 'Join'),
        ),
      )));
      expect(t.getSemantics(find.byType(ToggleButton)),
          matchesSemantics(
              label: 'Join',
              isButton: true,
              hasToggledState: true,
              isToggled: false,
              hasEnabledState: true,
              isEnabled: true,
              hasTapAction: true,
              isFocusable: true,
              hasFocusAction: true));
      await t.tap(find.text('Join'));
      await t.pumpAndSettle();
      expect(on, isTrue);
      expect(semanticsOf(t, find.byType(ToggleButton)).flagsCollection
          .isToggled, Tristate.isTrue);
      h.dispose();
    });

    testWidgets('ToggleIcon reads its description and state', (t) async {
      final h = t.ensureSemantics();
      var saved = true;
      await t.pumpWidget(app(StatefulBuilder(
        builder: (_, set) => ToggleIcon(
          checked: saved,
          onChanged: (v) => set(() => saved = v),
          on: Icons.bookmark,
          off: Icons.bookmark_border,
          description: 'Save',
        ),
      )));
      final s = semanticsOf(t, find.byType(ToggleIcon));
      expect(s.label, 'Save');
      expect(s.flagsCollection.isToggled, Tristate.isTrue);
      expect(find.byIcon(Icons.bookmark), findsOneWidget);
      await t.tap(find.byType(ToggleIcon));
      await t.pumpAndSettle();
      expect(saved, isFalse);
      expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
      h.dispose();
    });
  });

  testWidgets('ConnectedChoice is a radio group', (t) async {
    final h = t.ensureSemantics();
    await t.pumpWidget(app(ConnectedChoice<int>(
      options: const [(0, 'Hot'), (1, 'New')],
      selected: 1,
      onSelect: (_) {},
    )));
    final group = semanticsOf(t, find.byType(ConnectedChoice<int>));
    expect(group.role, SemanticsRole.radioGroup);
    final fresh = semanticsOf(t, find.text('New'));
    expect(fresh.flagsCollection.isInMutuallyExclusiveGroup, isTrue);
    expect(fresh.flagsCollection.isChecked, CheckedState.isTrue);
    final hot = semanticsOf(t, find.text('Hot'));
    expect(hot.flagsCollection.isChecked, CheckedState.isFalse);
    h.dispose();
  });

  testWidgets('pickOneMenu marks the current choice and returns a pick',
      (t) async {
    final h = t.ensureSemantics();
    String? picked;
    await t.pumpWidget(app(PopupMenuButton<String>(
      onSelected: (v) => picked = v,
      itemBuilder: (_) =>
          pickOneMenu(const [('hot', 'Hot'), ('new', 'New')], 'new'),
    )));
    await t.tap(find.byType(PopupMenuButton<String>));
    await t.pumpAndSettle();
    final current = semanticsOf(t, find.text('New'));
    expect(current.role, SemanticsRole.menuItemRadio);
    expect(current.flagsCollection.isChecked, CheckedState.isTrue);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    await t.tap(find.text('Hot'));
    await t.pumpAndSettle();
    expect(picked, 'hot');
    h.dispose();
  });

  test('Spring curves end on target; spatial ones overshoot', () {
    for (final s in [Motion.fastSpatial, Motion.defaultEffects]) {
      expect(s.transform(0), 0);
      expect(s.transform(1), 1);
    }
    double peak(Spring s) => [
          for (var i = 0; i <= 100; i++) s.transform(i / 100)
        ].reduce((a, b) => a > b ? a : b);
    expect(peak(Motion.fastSpatial), greaterThan(1.05));
    expect(peak(Motion.defaultEffects), lessThanOrEqualTo(1));
  });

  test('a fast carousel fling skips several images, a slow one snaps',
      () {
    const p = MultiBrowsePhysics(0.5); // 200px items in a 400px carousel
    final tol = Tolerance(velocity: 1, distance: 0.01);
    final far = p.snapTarget(0, 4000, 400, 0, 2000, tol);
    expect(far % 200, 0);
    expect(far, greaterThanOrEqualTo(600));
    expect(p.snapTarget(260, 0, 400, 0, 2000, tol), 200);
    expect(p.snapTarget(0, 20000, 400, 0, 1000, tol), 1000);
  });
}
