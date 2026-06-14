import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'app.dart';
import 'core/analytics.dart';
import 'core/storage/secure_store.dart';
import 'features/notifications/inbox_poller.dart';
import 'features/settings/settings_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  await Analytics.init();

  // Anonymous: which login method this install uses (api = official OAuth key,
  // website = the no-API-key/"Hydra" session, or logged_out).
  final store = SecureStore();
  final username = await store.username;
  final loginMethod = (username == null || username.isEmpty)
      ? 'logged_out'
      : (await store.authMode) == 'web'
          ? 'website'
          : 'api';
  Analytics.track('app_started', {'login_method': loginMethod});

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
