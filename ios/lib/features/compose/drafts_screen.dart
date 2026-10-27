import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/drafts.dart';
import '../../core/format.dart';

/// A draft as a row: what it is, where it goes, its text, and the route that
/// resumes it.
class _DraftRow {
  const _DraftRow(this.icon, this.where, this.preview, this.open);
  final IconData icon;
  final String where;
  final String preview;
  final String? open;
}

String? _nonBlank(Object? v) =>
    v is String && v.trim().isNotEmpty ? v : null;

_DraftRow _rowOf(Draft d) {
  final info = d.info ?? const <String, dynamic>{};
  Map? json;
  try {
    final j = jsonDecode(d.text);
    if (j is Map) json = j;
  } catch (_) {/* plain text */}
  String q(String path, Map<String, String?> params) {
    final p = {
      for (final e in params.entries)
        if (e.value != null) e.key: e.value!
    };
    return Uri(path: path, queryParameters: p.isEmpty ? null : p).toString();
  }

  if (d.key.startsWith('reply_')) {
    final to = _nonBlank(info['to']);
    final title = _nonBlank(info['title']);
    final sub = _nonBlank(info['sub']);
    final post = _nonBlank(info['post']);
    return _DraftRow(
      Icons.reply_rounded,
      [
        to != null ? 'Reply to u/$to' : 'Reply',
        if (title != null) 'in "$title"',
        if (sub != null) 'r/$sub',
      ].join(' · '),
      d.text,
      post == null
          ? null
          : q('/comments/${sub ?? '_'}/$post',
              {'comment': _nonBlank(info['comment'])}),
    );
  }
  if (d.key.startsWith('msgreply_')) {
    final to = _nonBlank(info['to']);
    return _DraftRow(
      Icons.mail_outline_rounded,
      [
        to != null ? 'Reply to u/$to' : 'Message reply',
        if (_nonBlank(info['subject']) != null) info['subject'] as String,
      ].join(' · '),
      d.text,
      q('/message', {'id': d.key.substring('msgreply_'.length)}),
    );
  }
  if (d.key == 'compose_msg') {
    final to = _nonBlank(json?['to']);
    return _DraftRow(
      Icons.mail_outline_rounded,
      to != null ? 'Message to u/$to' : 'New message',
      [_nonBlank(json?['subject']), _nonBlank(json?['body'])]
          .whereType<String>()
          .join(' — '),
      q('/compose_message', {'to': to}),
    );
  }
  if (d.key == 'compose_post') {
    final sr = _nonBlank(json?['sr']);
    return _DraftRow(
      Icons.edit_note_rounded,
      sr != null ? 'New post in r/$sr' : 'New post',
      [
        _nonBlank(json?['title']),
        _nonBlank(json?['body']) ?? _nonBlank(json?['url']),
      ].whereType<String>().join(' — '),
      q('/submit', {'sr': sr}),
    );
  }
  return _DraftRow(Icons.edit_note_rounded, 'Draft', d.text, null);
}

String _timeAgoPhrase(int millis) {
  final t = timeAgo(DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true));
  return t == 'now' ? 'just now' : '$t ago';
}

/// You → Drafts: this account's unfinished replies, messages and posts. Tap
/// to go where it belongs (its composer then restores it); swipe to delete.
class DraftsScreen extends ConsumerWidget {
  const DraftsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final drafts = ref.watch(draftListProvider);
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(title: const Text('Drafts')),
      body: drafts.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No drafts. Unfinished replies, messages and posts are '
                  'kept here until you send them.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 130),
              itemCount: drafts.length,
              itemBuilder: (_, i) =>
                  _DraftItem(key: ValueKey(drafts[i].key), d: drafts[i]),
            ),
    );
  }
}

class _DraftItem extends ConsumerWidget {
  const _DraftItem({super.key, required this.d});
  final Draft d;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final row = _rowOf(d);
    return Dismissible(
      key: ValueKey('draft_${d.key}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) {
        ref.read(draftsProvider).clear(d.key);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Draft deleted')));
      },
      background: Container(
        color: cs.errorContainer,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        alignment: AlignmentDirectional.centerEnd,
        child: Icon(Icons.delete_outline_rounded,
            color: cs.onErrorContainer, semanticLabel: 'Delete'),
      ),
      child: ListTile(
        tileColor: cs.surface,
        leading: Icon(row.icon),
        title: Text(row.preview.trim().isEmpty ? '(empty)' : row.preview,
            maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          [row.where, if (d.savedAt > 0) _timeAgoPhrase(d.savedAt)]
              .join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: row.open == null ? null : () => context.push(row.open!),
      ),
    );
  }
}
