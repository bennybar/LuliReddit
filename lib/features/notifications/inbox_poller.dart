import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../../core/reddit_constants.dart';
import '../../core/storage/secure_store.dart';
import '../auth/auth_repository.dart';
import 'notification_service.dart';

/// Background polling of the Reddit inbox + local notifications.
///
/// We can't use push (that would mean Firebase, which would disqualify the app
/// from F-Droid/IzzyOnDroid), so instead WorkManager wakes us roughly every 15
/// minutes, we fetch `/message/unread`, and fire a local notification for any
/// item we haven't already told the user about. This works for both auth modes
/// (OAuth and the website-session fallback) by reusing [SecureStore] +
/// [AuthRepository] directly — no Riverpod needed in the background isolate.

const String kInboxTaskUnique = 'luli.inbox.poll';
const String kInboxTaskName = 'pollInbox';

/// SharedPreferences keys.
const String kNotifyInboxPref = 'notifyInbox'; // mirrors the Settings flag
const String _kSeenIdsPref = 'notif_seen_ids';

/// WorkManager entry point. Must be a top-level function marked vm:entry-point.
@pragma('vm:entry-point')
void inboxCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await pollInbox(notify: true);
      return true;
    } catch (_) {
      // Returning true avoids WorkManager backoff storms; we'll retry next tick.
      return true;
    }
  });
}

/// Registers the ~15-minute periodic poll (Android). On iOS the cadence is
/// decided by the OS via BGTaskScheduler (see AppDelegate / Info.plist).
Future<void> registerInboxPolling() async {
  await Workmanager().registerPeriodicTask(
    kInboxTaskUnique,
    kInboxTaskName,
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );
}

Future<void> cancelInboxPolling() =>
    Workmanager().cancelByUniqueName(kInboxTaskUnique);

/// One unread item parsed from Reddit's inbox listing.
class _UnreadItem {
  _UnreadItem(this.fullname, this.title, this.body, this.route);
  final String fullname;
  final String title;
  final String body;
  final String? route; // go_router path to deep-link to (null = just open app)
}

/// Fetches unread inbox items and, when [notify] is true, fires a notification
/// for each one not already seen. When [notify] is false it only "primes" the
/// seen set (used when the user first turns the feature on, so we don't dump a
/// notification for every pre-existing unread item).
Future<void> pollInbox({required bool notify}) async {
  final store = SecureStore();
  final items = await _fetchUnread(store);
  if (items == null) return; // not logged in / network error

  final prefs = await SharedPreferences.getInstance();
  final seen = (prefs.getStringList(_kSeenIdsPref) ?? const <String>[]).toSet();

  final fresh = items.where((i) => !seen.contains(i.fullname)).toList();

  if (notify) {
    await NotificationService.instance.init();
    for (final item in fresh) {
      await NotificationService.instance.show(
        id: item.fullname.hashCode & 0x7fffffff,
        title: item.title,
        body: item.body,
        payload: item.route,
      );
    }
  }

  // Remember everything currently unread so we never re-notify, capped so the
  // list can't grow without bound.
  final updated = <String>[
    for (final i in items) i.fullname,
    ...seen.where((s) => items.every((i) => i.fullname != s)),
  ];
  await prefs.setStringList(
      _kSeenIdsPref, updated.take(200).toList(growable: false));
}

/// Returns the current unread items, or null if we can't authenticate.
Future<List<_UnreadItem>?> _fetchUnread(SecureStore store) async {
  final dio = Dio(BaseOptions(validateStatus: (s) => s != null && s < 500));
  final webMode = (await store.authMode) == 'web';

  Response res;
  if (webMode) {
    final cookie = await store.webCookie;
    if (cookie == null || cookie.isEmpty) return null;
    res = await dio.get(
      '${RedditConstants.webApiBase}/message/unread.json',
      queryParameters: {'limit': 25, 'raw_json': 1},
      options: Options(headers: {
        'cookie': cookie,
        'User-Agent': RedditConstants.webUserAgent,
      }),
    );
  } else {
    // Mint a fresh access token from the stored refresh token + client id.
    final token = await AuthRepository(store).refresh();
    if (token == null) return null;
    res = await dio.get(
      '${RedditConstants.oauthApiBase}/message/unread',
      queryParameters: {'limit': 25, 'raw_json': 1},
      options: Options(headers: {
        'Authorization': 'bearer $token',
        'User-Agent': RedditConstants.userAgent(await store.username),
      }),
    );
  }

  if (res.statusCode != 200) return null;
  dynamic body = res.data;
  if (body is String) {
    try {
      body = jsonDecode(body);
    } catch (_) {
      return null;
    }
  }
  final data = body is Map ? body['data'] : null;
  final children = data is Map ? data['children'] : null;
  if (children is! List) return const [];

  final out = <_UnreadItem>[];
  for (final c in children) {
    final d = (c is Map ? c['data'] : null);
    if (d is! Map) continue;
    final fullname = d['name']?.toString();
    if (fullname == null) continue;
    final author = d['author']?.toString() ?? 'Reddit';
    final wasComment = d['was_comment'] == true;
    final subject = d['subject']?.toString() ?? '';
    final linkTitle = d['link_title']?.toString();
    final rawBody = (d['body']?.toString() ?? '').replaceAll('\n', ' ').trim();

    final linkSuffix = linkTitle != null ? ' · $linkTitle' : '';
    final title = wasComment
        ? 'u/$author replied$linkSuffix'
        : (subject.isNotEmpty ? subject : 'Message from u/$author');
    final snippet = rawBody.length > 140
        ? '${rawBody.substring(0, 140)}…'
        : (rawBody.isEmpty ? 'Open Ilay to read' : rawBody);

    // Deep-link target for comment replies/mentions (t1_): jump to the comment.
    String? route;
    final sub = d['subreddit']?.toString();
    final linkId = d['link_id']?.toString(); // t3_<postId>
    if (wasComment &&
        fullname.startsWith('t1_') &&
        sub != null &&
        sub.isNotEmpty &&
        linkId != null &&
        linkId.startsWith('t3_')) {
      route =
          '/comments/$sub/${linkId.substring(3)}?comment=${fullname.substring(3)}';
    }
    out.add(_UnreadItem(fullname, title, snippet, route));
  }
  return out;
}
