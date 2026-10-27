import 'package:aptabase_flutter/aptabase_flutter.dart';

/// Privacy-friendly, anonymous usage analytics via Aptabase.
///
/// No ad IDs, no personal data — just anonymous sessions plus the OS/app
/// version and the few events we explicitly track. Completely disabled (a
/// no-op) until [_appKey] is set, so the open-source build ships clean and
/// F-Droid stays happy.
class Analytics {
  /// Paste your Aptabase App Key here, e.g. "A-EU-1234567890".
  /// Leave empty to keep analytics fully disabled.
  static const String _appKey = 'A-US-2578531885';

  static bool get enabled => _appKey.isNotEmpty;

  static Future<void> init() async {
    if (!enabled) return;
    await Aptabase.init(_appKey);
  }

  /// Records an anonymous event (no-op when disabled).
  static void track(String event, [Map<String, dynamic>? props]) {
    if (!enabled) return;
    Aptabase.instance.trackEvent(event, props);
  }
}
