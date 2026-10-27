import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/format.dart';
import '../../core/widgets/markdown_style.dart';
import '../../core/widgets/reddit_markdown.dart';
import '../../models/comment.dart';
import '../../models/post.dart';
import 'comment_tree.dart';

/// Previews a comment and its parent chain as an image card, then shares it
/// as a PNG. Usernames can be hidden before sharing.
Future<void> showShareCommentImage(BuildContext context,
        {required Post post, required List<Comment> chain}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _ShareImageDialog(post: post, chain: chain),
    );

class _ShareImageDialog extends StatefulWidget {
  const _ShareImageDialog({required this.post, required this.chain});
  final Post post;
  final List<Comment> chain; // top-level ancestor first, shared comment last

  @override
  State<_ShareImageDialog> createState() => _ShareImageDialogState();
}

class _ShareImageDialogState extends State<_ShareImageDialog> {
  final _boundary = GlobalKey();
  bool _hideNames = false;
  bool _busy = false;

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final box = _boundary.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      final image = await box.toImage(pixelRatio: 3);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('${(await getTemporaryDirectory()).path}/'
          'ilay_comment_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(png!.buffer.asUint8List());
      await Share.shareXFiles([XFile(file.path, mimeType: 'image/png')]);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Couldn't create the image")));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Share as image'),
      contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: RepaintBoundary(
                  key: _boundary,
                  child: _ChainCard(
                      post: widget.post,
                      chain: widget.chain,
                      hideNames: _hideNames),
                ),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Hide usernames'),
              value: _hideNames,
              onChanged: (v) => setState(() => _hideNames = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton.icon(
          onPressed: _busy ? null : _share,
          icon: const Icon(Icons.ios_share_rounded),
          label: const Text('Share'),
        ),
      ],
    );
  }
}

/// The card that becomes the image: post title, then the comment chain.
class _ChainCard extends StatelessWidget {
  const _ChainCard(
      {required this.post, required this.chain, required this.hideNames});
  final Post post;
  final List<Comment> chain;
  final bool hideNames;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    final names = CommentTree.shareNames(chain, hideNames);
    return Container(
      color: cs.surface,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('r/${post.subreddit}',
              style: muted.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(post.title,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, height: 1.3)),
          const SizedBox(height: 12),
          for (var i = 0; i < chain.length; i++)
            Padding(
              padding: EdgeInsetsDirectional.only(start: i * 10.0, bottom: 8),
              // A Stack for the start bar: a one-sided border can't take
              // rounded corners.
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(children: [
                  Container(
                    width: double.infinity,
                    color: cs.surfaceContainerLow,
                    padding: const EdgeInsetsDirectional.fromSTEB(10, 6, 6, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            '${names[i]} · '
                            '${compactNumber(chain[i].score)} points',
                            style: muted.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        RedditMarkdown(
                            data: chain[i].body,
                            styleSheet:
                                redditMarkdownStyle(context, fontSize: 14)),
                      ],
                    ),
                  ),
                  PositionedDirectional(
                    start: 0,
                    top: 0,
                    bottom: 0,
                    width: 3,
                    child: ColoredBox(
                        color: i == chain.length - 1
                            ? cs.primary
                            : cs.outlineVariant),
                  ),
                ]),
              ),
            ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Text('Shared from Ilay for Reddit',
                style: muted.copyWith(fontSize: 10.5)),
          ),
        ],
      ),
    );
  }
}
