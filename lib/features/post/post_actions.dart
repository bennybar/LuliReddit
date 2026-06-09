import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers.dart';
import '../../core/share.dart';
import '../../models/post.dart';

/// Bottom sheet of secondary actions for a post: hide, report, crosspost, open.
void showPostActionsSheet(BuildContext context, WidgetRef ref, Post post) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.share_outlined),
            title: const Text('Share'),
            onTap: () {
              Navigator.pop(ctx);
              shareUrl('https://reddit.com${post.permalink}',
                  subject: post.title);
            },
          ),
          ListTile(
            leading: const Icon(Icons.visibility_off_outlined),
            title: const Text('Hide'),
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(ctx);
              try {
                await ref.read(redditRepositoryProvider)
                    .setHidden(post.fullname, true);
                _snack(messenger, 'Post hidden');
              } catch (e) {
                _snack(messenger, 'Could not hide: $e');
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.flag_outlined),
            title: const Text('Report'),
            onTap: () {
              Navigator.pop(ctx);
              _showReportDialog(context, ref, post.fullname);
            },
          ),
          ListTile(
            leading: const Icon(Icons.repeat_rounded),
            title: const Text('Crosspost'),
            onTap: () {
              Navigator.pop(ctx);
              _showCrosspostDialog(context, ref, post);
            },
          ),
          ListTile(
            leading: const Icon(Icons.open_in_new_rounded),
            title: const Text('Open in browser'),
            onTap: () {
              Navigator.pop(ctx);
              launchUrl(Uri.parse('https://reddit.com${post.permalink}'),
                  mode: LaunchMode.externalApplication);
            },
          ),
          if (post.canModPost) ...[
            const Divider(height: 8),
            ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: const Text('Moderate'),
              dense: true,
              enabled: false,
            ),
            _modTile(ref, post, 'Approve', Icons.check_circle_outline,
                (r) => r.modApprove(post.fullname), 'Approved'),
            _modTile(ref, post, 'Remove', Icons.block_rounded,
                (r) => r.modRemove(post.fullname), 'Removed'),
            _modTile(ref, post, 'Remove as spam', Icons.report_gmailerrorred_outlined,
                (r) => r.modRemove(post.fullname, spam: true), 'Removed as spam'),
            _modTile(
                ref,
                post,
                post.locked ? 'Unlock' : 'Lock',
                post.locked ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
                (r) => r.modLock(post.fullname, !post.locked),
                post.locked ? 'Unlocked' : 'Locked'),
          ],
        ],
      ),
    ),
  );
}

Widget _modTile(WidgetRef ref, Post post, String label, IconData icon,
    Future<void> Function(dynamic repo) action, String done) {
  return Builder(builder: (ctx) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      onTap: () async {
        final messenger = ScaffoldMessenger.of(ctx);
        Navigator.pop(ctx);
        try {
          await action(ref.read(redditRepositoryProvider));
          _snack(messenger, done);
        } catch (e) {
          _snack(messenger, 'Failed: $e');
        }
      },
    );
  });
}

const _reportReasons = [
  'Spam',
  'Harassment or bullying',
  'Hate speech',
  'Violence or threats',
  'Misinformation',
  'Breaks subreddit rules',
];

void _showReportDialog(BuildContext context, WidgetRef ref, String fullname) {
  final custom = TextEditingController();
  String? selected;
  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Report'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final r in _reportReasons)
                RadioListTile<String>(
                  value: r,
                  // ignore: deprecated_member_use
                  groupValue: selected,
                  // ignore: deprecated_member_use
                  onChanged: (v) => setState(() => selected = v),
                  title: Text(r),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              TextField(
                controller: custom,
                decoration: const InputDecoration(
                    hintText: 'Other reason (optional)'),
                onChanged: (_) => setState(() => selected = null),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final reason = custom.text.trim().isNotEmpty
                  ? custom.text.trim()
                  : selected;
              if (reason == null) return;
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(ctx);
              try {
                await ref.read(redditRepositoryProvider)
                    .report(fullname, reason);
                _snack(messenger, 'Reported. Thanks.');
              } catch (e) {
                _snack(messenger, 'Could not report: $e');
              }
            },
            child: const Text('Report'),
          ),
        ],
      ),
    ),
  );
}

void _showCrosspostDialog(BuildContext context, WidgetRef ref, Post post) {
  final sr = TextEditingController();
  final title = TextEditingController(text: post.title);
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Crosspost'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: sr,
            autocorrect: false,
            decoration: const InputDecoration(
                labelText: 'Subreddit', prefixText: 'r/'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: title,
            maxLines: 2,
            minLines: 1,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            final srName = sr.text.trim();
            if (srName.isEmpty || title.text.trim().isEmpty) return;
            final messenger = ScaffoldMessenger.of(context);
            final router = GoRouter.of(context);
            Navigator.pop(ctx);
            try {
              final id = await ref.read(redditRepositoryProvider).submitCrosspost(
                    subreddit: srName,
                    title: title.text.trim(),
                    crosspostFullname: post.fullname,
                  );
              router.push('/comments/$srName/$id');
            } catch (e) {
              _snack(messenger, 'Crosspost failed: $e');
            }
          },
          child: const Text('Post'),
        ),
      ],
    ),
  );
}

void _snack(ScaffoldMessengerState messenger, String msg) {
  messenger.showSnackBar(
      SnackBar(content: Text(msg.replaceFirst('Exception: ', ''))));
}
