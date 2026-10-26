import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart';
import '../auth/auth_controller.dart';
import '../settings/settings_controller.dart';
import 'inbox_poller.dart';
import 'notification_log.dart';
import 'notification_service.dart';

String _timeAgoPhrase(int millis) {
  final t = timeAgo(DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true));
  return t == 'now' ? 'just now' : '$t ago';
}

/// Settings → Notification activity: whether Ilay can notify you right now
/// (and what to fix if not), "Check now", and the last notifications it
/// showed or couldn't show — tap one to open it.
class NotificationActivityScreen extends ConsumerStatefulWidget {
  const NotificationActivityScreen({super.key});

  @override
  ConsumerState<NotificationActivityScreen> createState() =>
      _NotificationActivityScreenState();
}

class _NotificationActivityScreenState
    extends ConsumerState<NotificationActivityScreen> {
  late final NotificationLog _log =
      NotificationLog(ref.read(sharedPrefsProvider));
  List<NotificationEvent> _events = const [];
  (int, String)? _lastCheck;
  bool? _canNotify;
  bool _checking = false;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Permission is the system's: re-read on return from its settings.
    _lifecycle = AppLifecycleListener(onResume: _reload);
    _reload();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    // The background check writes these from its own isolate.
    await ref.read(sharedPrefsProvider).reload();
    final can = await NotificationService.instance.canNotify();
    if (!mounted) return;
    setState(() {
      _events = _log.events();
      _lastCheck = _log.lastCheck();
      _canNotify = can;
    });
  }

  Future<void> _checkNow() async {
    setState(() => _checking = true);
    final messenger = ScaffoldMessenger.of(context);
    List<UnreadItem>? shown;
    try {
      shown = await pollInbox(notify: true);
    } catch (_) {/* reported below */}
    await _reload();
    if (!mounted) return;
    setState(() => _checking = false);
    messenger.showSnackBar(SnackBar(
        content: Text(shown == null
            ? "Couldn't check the inbox"
            : shown.isEmpty
                ? 'Checked: ${_lastCheck?.$2 ?? 'nothing new'}'
                : '${shown.length} new notification'
                    '${shown.length == 1 ? '' : 's'}')));
  }

  // Opens the event's reply / message.
  void _open(NotificationEvent e) {
    final me = ref.read(authControllerProvider).valueOrNull?.username ?? '';
    final messenger = ScaffoldMessenger.of(context);
    if (e.account.isNotEmpty && e.account.toLowerCase() != me.toLowerCase()) {
      messenger.showSnackBar(SnackBar(
          content: Text('This was for u/${e.account}: switch to that account '
              'to open it')));
      return;
    }
    final route = e.route;
    if (route != null) {
      context.push(route);
    } else {
      messenger.showSnackBar(const SnackBar(
          content: Text("Couldn't find it: try your Inbox")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final notifyInbox =
        ref.watch(settingsControllerProvider.select((s) => s.notifyInbox));
    final can = _canNotify ?? true;
    final last = _lastCheck;
    final status = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusRow(
            ok: can,
            text: can
                ? 'Ilay can show notifications'
                : "Ilay's notifications are turned off",
            fix: can
                ? null
                : ('Allow', () => launchUrl(Uri.parse('app-settings:'))),
          ),
          const SizedBox(height: 10),
          _StatusRow(
            ok: notifyInbox,
            // iOS decides how often a background check runs.
            text: notifyInbox
                ? 'Checks your inbox in the background'
                : 'Inbox notifications are off (Settings → Notifications)',
          ),
          const SizedBox(height: 10),
          Text(
            last == null
                ? 'No inbox check yet'
                : 'Last check ${_timeAgoPhrase(last.$1)}: ${last.$2}',
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _checking ? null : _checkNow,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(_checking ? 'Checking…' : 'Check now'),
          ),
        ],
      ),
    );
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Notification activity'),
        actions: [
          if (_events.isNotEmpty)
            TextButton(
              onPressed: () async {
                await _log.clear();
                _reload();
              },
              child: const Text('Clear'),
            ),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 130),
        itemCount: _events.length + (_events.isEmpty ? 3 : 2),
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          if (i == 0) return status;
          if (i == 1) {
            return Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 2),
              child: Text('Recent',
                  style: TextStyle(
                      color: cs.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14)),
            );
          }
          if (_events.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                "Notifications Ilay shows or can't show will be listed here.",
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            );
          }
          final e = _events[i - 2];
          return _EventRow(
              key: ValueKey('${e.at}_${e.title.hashCode}'),
              e: e,
              onOpen: () => _open(e));
        },
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.ok, required this.text, this.fix});
  final bool ok;
  final String text;
  final (String, VoidCallback)? fix;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final f = fix;
    return Row(
      children: [
        Icon(ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
            size: 20, color: ok ? cs.primary : cs.error),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text,
              style: TextStyle(fontSize: 14, color: cs.onSurface)),
        ),
        if (f != null) TextButton(onPressed: f.$2, child: Text(f.$1)),
      ],
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({super.key, required this.e, required this.onOpen});
  final NotificationEvent e;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ok = e.outcome.ok;
    final meta = [
      if (e.account.isNotEmpty) 'u/${e.account}',
      _timeAgoPhrase(e.at),
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
                ok
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_off_outlined,
                size: 20,
                color: ok ? cs.onSurfaceVariant : cs.error),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                if (e.text.isNotEmpty)
                  Text(e.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                const SizedBox(height: 2),
                Text('$meta\n${e.outcome.label}',
                    style: TextStyle(
                        fontSize: 12,
                        color: ok ? cs.onSurfaceVariant : cs.error)),
              ],
            ),
          ),
          TextButton(onPressed: onOpen, child: const Text('Open')),
        ],
      ),
    );
  }
}
