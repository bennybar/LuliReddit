import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/drafts.dart';
import '../../core/format.dart';
import '../../core/network/catbox.dart';
import '../../core/providers.dart';
import '../../core/open_link.dart';
import '../../core/widgets/error_view.dart';
import '../../core/widgets/markdown_style.dart';
import '../../core/widgets/reddit_markdown.dart';
import '../../models/inbox_item.dart';
import '../auth/auth_controller.dart';
import '../media/attachment.dart';
import '../media/attachment_bar.dart';

/// A private-message conversation: [root] when it's at hand, else fetched by
/// [fullname] (opened from a notification or a draft).
class MessageThreadScreen extends ConsumerStatefulWidget {
  const MessageThreadScreen({super.key, this.root, this.fullname})
      : assert(root != null || fullname != null);
  final InboxItem? root;
  final String? fullname;

  @override
  ConsumerState<MessageThreadScreen> createState() =>
      _MessageThreadScreenState();
}

class _MessageThreadScreenState extends ConsumerState<MessageThreadScreen> {
  late Future<InboxItem> _root = _load();

  Future<InboxItem> _load() async {
    final root = widget.root;
    if (root != null) return root;
    final thread = await ref
        .read(redditRepositoryProvider)
        .getMessageThread(widget.fullname!);
    if (thread == null) throw Exception('This message is no longer available.');
    return thread;
  }

  @override
  Widget build(BuildContext context) {
    final root = widget.root;
    final title = root?.subject;
    return FutureBuilder<InboxItem>(
      future: _root,
      initialData: root,
      builder: (context, snap) {
        final r = snap.data;
        final subject = r?.subject ?? title ?? '';
        return Scaffold(
          appBar: AppBar(
            title: Text(
              subject.isEmpty ? 'Message' : subject,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          body: r != null
              ? _Thread(root: r)
              : snap.hasError
                  ? ErrorView(
                      message: snap.error,
                      onRetry: () => setState(() => _root = _load()))
                  : const Center(child: CircularProgressIndicator()),
        );
      },
    );
  }
}

class _Thread extends ConsumerStatefulWidget {
  const _Thread({required this.root});
  final InboxItem root;

  @override
  ConsumerState<_Thread> createState() => _ThreadState();
}

class _ThreadState extends ConsumerState<_Thread> {
  final _reply = TextEditingController();
  late final List<InboxItem> _messages = [widget.root, ...widget.root.replies];
  bool _sending = false;
  MediaAttachment? _media;

  String get _draftKey => 'msgreply_${widget.root.fullname}';

  @override
  void initState() {
    super.initState();
    final saved = ref.read(draftsProvider).get(_draftKey);
    if (saved != null && saved.isNotEmpty) _reply.text = saved;
  }

  // Where it goes, for the Drafts list.
  void _saveDraft(String v) {
    final me = ref.read(authControllerProvider).valueOrNull?.username ?? '';
    final other = _messages
            .where((m) => m.author.toLowerCase() != me.toLowerCase())
            .firstOrNull
            ?.author ??
        widget.root.author;
    ref.read(draftsProvider).save(_draftKey, v, info: {
      'kind': 'msgreply',
      'subject': widget.root.subject,
      'to': other,
    });
  }

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _setMedia(Future<MediaAttachment?> Function() pick,
      {String? emptyMsg}) async {
    try {
      final m = await pick();
      if (m == null) {
        if (emptyMsg != null && mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(emptyMsg)));
        }
        return;
      }
      if (mounted) setState(() => _media = m);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$e'.replaceFirst('Exception: ', ''))));
      }
    }
  }

  void _showAttachMenu() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Attach image'),
              onTap: () {
                Navigator.pop(ctx);
                _setMedia(pickImageAttachment);
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Attach video'),
              onTap: () {
                Navigator.pop(ctx);
                _setMedia(pickVideoAttachment);
              },
            ),
            ListTile(
              leading: const Icon(Icons.content_paste_rounded),
              title: const Text('Paste image'),
              onTap: () {
                Navigator.pop(ctx);
                _setMedia(pasteImageAttachment,
                    emptyMsg: 'No image on the clipboard.');
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _send() async {
    var text = _reply.text.trim();
    if (text.isEmpty && _media == null) return;
    setState(() => _sending = true);
    final me = ref.read(authControllerProvider).valueOrNull?.username ?? 'you';
    // Reply to the most recent real message in the thread for correct
    // threading.
    final target = _messages
        .lastWhere((m) => !m.fullname.startsWith('local_'))
        .fullname;
    try {
      if (_media != null) {
        // Reddit messages are markdown-text only, so host on Catbox + link.
        final url = await uploadToCatbox(
            bytes: _media!.bytes, filename: _media!.filename);
        text = text.isEmpty ? url : '$text\n\n$url';
      }
      await ref.read(redditRepositoryProvider).sendReply(target, text);
      ref.read(draftsProvider).clear(_draftKey);
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
        _media = null;
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
    return Column(
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
                      RedditMarkdown(
                        data: m.body,
                        selectable: true,
                        styleSheet: redditMarkdownStyle(context, fontSize: 14),
                        onTapLink: (_, href, __) => openLink(context, href),
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_media != null) ...[
                  AttachmentPreview(
                    media: _media!,
                    onRemove: () => setState(() => _media = null),
                  ),
                  const SizedBox(height: 6),
                ],
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Attach',
                      onPressed: _sending ? null : _showAttachMenu,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _reply,
                        minLines: 1,
                        maxLines: 5,
                        onChanged: _saveDraft,
                        // GIFs and stickers from the keyboard.
                        contentInsertionConfiguration: keyboardMedia(
                            (m) => setState(() => _media = m),
                            (msg) => ScaffoldMessenger.of(context)
                                .showSnackBar(SnackBar(content: Text(msg)))),
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
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
