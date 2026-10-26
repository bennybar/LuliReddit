// Frame timings while scrolling the real feed and a thread, on a device in
// profile mode:
//   flutter drive --profile --driver=test_driver/perf_driver.dart \
//     --target=integration_test/scroll_perf_test.dart -d <device>
// Uses the signed-in account on the device; loads a few feed pages.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:luli_for_reddit/features/feed/post_card.dart';
import 'package:luli_for_reddit/main.dart' as app;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> waitFor(WidgetTester t, Finder f, {int seconds = 30}) async {
    for (var i = 0; i < seconds * 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
      if (f.evaluate().isNotEmpty) return;
    }
    throw StateError('Timed out waiting for $f');
  }

  testWidgets('feed and thread scrolling', (t) async {
    app.main();
    await waitFor(t, find.byType(PostCard), seconds: 45);
    await t.pump(const Duration(seconds: 2));
    final feed = find.byType(Scrollable).first;

    await binding.traceAction(() async {
      for (var i = 0; i < 6; i++) {
        await t.fling(feed, const Offset(0, -900), 2500);
        await t.pumpAndSettle(const Duration(milliseconds: 100));
      }
      for (var i = 0; i < 3; i++) {
        await t.fling(feed, const Offset(0, 900), 2500);
        await t.pumpAndSettle(const Duration(milliseconds: 100));
      }
    }, reportKey: 'feed_scroll');

    await t.tap(find.byType(PostCard).first);
    await t.pump(const Duration(seconds: 3));
    final thread = find.byType(Scrollable).last;
    await binding.traceAction(() async {
      for (var i = 0; i < 5; i++) {
        await t.fling(thread, const Offset(0, -900), 2500);
        await t.pumpAndSettle(const Duration(milliseconds: 100));
      }
    }, reportKey: 'thread_scroll');
  });
}
