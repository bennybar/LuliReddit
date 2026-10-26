import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/motion.dart';
import '../../models/post.dart';
import '../notifications/notification_log.dart';
import '../notifications/notification_service.dart';
import '../settings/settings_controller.dart';

/// A tapped reminder's notification payload: this, then the post's route.
/// It opens the post where you are (not on the Inbox tab).
const reminderPayloadPrefix = 'reminder:';

const _pref = 'postReminders'; // post id → when (epoch millis)
const _postsPref = 'postReminderPosts'; // post id → [subreddit, title]

/// "Remind me about this post": offered (a snackbar action) when you save a
/// post, then a local notification at the time you pick, scheduled with the
/// system (iOS shows it even if Ilay isn't running; no push service).
/// Unsaving cancels it. Pending ones are kept (post id → when) so the post
/// shows it.
class PostReminders extends Notifier<Map<String, int>> {
  Timer? _sweep;

  @override
  Map<String, int> build() {
    ref.onDispose(() => _sweep?.cancel());
    final pending =
        decodeReminders(ref.read(sharedPrefsProvider).getString(_pref));
    // Fired while Ilay wasn't running: logged and dropped once read.
    Future.microtask(_fired);
    return pending;
  }

  void _store(Map<String, int> next) {
    state = next;
    final prefs = ref.read(sharedPrefsProvider);
    prefs.setString(_pref, jsonEncode(next));
    final posts = _posts()..removeWhere((id, _) => !next.containsKey(id));
    prefs.setString(_postsPref, jsonEncode(posts));
  }

  Map<String, dynamic> _posts() {
    try {
      final raw = ref.read(sharedPrefsProvider).getString(_postsPref);
      return raw == null
          ? {}
          : Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  /// Due ones have fired (the system showed them): no longer pending, and in
  /// the notification log. Then waits for the next one to come due.
  Future<void> _fired() async {
    _sweep?.cancel();
    final now = DateTime.now().millisecondsSinceEpoch;
    final due = {
      for (final e in state.entries)
        if (e.value <= now) e.key: e.value
    };
    if (due.isNotEmpty) {
      final posts = _posts();
      final shown = await NotificationService.instance.canNotify();
      final log = NotificationLog(ref.read(sharedPrefsProvider));
      for (final e in due.entries) {
        final p = posts[e.key];
        final sub = p is List && p.isNotEmpty ? '${p[0]}' : null;
        await log.add(NotificationEvent(
          at: e.value,
          account: '',
          source: NotificationEvent.sourceReminder,
          title: sub == null ? 'Reminder' : 'Reminder · r/$sub',
          text: p is List && p.length > 1 ? '${p[1]}' : '',
          outcome: shown
              ? NotificationOutcome.shown
              : NotificationOutcome.notShown,
          subreddit: sub,
          postId: sub == null ? null : e.key,
        ));
      }
      _store({...state}..removeWhere((id, _) => due.containsKey(id)));
    }
    if (state.isEmpty) return;
    final next = state.values.reduce((a, b) => a < b ? a : b);
    // Timers pause with the app, so this also runs on return from the
    // background.
    _sweep = Timer(
        Duration(milliseconds: next - DateTime.now().millisecondsSinceEpoch),
        _fired);
  }

  Future<void> schedule(Post post, DateTime at) async {
    await NotificationService.instance.schedule(
      id: reminderNotificationId(post.id),
      title: 'Reminder · r/${post.subreddit}',
      body: post.title,
      at: at,
      payload:
          '$reminderPayloadPrefix/comments/${post.subreddit}/${post.id}',
    );
    final posts = _posts()..[post.id] = [post.subreddit, post.title];
    ref.read(sharedPrefsProvider).setString(_postsPref, jsonEncode(posts));
    _store({...state, post.id: at.millisecondsSinceEpoch});
    _fired();
  }

  /// Unsaved: drop its reminder, if any.
  void cancel(String postId) {
    if (!state.containsKey(postId)) return;
    NotificationService.instance.cancel(reminderNotificationId(postId));
    _store({...state}..remove(postId));
  }
}

final postRemindersProvider =
    NotifierProvider<PostReminders, Map<String, int>>(PostReminders.new);

/// The stored pending reminders; empty when missing or unreadable.
Map<String, int> decodeReminders(String? raw) {
  if (raw == null) return {};
  try {
    return {
      for (final e in (jsonDecode(raw) as Map).entries)
        if (e.value is num) '${e.key}': (e.value as num).toInt()
    };
  } catch (_) {
    return {};
  }
}

/// A stable notification id per post (Kotlin's `"reminder_$id".hashCode()`,
/// non-negative): Dart's own String.hashCode changes between runs, and a
/// reminder must still be cancellable after a restart.
int reminderNotificationId(String postId) {
  var h = 0;
  for (final c in 'reminder_$postId'.codeUnits) {
    h = (31 * h + c) & 0xffffffff;
  }
  return h & 0x7fffffff;
}

/// "today at 14:30", "tomorrow at 09:00", "Tue at 18:05", "on Oct 25 at
/// 10:00"; [use24h] as the system clock.
String whenLabel(DateTime at, DateTime now, {required bool use24h}) {
  if (!at.isAfter(now)) return 'any moment now';
  final day = DateTime(at.year, at.month, at.day);
  final today = DateTime(now.year, now.month, now.day);
  final days = DateTime.utc(day.year, day.month, day.day)
      .difference(DateTime.utc(today.year, today.month, today.day))
      .inDays;
  final time = (use24h ? DateFormat.Hm() : DateFormat.jm()).format(at);
  final date = switch (days) {
    0 => 'today',
    1 => 'tomorrow',
    < 7 => DateFormat.E().format(at),
    _ => 'on ${DateFormat('MMM d').format(at)}',
  };
  return '$date at $time';
}

class _Choice {
  const _Choice(this.label, this.hours);
  final String label;
  final int hours;
}

const _choices = [
  _Choice('In 1 hour', 1),
  _Choice('In 3 hours', 3),
  _Choice('Tomorrow', 24),
  _Choice('In 3 days', 72),
  _Choice('In a week', 24 * 7),
];

const _cancelIt = Object();

/// Just saved [post]: a quiet "Remind me" next to "Saved".
void offerReminder(BuildContext context, Post post) {
  final nav = Navigator.of(context, rootNavigator: true);
  final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    content: const Text('Saved'),
    action: SnackBarAction(
        label: 'Remind me', onPressed: () => _pick(nav, messenger, post)),
  ));
}

/// Tapped a post's reminder line: pick a new time, or cancel it.
void manageReminder(BuildContext context, Post post) {
  final existing = ProviderScope.containerOf(context, listen: false)
      .read(postRemindersProvider)[post.id];
  _pick(Navigator.of(context, rootNavigator: true),
      ScaffoldMessenger.of(context), post,
      existing: existing);
}

// Runs from a snackbar action, after the card that offered it may be gone:
// so it works off the root navigator.
Future<void> _pick(
    NavigatorState nav, ScaffoldMessengerState messenger, Post post,
    {int? existing}) async {
  void say(String msg) =>
      messenger.showSnackBar(SnackBar(content: Text(msg)));
  final ctx = nav.context;
  bool use24h() => MediaQuery.alwaysUse24HourFormatOf(ctx);
  final title = existing == null
      ? 'Remind me about this post'
      : 'Reminder ${whenLabel(DateTime.fromMillisecondsSinceEpoch(existing),
          DateTime.now(), use24h: use24h())}';
  final picked = await showModalBottomSheet<Object>(
    context: ctx,
    sheetAnimationStyle: sheetMotion,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                title,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            for (final c in _choices)
              ListTile(
                leading: const Icon(Icons.schedule_rounded),
                title: Text(c.label),
                onTap: () => Navigator.pop(sheet, c),
              ),
            if (existing != null)
              ListTile(
                leading: const Icon(Icons.notifications_off_rounded),
                title: const Text('Cancel reminder'),
                onTap: () => Navigator.pop(sheet, _cancelIt),
              ),
          ],
        ),
      ),
    ),
  );
  if (picked == null || !ctx.mounted) return;
  final reminders = ProviderScope.containerOf(ctx, listen: false)
      .read(postRemindersProvider.notifier);
  if (identical(picked, _cancelIt)) {
    reminders.cancel(post.id);
    say('Reminder cancelled');
    return;
  }
  final choice = picked as _Choice;
  // Reminders need notifications allowed.
  if (!await NotificationService.instance.requestPermission()) {
    say("Allow Ilay's notifications to get reminders");
    return;
  }
  final at = DateTime.now().add(Duration(hours: choice.hours));
  try {
    await reminders.schedule(post, at);
  } catch (_) {
    say("Couldn't set the reminder");
    return;
  }
  if (!ctx.mounted) return;
  say("I'll remind you ${whenLabel(at, DateTime.now(), use24h: use24h())}");
}
