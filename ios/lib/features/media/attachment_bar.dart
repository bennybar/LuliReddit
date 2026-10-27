import 'package:flutter/material.dart';

import 'attachment.dart';

/// Reusable composer attachment UI: a pending-attachment preview plus a row of
/// pick-image / pick-video / paste buttons. Stateless — the parent owns the
/// current [media] and is notified via [onChanged] / [onError].
class AttachmentControls extends StatelessWidget {
  const AttachmentControls({
    super.key,
    required this.media,
    required this.onChanged,
    required this.onError,
    this.leading = const [],
    this.catboxForImages = false,
  });

  final MediaAttachment? media;
  final ValueChanged<MediaAttachment?> onChanged;
  final ValueChanged<String> onError;

  /// Extra buttons shown before the attach buttons (e.g. a GIF button).
  final List<Widget> leading;

  /// When true, even images are hosted on Catbox (used in messages, which can't
  /// carry Reddit-hosted media). When false, images go inline via Reddit.
  final bool catboxForImages;

  Future<void> _pick(Future<MediaAttachment?> Function() f,
      {String? emptyMsg}) async {
    try {
      final m = await f();
      if (m == null) {
        if (emptyMsg != null) onError(emptyMsg);
        return;
      }
      onChanged(m);
    } catch (e) {
      onError('$e'.replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (media != null) ...[
          AttachmentPreview(media: media!, onRemove: () => onChanged(null)),
          const SizedBox(height: 4),
        ],
        Row(
          children: [
            ...leading,
            IconButton(
              tooltip: 'Attach image',
              onPressed: () => _pick(pickImageAttachment),
              icon: const Icon(Icons.image_outlined),
            ),
            IconButton(
              tooltip: 'Attach video',
              onPressed: () => _pick(pickVideoAttachment),
              icon: const Icon(Icons.videocam_outlined),
            ),
            IconButton(
              tooltip: 'Paste image',
              onPressed: () => _pick(pasteImageAttachment,
                  emptyMsg: 'No image on the clipboard.'),
              icon: const Icon(Icons.content_paste_rounded),
            ),
          ],
        ),
        if (media != null)
          Text(_noteFor(media!),
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
      ],
    );
  }

  String _noteFor(MediaAttachment m) {
    if (m.isVideo || catboxForImages) {
      return 'Will be uploaded to catbox.moe and linked (public).';
    }
    return 'Image posts inline (hosted by Reddit; some subs disallow it — '
        'falls back to a catbox.moe link).';
  }
}

/// Small inline preview of a pending attachment with a remove button.
class AttachmentPreview extends StatelessWidget {
  const AttachmentPreview({super.key, required this.media, required this.onRemove});
  final MediaAttachment media;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: media.isVideo
                ? Container(
                    width: 48,
                    height: 48,
                    color: cs.surfaceContainerHigh,
                    child:
                        Icon(Icons.movie_outlined, color: cs.onSurfaceVariant),
                  )
                : Image.memory(media.bytes,
                    width: 48, height: 48, fit: BoxFit.cover),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(media.isVideo ? 'Video' : 'Image',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(media.sizeLabel,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Remove',
          ),
        ],
      ),
    );
  }
}
