import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../../core/reddit_constants.dart';
import '../../core/storage/secure_store.dart';
import '../auth/auth_repository.dart';
import 'notification_log.dart';
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

/// One unread inbox item, ready for a notification.
class UnreadItem {
  const UnreadItem(this.fullname, this.title, this.body,
      {this.post, this.messageFullname});
  final String fullname;
  final String title;
  final String body;

  /// (subreddit, postId, commentId) for comment replies / mentions.
  final (String, String, String)? post;

  /// Thread to open for private messages.
  final String? messageFullname;

  /// go_router path to deep-link to (null = just open the app).
  String? get route {
    final p = post;
    if (p != null) return '/comments/${p.$1}/${p.$2}?comment=${p.$3}';
    final m = messageFullname;
    return m == null ? null : '/message?id=$m';
  }
}

/// One unread item parsed from Reddit's raw inbox listing (`data` of a
/// child), or null.
UnreadItem? parseUnread(Object? d) {
  if (d is! Map) return null;
  final fullname = d['name']?.toString();
  if (fullname == null) return null;
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
  final sub = d['subreddit']?.toString();
  final linkId = d['link_id']?.toString(); // t3_<postId>
  final post = wasComment &&
          fullname.startsWith('t1_') &&
          sub != null &&
          sub.isNotEmpty &&
          linkId != null &&
          linkId.startsWith('t3_')
      ? (sub, linkId.substring(3), fullname.substring(3))
      : null;
  // Messages open their conversation (by its first message when known).
  final message = !wasComment && fullname.startsWith('t4_')
      ? (d['first_message_name']?.toString() ?? fullname)
      : null;
  return UnreadItem(fullname, title, snippet,
      post: post, messageFullname: message);
}

/// Checks the inbox and, when [notify] is true, fires a notification for
/// each item not already seen; returns the items it showed one for. When
/// [notify] is false it only "primes" the seen set (used when the user first
/// turns the feature on, so we don't dump a notification for every
/// pre-existing unread item). Each check is recorded for Settings →
/// Notification activity.
Future<List<UnreadItem>> pollInbox({required bool notify}) async {
  final store = SecureStore();
  final prefs = await SharedPreferences.getInstance();
  // The UI isolate and the background check share these prefs.
  await prefs.reload();
  final log = NotificationLog(prefs);
  // Per account: the polled inbox is the active account's, so one shared
  // list made every switch notify for all of the other account's unread. An
  // account's first check only primes its list (no burst of old items).
  final user = (await store.username) ?? '';
  final key = user.isEmpty
      ? _kSeenIdsPref
      : '${_kSeenIdsPref}_${user.toLowerCase()}';
  if (key != _kSeenIdsPref &&
      !prefs.containsKey(key) &&
      prefs.containsKey(_kSeenIdsPref)) {
    // A list from before accounts were part of the key: this account's.
    await prefs.setStringList(
        key, prefs.getStringList(_kSeenIdsPref) ?? const []);
    await prefs.remove(_kSeenIdsPref);
  }
  final primed = prefs.containsKey(key);
  final seen = (prefs.getStringList(key) ?? const <String>[]).toSet();

  final items = await _fetchUnread(store, seen);
  if (items == null) {
    // Not logged in / network error.
    await log.checked("Couldn't check: offline, or not signed in");
    return const [];
  }
  // The account changed meanwhile: don't notify or record one account's
  // items as the other's.
  if (((await store.username) ?? '') != user) return const [];

  final fresh = items.where((i) => !seen.contains(i.fullname)).toList();
  final shown = <UnreadItem>[];
  if (notify && primed) {
    await NotificationService.instance.init();
    for (final item in fresh) {
      final ok = await NotificationService.instance.show(
        id: item.fullname.hashCode & 0x7fffffff,
        title: item.title,
        body: item.body,
        payload: item.route,
      );
      if (ok) shown.add(item);
      await log.add(NotificationEvent(
        at: DateTime.now().millisecondsSinceEpoch,
        account: user,
        title: item.title,
        text: item.body,
        outcome: ok ? NotificationOutcome.shown : NotificationOutcome.notShown,
        subreddit: item.post?.$1,
        postId: item.post?.$2,
        commentId: item.post?.$3,
        messageFullname: item.messageFullname,
      ));
    }
  }
  await log.checked(!primed
      ? 'First check for u/$user: ${items.length} unread (not notified)'
      : fresh.isEmpty
          ? '${items.length} unread, nothing new'
          : !notify
              ? '${fresh.length} new (not notified: checked from the app)'
              : '${fresh.length} new, ${shown.length} notified');

  // Remember everything currently unread so we never re-notify, capped so the
  // list can't grow without bound.
  final current = {for (final i in items) i.fullname};
  final updated = <String>[
    for (final i in items) i.fullname,
    ...seen.where((s) => !current.contains(s)),
  ];
  await prefs.setStringList(key, updated.take(200).toList(growable: false));
  return shown;
}

/// The current unread items, or null if we can't authenticate / reach
/// Reddit. Reads past the first 25 while every item on a page is new (a burst
/// between checks), up to 100: older new ones would otherwise never notify.
Future<List<UnreadItem>?> _fetchUnread(
    SecureStore store, Set<String> seen) async {
  try {
    if ((await store.username ?? '').isEmpty) return null;
    final dio = Dio(BaseOptions(validateStatus: (s) => s != null && s < 500));
    final webMode = (await store.authMode) == 'web';
    final String url;
    final Map<String, String> headers;
    if (webMode) {
      final cookie = await store.webCookie;
      if (cookie == null || cookie.isEmpty) return null;
      url = '${RedditConstants.webApiBase}/message/unread.json';
      headers = {
        'cookie': cookie,
        'User-Agent': RedditConstants.webUserAgent,
      };
    } else {
      if ((await store.authMode) == 'anon') return null;
      // Mint a fresh access token from the stored refresh token + client id.
      final token = await AuthRepository(store).refresh();
      if (token == null) return null;
      url = '${RedditConstants.oauthApiBase}/message/unread';
      headers = {
        'Authorization': 'bearer $token',
        'User-Agent': RedditConstants.userAgent(await store.username),
      };
    }

    final out = <UnreadItem>[];
    String? after;
    for (var page = 0; page < 4; page++) {
      final res = await dio.get(url,
          queryParameters: {
            'limit': 25,
            'raw_json': 1,
            if (after != null) 'after': after,
          },
          options: Options(headers: headers));
      if (res.statusCode != 200) return page == 0 ? null : out;
      dynamic body = res.data;
      if (body is String) body = jsonDecode(body);
      final data = body is Map ? body['data'] : null;
      final children = data is Map ? data['children'] : null;
      if (children is! List) return out;
      final items = [
        for (final c in children)
          if (parseUnread(c is Map ? c['data'] : null) case final i?) i
      ];
      out.addAll(items);
      after = data['after'] as String?;
      if (after == null ||
          after.isEmpty ||
          items.length < 25 ||
          items.any((i) => seen.contains(i.fullname))) {
        return out;
      }
    }
    return out;
  } catch (_) {
    return null;
  }
}
