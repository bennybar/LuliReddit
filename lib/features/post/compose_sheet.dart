import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../models/comment.dart';
import '../media/giphy_picker.dart';

/// Opens a reply composer. Returns the created [Comment] on success.
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
      onSubmit: (text) async {
        return ref.read(redditRepositoryProvider).reply(
              parentFullname: parentFullname,
              text: text,
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
    required this.onSubmit,
    this.initialText,
  });

  final WidgetRef ref;
  final String title;
  final String submitLabel;
  final String? initialText;
  final Future<T> Function(String text) onSubmit;

  @override
  State<_ComposeSheet<T>> createState() => _ComposeSheetState<T>();
}

class _ComposeSheetState<T> extends State<_ComposeSheet<T>> {
  late final _controller = TextEditingController(text: widget.initialText);
  bool _busy = false;
  String? _error;

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
    if (text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.onSubmit(text);
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
            decoration: const InputDecoration(
              hintText: 'Markdown supported',
            ),
          ),
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
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
