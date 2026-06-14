import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'app.dart';
import 'core/analytics.dart';
import 'features/notifications/inbox_poller.dart';
import 'features/settings/settings_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  await Analytics.init();
  Analytics.track('app_started');

  // Background inbox notifications (opt-in). Initializing WorkManager is cheap;
  // we only register the periodic poll if the user has turned it on.
  await Workmanager().initialize(inboxCallbackDispatcher);
  if (prefs.getBool(kNotifyInboxPref) ?? false) {
    await registerInboxPolling();
  }

  runApp(
    ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: const LuliApp(),
    ),
  );
}
