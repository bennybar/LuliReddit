import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luli_for_reddit/features/settings/settings_controller.dart';
import 'package:luli_for_reddit/features/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> open(WidgetTester t, {String? section}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await t.binding.setSurfaceSize(const Size(800, 6000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: MaterialApp(home: SettingsScreen(section: section)),
    ));
    await t.pump();
  }

  testWidgets('the main page lists categories, not settings', (t) async {
    await open(t);
    for (final title in [
      'Feed',
      'Appearance',
      'Posts & comments',
      'Media',
      'Notifications',
      'Translation',
      'AI summaries',
      'Data & storage',
      'Account & keys',
      'Power-user features',
      'About',
    ]) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    expect(find.text('Post display'), findsNothing);
    expect(find.text('Search settings'), findsOneWidget);
  });

  testWidgets('search finds settings across every category', (t) async {
    await open(t);
    await t.enterText(find.byType(TextField), 'post display');
    await t.pump();
    expect(find.text('Post display'), findsOneWidget);
    expect(find.text('Appearance'), findsNothing);
    await t.enterText(find.byType(TextField), 'top bar');
    await t.pump();
    expect(find.text('Top bar'), findsOneWidget);
  });

  testWidgets('a category shows only its own settings', (t) async {
    await open(t, section: 'Feed');
    expect(find.text('Post display'), findsOneWidget);
    expect(find.text('Top bar'), findsNothing);
    expect(find.text('Search settings'), findsNothing);
  });

  testWidgets('every category has settings', (t) async {
    for (final (section, setting) in [
      ('Appearance', 'Top bar'),
      ('Posts & comments', 'Comment style'),
      ('Translation', 'Translation service'),
      ('Data & storage', 'Track history'),
      ('About', 'Content & conduct policy'),
    ]) {
      await open(t, section: section);
      expect(find.text(setting), findsOneWidget, reason: section);
      await t.pumpWidget(const SizedBox());
    }
  });
}
