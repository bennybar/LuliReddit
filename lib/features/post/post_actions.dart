import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/reddit_client.dart';
import '../../core/providers.dart';
import '../../core/share.dart';
import '../../core/widgets/error_view.dart';
import '../../core/widgets/tap_guard.dart';
import '../../models/post.dart';
import '../feed/expiring_ids.dart';
import '../feed/post_card.dart' show filterOutSub, hideSubFromHome;
import '../foryou/for_you_learner.dart';
import '../foryou/tune_sheet.dart';
import '../history/history_store.dart';
import '../media/share_media.dart';
import '../offline/offline_store.dart';
import '../settings/settings_controller.dart';

/// Bottom sheet of secondary actions for a post: hide, report, crosspost, open.
void showPostActionsSheet(BuildContext context, WidgetRef ref, Post post) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    // Ignore taps briefly so the gesture that opened the sheet can't fall
    // through onto an item.
    builder: (ctx) => TapGuard(
      child: SafeArea(
      child: SingleChildScrollView(
        child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.share_outlined),
            title: const Text('Share link'),
            onTap: () {
              Navigator.pop(ctx);
              // Sharing is a strong interest signal.
              ref.read(forYouLearnerProvider).share(post);
              shareUrl(context, 'https://reddit.com${post.permalink}',
                  subject: post.title);
            },
          ),
          ListTile(
            leading: const Icon(Icons.text_snippet_outlined),
            title: const Text('Share with title'),
            subtitle: const Text('Includes the post title above the link'),
            onTap: () {
              Navigator.pop(ctx);
              ref.read(forYouLearnerProvider).share(post);
              shareUrlWithTitle(
                  context, 'https://reddit.com${post.permalink}', post.title);
            },
          ),
          if (canShareAsMedia(post))
            ListTile(
              leading: const Icon(Icons.perm_media_outlined),
              title: const Text('Share as media'),
              subtitle: const Text('The image or video itself, not a link'),
              onTap: () {
                Navigator.pop(ctx);
                ref.read(forYouLearnerProvider).share(post);
                shareAsMedia(context, post);
              },
            ),
          ListTile(
            leading: const Icon(Icons.visibility_off_outlined),
            title: const Text('Hide'),
            onTap: () {
              Navigator.pop(ctx);
              hidePost(context, ref, post);
            },
          ),
          ListTile(
            leading: const Icon(Icons.done_all_rounded),
            title: const Text('Already seen elsewhere'),
            subtitle: const Text('Mark as read and drop it from your feeds '
                '(e.g. read in the Reddit app)'),
            onTap: () {
              Navigator.pop(ctx);
              alreadySeen(context, ref, post);
            },
          ),
          if (post.subreddit.isNotEmpty) ...[
            ListTile(
              leading: const Icon(Icons.do_not_disturb_on_rounded),
              title: Text('Hide r/${post.subreddit} for 7 days'),
              subtitle: const Text(
                  'From your front page: Home, For You, Best / Hot / New'),
              onTap: () {
                Navigator.pop(ctx);
                hideSubFromHome(context, ref, post);
              },
            ),
            ListTile(
              leading: const Icon(Icons.filter_alt_outlined),
              title: Text('Filter out r/${post.subreddit}'),
              subtitle: const Text(
                  'From every feed, for good (Settings → Content filters)'),
              onTap: () {
                Navigator.pop(ctx);
                filterOutSub(context, ref, post);
              },
            ),
          ],
          // The Calm card has no read toggle of its own: it lives here.
          if (ref.read(settingsControllerProvider).postDisplay.isCalm)
            Builder(builder: (_) {
              final seen = ref.read(historyContainsProvider(post.id));
              return ListTile(
                leading: Icon(seen
                    ? Icons.check_circle_rounded
                    : Icons.check_circle_outline_rounded),
                title: Text(seen ? 'Mark as unread' : 'Mark as read'),
                onTap: () {
                  Navigator.pop(ctx);
                  final h = ref.read(historyControllerProvider.notifier);
                  seen ? h.removeViewed(post.id) : h.markViewed(post);
                },
              );
            }),
          Consumer(builder: (_, ref, __) {
            final saved = ref.watch(offlineProvider).any((t) => t.id == post.id);
            return ListTile(
              leading: Icon(saved
                  ? Icons.offline_pin_rounded
                  : Icons.download_for_offline_outlined),
              title: Text(saved ? 'Remove offline copy' : 'Save for offline'),
              subtitle: saved
                  ? null
                  : const Text('Keep it with its comments in Read later'),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                final offline = ref.read(offlineProvider.notifier);
                Navigator.pop(ctx);
                if (saved) {
                  await offline.remove(post.id);
                  _snack(messenger, 'Removed from Read later');
                  return;
                }
                _snack(messenger, 'Saving for offline…');
                try {
                  await offline.save(context, post);
                  _snack(messenger, 'Saved to Read later');
                } catch (e) {
                  _snack(messenger, "Couldn't save: ${friendlyError(e)}");
                }
              },
            );
          }),
          ListTile(
            leading: const Icon(Icons.content_copy_rounded),
            title: const Text('Copy text'),
            onTap: () {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(ctx);
              final text = post.isSelf && post.selftext.isNotEmpty
                  ? post.selftext
                  : post.title;
              Clipboard.setData(ClipboardData(text: text));
              _snack(messenger, 'Copied');
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
            leading: const Icon(Icons.block_flipped),
            title: Text('Block u/${post.author}'),
            onTap: () {
              Navigator.pop(ctx);
              confirmBlockUser(context, ref, post.author);
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
          const Divider(height: 8),
          ListTile(
            leading: const Icon(Icons.auto_awesome_rounded),
            title: const Text('Tune For You'),
            subtitle: Text('Why it\'s here · more or less like it · mute '
                'r/${post.subreddit}'),
            onTap: () {
              Navigator.pop(ctx);
              showTuneSheet(context, ref, post);
            },
          ),
        ],
        ),
      ),
    ),
    ),
  );
}

/// "Already seen elsewhere" (read in the official app, on the web…): marks
/// it read, so For You treats it as opened and won't bring it back, and drops
/// it from the feeds on screen. Local only — Reddit isn't told.
void alreadySeen(BuildContext context, WidgetRef ref, Post post) {
  final history = ref.read(historyControllerProvider.notifier);
  final hidden = ref.read(hiddenPostsProvider.notifier);
  final wasRead = ref.read(historyContainsProvider(post.id));
  history.markViewed(post);
  hidden.add(post.id);
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(SnackBar(
    content: const Text('Marked as seen'),
    action: SnackBarAction(
      label: 'Undo',
      onPressed: () {
        hidden.remove(post.id);
        if (!wasRead) history.removeViewed(post.id);
      },
    ),
  ));
}

/// Hides [post] on Reddit and in the open feeds (for Settings → Hide posts
/// for), with Undo.
Future<void> hidePost(BuildContext context, WidgetRef ref, Post post) async {
  final messenger = ScaffoldMessenger.of(context);
  final repo = ref.read(redditRepositoryProvider);
  final hidden = ref.read(hiddenPostsProvider.notifier);
  final learner = ref.read(forYouLearnerProvider);
  hidden.add(post.id);
  try {
    await repo.setHidden(post.fullname, true);
    learner.hidePost(post); // a clear "not for me"
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(
      content: const Text('Post hidden'),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () async {
          hidden.remove(post.id);
          learner.hidePost(post, undo: true);
          try {
            await repo.setHidden(post.fullname, false);
          } catch (_) {/* best effort */}
        },
      ),
    ));
  } catch (e) {
    hidden.remove(post.id);
    _snack(messenger, "Couldn't hide: ${friendlyError(e)}");
  }
}

Widget _modTile(WidgetRef ref, Post post, String label, IconData icon,
    Future<void> Function(dynamic repo) action, String done) {
  return Builder(builder: (ctx) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      onTap: () {
        final messenger = ScaffoldMessenger.of(ctx);
        Navigator.pop(ctx);
        modAction(messenger, ref, done, action);
      },
    );
  });
}

/// Runs a moderator action and reports the outcome. True when it went
/// through.
Future<bool> modAction(ScaffoldMessengerState messenger, WidgetRef ref,
    String doneMsg, Future<void> Function(dynamic repo) action) async {
  try {
    await action(ref.read(redditRepositoryProvider));
    _snack(messenger, doneMsg);
    return true;
  } on RedditApiException catch (e) {
    _snack(
        messenger,
        e.statusCode == 403
            ? "Reddit refused that. If you moderate this community, "
                'sign out and back in so Ilay can request moderator '
                'permission.'
            : friendlyError(e));
  } catch (e) {
    _snack(messenger, friendlyError(e));
  }
  return false;
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

/// Confirms and blocks a user. Reusable from posts, comments, and profiles.
Future<void> confirmBlockUser(
    BuildContext context, WidgetRef ref, String username) async {
  if (username.isEmpty || username == '[deleted]') return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Block u/$username?'),
      content: const Text(
          "You won't see their posts, comments, or messages anymore. You can "
          'unblock them later in Reddit settings.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Block')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(redditRepositoryProvider).blockUser(username);
    _snack(messenger, 'Blocked u/$username');
  } catch (e) {
    _snack(messenger, 'Could not block: $e');
  }
}

void _snack(ScaffoldMessengerState messenger, String msg) {
  messenger.showSnackBar(
      SnackBar(content: Text(msg.replaceFirst('Exception: ', ''))));
}

/// Snackbar for a personalization change, with a "Manage" action that opens the
/// Manage For You screen where it can be reviewed/undone.
