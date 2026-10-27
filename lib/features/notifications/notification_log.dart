import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// What came of one notification.
enum NotificationOutcome {
  shown('Notified', true),
  notShown("Not shown: Ilay's notifications are off or blocked", false);

  const NotificationOutcome(this.label, this.ok);
  final String label;
  final bool ok;
}

/// One notification Ilay handled: what came in and what it did with it.
class NotificationEvent {
  const NotificationEvent({
    required this.at,
    required this.account,
    required this.title,
    required this.text,
    required this.outcome,
    this.source = sourceInbox,
    this.subreddit,
    this.postId,
    this.commentId,
    this.messageFullname,
  });

  /// Epoch millis.
  final int at;
  final String account;
  final String title;
  final String text;
  final NotificationOutcome outcome;

  /// [sourceInbox]: Ilay's own inbox check; [sourceReminder]: a post
  /// reminder.
  final String source;
  static const sourceInbox = 'inbox', sourceReminder = 'reminder';

  /// Where it opens: a reply / mention (subreddit, post, comment) or a
  /// message thread.
  final String? subreddit;
  final String? postId;
  final String? commentId;
  final String? messageFullname;

  /// The route it opens, or null.
  String? get route {
    if (subreddit != null && postId != null) {
      return '/comments/$subreddit/$postId'
          '${commentId != null ? '?comment=$commentId' : ''}';
    }
    if (messageFullname != null) return '/message?id=$messageFullname';
    return null;
  }

  // Same fields as the Kotlin build's log.
  Map<String, dynamic> toJson() => {
        'at': at,
        'acct': account,
        'src': source,
        'title': title,
        'text': text,
        'out': switch (outcome) {
          NotificationOutcome.shown => 'SHOWN',
          NotificationOutcome.notShown => 'NOT_SHOWN',
        },
        if (subreddit != null) 'sub': subreddit,
        if (postId != null) 'post': postId,
        if (commentId != null) 'comment': commentId,
        if (messageFullname != null) 'msg': messageFullname,
      };

  static NotificationEvent? fromJson(Object? j) {
    if (j is! Map) return null;
    final at = (j['at'] as num?)?.toInt();
    final outcome = switch (j['out']) {
      'SHOWN' => NotificationOutcome.shown,
      'NOT_SHOWN' => NotificationOutcome.notShown,
      _ => null,
    };
    if (at == null || outcome == null) return null;
    String? s(String k) => j[k] is String ? j[k] as String : null;
    return NotificationEvent(
      at: at,
      account: s('acct') ?? '',
      title: s('title') ?? '',
      text: s('text') ?? '',
      outcome: outcome,
      source: s('src') ?? sourceInbox,
      subreddit: s('sub'),
      postId: s('post'),
      commentId: s('comment'),
      messageFullname: s('msg'),
    );
  }
}

/// The last notifications Ilay showed or couldn't show (Settings →
/// Notification activity), plus the last inbox check: so a missed one can be
/// found and opened, and it's clear why. On this device only, all accounts
/// (each entry names its account). Written by the background check too, so
/// readers reload the prefs first.
class NotificationLog {
  NotificationLog(this._prefs);
  final SharedPreferences _prefs;

  static const _key = 'notification_log';
  static const _checkKey = 'notification_last_check';
  static const _max = 50;

  List<NotificationEvent> events() {
    try {
      final raw = _prefs.getString(_key);
      if (raw == null) return const [];
      return [
        for (final j in jsonDecode(raw) as List)
          if (NotificationEvent.fromJson(j) case final e?) e
      ];
    } catch (_) {
      return const [];
    }
  }

  /// The last inbox check: when (epoch millis), and what came of it.
  (int, String)? lastCheck() {
    final raw = _prefs.getString(_checkKey);
    if (raw == null) return null;
    final i = raw.indexOf('|');
    final at = int.tryParse(i < 0 ? raw : raw.substring(0, i));
    return at == null ? null : (at, i < 0 ? '' : raw.substring(i + 1));
  }

  Future<void> add(NotificationEvent e) => _prefs.setString(
      _key,
      jsonEncode(
          [for (final x in [e, ...events()].take(_max)) x.toJson()]));

  Future<void> checked(String result) => _prefs.setString(
      _checkKey, '${DateTime.now().millisecondsSinceEpoch}|$result');

  Future<void> clear() => _prefs.remove(_key);
}
