import 'package:flutter_driver/flutter_driver.dart' as driver;
import 'package:integration_test/integration_test_driver.dart';

// Writes a timeline summary per traced action to build/<key>.timeline_summary.json.
Future<void> main() => integrationDriver(
      responseDataCallback: (data) async {
        if (data == null) return;
        for (final key in ['feed_scroll', 'thread_scroll']) {
          if (data[key] == null) continue;
          final timeline = driver.Timeline.fromJson(data[key] as Map<String, dynamic>);
          await driver.TimelineSummary.summarize(timeline)
              .writeTimelineToFile(key, pretty: true, includeSummary: true);
        }
      },
    );
