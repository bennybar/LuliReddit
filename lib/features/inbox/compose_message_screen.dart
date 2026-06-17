import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/drafts.dart';
import '../../core/network/catbox.dart';
import '../../core/providers.dart';
import '../../core/widgets/markdown_toolbar.dart';
import '../media/attachment.dart';
import '../media/attachment_bar.dart';

class ComposeMessageScreen extends ConsumerStatefulWidget {
  const ComposeMessageScreen({super.key, this.initialTo});
  final String? initialTo;

  @override
  ConsumerState<ComposeMessageScreen> createState() =>
      _ComposeMessageScreenState();
}

class _ComposeMessageScreenState extends ConsumerState<ComposeMessageScreen> {
  late final _to = TextEditingController(text: widget.initialTo ?? '');
  final _subject = TextEditingController();
  final _body = TextEditingController();
  bool _busy = false;
  String? _error;
  MediaAttachment? _media;

  static const _draftKey = 'compose_msg';

  @override
  void initState() {
    super.initState();
    final raw = ref.read(draftsProvider).get(_draftKey);
    if (raw != null) {
      try {
        final m = jsonDecode(raw) as Map;
        if ((widget.initialTo ?? '').isEmpty) _to.text = m['to'] ?? '';
        _subject.text = m['subject'] ?? '';
        _body.text = m['body'] ?? '';
      } catch (_) {/* ignore malformed draft */}
    }
  }

  void _saveDraft() => ref.read(draftsProvider).save(
        _draftKey,
        jsonEncode({
          'to': _to.text,
          'subject': _subject.text,
          'body': _body.text,
        }),
      );

  @override
  void dispose() {
    _to.dispose();
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final to = _to.text.trim();
    final subject = _subject.text.trim();
    var body = _body.text.trim();
    if (to.isEmpty || subject.isEmpty || (body.isEmpty && _media == null)) {
      setState(() => _error = 'Recipient, subject and a message or attachment '
          'are required.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_media != null) {
        // Reddit messages are markdown-text only, so host on Catbox + link.
        final url = await uploadToCatbox(
            bytes: _media!.bytes, filename: _media!.filename);
        body = body.isEmpty ? url : '$body\n\n$url';
      }
      await ref
          .read(redditRepositoryProvider)
          .composeMessage(to: to, subject: subject, text: body);
      ref.read(draftsProvider).clear(_draftKey);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Message sent')));
      context.pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e'.replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New message'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: _busy ? null : _send,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Send'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _to,
            autocorrect: false,
            onChanged: (_) => _saveDraft(),
            decoration: const InputDecoration(
                labelText: 'To', prefixText: 'u/', prefixIcon: Icon(Icons.person_rounded)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _subject,
            onChanged: (_) => _saveDraft(),
            decoration: const InputDecoration(
                labelText: 'Subject', prefixIcon: Icon(Icons.subject_rounded)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _body,
            minLines: 6,
            maxLines: 14,
            onChanged: (_) => _saveDraft(),
            decoration: const InputDecoration(
                labelText: 'Message (Markdown)', alignLabelWithHint: true),
          ),
          MarkdownToolbar(controller: _body),
          const SizedBox(height: 4),
          AttachmentControls(
            media: _media,
            catboxForImages: true,
            onChanged: (m) => setState(() {
              _media = m;
              _error = null;
            }),
            onError: (msg) => setState(() => _error = msg),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
    );
  }
}
