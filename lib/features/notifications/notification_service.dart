import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Required top-level handler for taps that arrive while the app is backgrounded
/// (no-op — routing happens via the launch details / foreground handler).
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {}

/// Thin wrapper around [FlutterLocalNotificationsPlugin] for the one thing we
/// use it for: telling the user about new inbox replies & messages found by the
/// background poller. No Firebase / FCM — everything is local, so the app stays
/// clean for F-Droid / IzzyOnDroid.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _inited = false;

  /// Set by the app: routes a tapped notification's payload (a go_router path).
  static void Function(String route)? onSelectRoute;

  static const String _channelId = 'inbox';
  static const String _channelName = 'Inbox replies & messages';
  static const String _channelDesc =
      'New replies, mentions and private messages on Reddit.';

  /// Safe to call repeatedly (runs once). Must be called before [show] — both in
  /// the UI isolate and inside the background poller isolate.
  Future<void> init() async {
    if (_inited) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      // We request permission explicitly via [requestPermission] instead.
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: darwin),
      onDidReceiveNotificationResponse: (r) {
        final p = r.payload;
        if (p != null && p.isNotEmpty) onSelectRoute?.call(p);
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
    // Pre-create the Android channel so importance/sound are correct.
    final android13 = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android13?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.high,
      ),
    );
    _inited = true;
  }

  /// Requests OS notification permission (Android 13+ / iOS). Returns whether it
  /// was granted (best-effort; null result is treated as granted).
  Future<bool> requestPermission() async {
    await init();
    if (Platform.isAndroid) {
      final impl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return (await impl?.requestNotificationsPermission()) ?? true;
    }
    if (Platform.isIOS) {
      final impl = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      return (await impl?.requestPermissions(
              alert: true, badge: true, sound: true)) ??
          true;
    }
    return true;
  }

  Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    await init();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
        styleInformation: BigTextStyleInformation(''),
      ),
      iOS: DarwinNotificationDetails(),
    );
    await _plugin.show(id, title, body, details, payload: payload);
  }

  /// If the app was launched by tapping a notification, route to its payload.
  /// Call once after the router/navigator is ready.
  Future<void> handleLaunch() async {
    await init();
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp ?? false) {
      final p = details!.notificationResponse?.payload;
      if (p != null && p.isNotEmpty) onSelectRoute?.call(p);
    }
  }
}
