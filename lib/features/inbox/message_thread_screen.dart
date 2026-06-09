import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../models/inbox_item.dart';
import '../auth/auth_controller.dart';

class MessageThreadScreen extends ConsumerStatefulWidget {
  const MessageThreadScreen({super.key, required this.root});
  final InboxItem root;

  @override
  ConsumerState<MessageThreadScreen> createState() =>
      _MessageThreadScreenState();
}

class _MessageThreadScreenState extends ConsumerState<MessageThreadScreen> {
  final _reply = TextEditingController();
  late final List<InboxItem> _messages = [widget.root, ...widget.root.replies];
  bool _sending = false;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _reply.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    final me = ref.read(authControllerProvider).valueOrNull?.username ?? 'you';
    // Reply to the most recent message in the thread for correct threading.
    final target = _messages.last.fullname;
    try {
      await ref.read(redditRepositoryProvider).sendReply(target, text);
      if (!mounted) return;
      setState(() {
        _messages.add(InboxItem(
          fullname: 'local_${_messages.length}',
          kind: InboxKind.message,
          author: me,
          subject: widget.root.subject,
          body: text,
          created: DateTime.now().toUtc(),
        ));
        _reply.clear();
        _sending = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$e'.replaceFirst('Exception: ', ''))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final me = ref.watch(authControllerProvider).valueOrNull?.username;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.root.subject.isEmpty ? 'Message' : widget.root.subject,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              itemCount: _messages.length,
              itemBuilder: (context, i) {
                final m = _messages[i];
                final mine = m.author == me;
                return Align(
                  alignment:
                      mine ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.82),
                    decoration: BoxDecoration(
                      color: mine
                          ? cs.primaryContainer
                          : cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('u/${m.author} · ${timeAgo(m.created)}',
                            style: TextStyle(
                                fontSize: 11, color: cs.onSurfaceVariant)),
                        const SizedBox(height: 4),
                        MarkdownBody(
                          data: m.body,
                          styleSheet: MarkdownStyleSheet(
                              p: Theme.of(context).textTheme.bodyMedium),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _reply,
                      minLines: 1,
                      maxLines: 5,
                      decoration: const InputDecoration(hintText: 'Reply…'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
