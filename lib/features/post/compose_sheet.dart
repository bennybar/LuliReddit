import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/drafts.dart';
import '../../core/network/catbox.dart';
import '../../core/providers.dart';
import '../../models/comment.dart';
import '../../core/widgets/markdown_toolbar.dart';
import '../media/attachment.dart';
import '../media/attachment_bar.dart';
import '../media/giphy_picker.dart';

/// Opens a reply composer. Returns the created [Comment] on success.
///
/// Supports attaching an image (posted inline via Reddit's richtext where the
/// subreddit allows it) or a video (uploaded to Catbox and linked).
Future<Comment?> showReplySheet(
  BuildContext context,
  WidgetRef ref, {
  required String parentFullname,
  required int parentDepth,
  String? replyingTo,
}) {
  return showModalBottomSheet<Comment>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _ComposeSheet(
      ref: ref,
      title: replyingTo == null ? 'Reply' : 'Reply to u/$replyingTo',
      submitLabel: 'Reply',
      allowAttachments: true,
      draftKey: 'reply_$parentFullname',
      onSubmitMedia: (text, media) async {
        final repo = ref.read(redditRepositoryProvider);
        if (media == null) {
          return repo.reply(
              parentFullname: parentFullname,
              text: text,
              depth: parentDepth + 1);
        }
        if (media.isVideo) {
          final url =
              await uploadToCatbox(bytes: media.bytes, filename: media.filename);
          final body = text.isEmpty ? url : '$text\n\n$url';
          return repo.reply(
              parentFullname: parentFullname,
              text: body,
              depth: parentDepth + 1);
        }
        return repo.replyWithImage(
          parentFullname: parentFullname,
          text: text,
          bytes: media.bytes,
          filename: media.filename,
          mimeType: media.mimeType,
          depth: parentDepth + 1,
        );
      },
    ),
  );
}

/// Opens an editor for your own post/comment body. Returns the new text.
Future<String?> showEditSheet(
  BuildContext context,
  WidgetRef ref, {
  required String thingFullname,
  required String initialText,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _ComposeSheet(
      ref: ref,
      title: 'Edit',
      submitLabel: 'Save',
      initialText: initialText,
      onSubmit: (text) async {
        await ref
            .read(redditRepositoryProvider)
            .editText(thingFullname: thingFullname, text: text);
        return text;
      },
    ),
  );
}

class _ComposeSheet<T> extends StatefulWidget {
  const _ComposeSheet({
    required this.ref,
    required this.title,
    required this.submitLabel,
    this.onSubmit,
    this.onSubmitMedia,
    this.allowAttachments = false,
    this.initialText,
    this.draftKey,
  }) : assert(onSubmit != null || onSubmitMedia != null);

  final WidgetRef ref;
  final String title;
  final String submitLabel;
  final String? initialText;
  final bool allowAttachments;

  /// When set, the in-progress text is autosaved/restored under this key.
  final String? draftKey;

  /// Text-only submit (used for editing).
  final Future<T> Function(String text)? onSubmit;

  /// Submit with an optional attachment (used for replies).
  final Future<T> Function(String text, MediaAttachment? media)? onSubmitMedia;

  @override
  State<_ComposeSheet<T>> createState() => _ComposeSheetState<T>();
}

class _ComposeSheetState<T> extends State<_ComposeSheet<T>> {
  late final _controller = TextEditingController(text: _initialText());
  bool _busy = false;
  String? _error;
  MediaAttachment? _media;

  String? _initialText() {
    if (widget.initialText != null) return widget.initialText;
    if (widget.draftKey != null) {
      return widget.ref.read(draftsProvider).get(widget.draftKey!);
    }
    return null;
  }

  void _onChanged(String v) {
    if (widget.draftKey != null) {
      widget.ref.read(draftsProvider).save(widget.draftKey!, v);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _insertGif() async {
    final url = await showGiphyPicker(context, widget.ref);
    if (url == null) return;
    final sep = _controller.text.isEmpty ? '' : '\n';
    _controller.text = '${_controller.text}$sep$url';
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty && _media == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final T result = widget.onSubmitMedia != null
          ? await widget.onSubmitMedia!(text, _media)
          : await widget.onSubmit!(text);
      if (widget.draftKey != null) {
        widget.ref.read(draftsProvider).clear(widget.draftKey!);
      }
      if (mounted) Navigator.pop(context, result);
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
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            onChanged: _onChanged,
            decoration: const InputDecoration(
              hintText: 'Markdown supported',
            ),
          ),
          MarkdownToolbar(controller: _controller),
          const SizedBox(height: 6),
          if (widget.allowAttachments)
            AttachmentControls(
              media: _media,
              onChanged: (m) => setState(() {
                _media = m;
                _error = null;
              }),
              onError: (msg) => setState(() => _error = msg),
              leading: [
                TextButton.icon(
                  onPressed: _insertGif,
                  icon: const Icon(Icons.gif_box_outlined),
                  label: const Text('GIF'),
                ),
              ],
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _insertGif,
                icon: const Icon(Icons.gif_box_outlined),
                label: const Text('GIF'),
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: cs.error)),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _submit,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send_rounded),
            label: Text(_busy ? 'Sending…' : widget.submitLabel),
          ),
        ],
      ),
    );
  }
}

