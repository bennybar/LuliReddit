// Frame timings while scrolling the real feed and a thread, on a device in
// profile mode:
//   flutter drive --profile --no-dds --driver=test_driver/perf_driver.dart \
//     --target=integration_test/scroll_perf_test.dart -d <device>
// Uses the signed-in account on the device; loads a few feed pages. The
// summary is printed to the log ("PERF ...").
import 'dart:ui';

import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:luli_for_reddit/features/feed/post_card.dart';
import 'package:luli_for_reddit/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> waitFor(WidgetTester t, Finder f, {int seconds = 30}) async {
    for (var i = 0; i < seconds * 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
      if (f.evaluate().isNotEmpty) return;
    }
    throw StateError('Timed out waiting for $f');
  }

  // Build / raster times of every frame drawn while [action] runs.
  Future<void> measure(String name, Future<void> Function() action) async {
    final frames = <FrameTiming>[];
    void collect(List<FrameTiming> t) => frames.addAll(t);
    SchedulerBinding.instance.addTimingsCallback(collect);
    await action();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    SchedulerBinding.instance.removeTimingsCallback(collect);
    double ms(Duration d) => d.inMicroseconds / 1000;
    List<double> sorted(Iterable<double> v) => v.toList()..sort();
    String pct(List<double> v, double p) =>
        v.isEmpty ? '-' : v[((v.length - 1) * p).round()].toStringAsFixed(1);
    final build = sorted(frames.map((f) => ms(f.buildDuration)));
    final raster = sorted(frames.map((f) => ms(f.rasterDuration)));
    final total = sorted(frames.map((f) => ms(f.totalSpan)));
    // 120Hz budget is 8.3 ms; 60Hz is 16.7 ms.
    final over8 = total.where((v) => v > 8.4).length;
    final over16 = total.where((v) => v > 16.7).length;
    // ignore: avoid_print
    print('PERF $name frames=${frames.length} '
        'build p50/p90/p99/max=${pct(build, .5)}/${pct(build, .9)}/${pct(build, .99)}/${pct(build, 1)} '
        'raster p50/p90/p99/max=${pct(raster, .5)}/${pct(raster, .9)}/${pct(raster, .99)}/${pct(raster, 1)} '
        'over8.3ms=$over8 over16.7ms=$over16');
  }

  testWidgets('feed and thread scrolling', (t) async {
    app.main();
    await waitFor(t, find.byType(PostCard), seconds: 45);
    await t.pump(const Duration(seconds: 2));
    // Startup prompts (notifications, What's new) would take the flings.
    for (final label in ['Not now', 'Got it']) {
      if (find.text(label).evaluate().isNotEmpty) {
        await t.tap(find.text(label).first);
        await t.pump(const Duration(seconds: 1));
      }
    }
    final feed = find.byType(Scrollable).first;
    await measure('feed', () async {
      for (var i = 0; i < 8; i++) {
        await t.fling(feed, const Offset(0, -900), 2500,
            warnIfMissed: false);
        await t.pump(const Duration(milliseconds: 1500));
      }
    });

    await t.tap(find.byType(PostCard).first, warnIfMissed: false);
    await t.pump(const Duration(seconds: 4));
    final thread = find.byType(Scrollable).last;
    await measure('thread', () async {
      for (var i = 0; i < 6; i++) {
        await t.fling(thread, const Offset(0, -900), 2500,
            warnIfMissed: false);
        await t.pump(const Duration(milliseconds: 1500));
      }
    });
  });
}
