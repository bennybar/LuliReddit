import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/reddit_constants.dart';
import '../../core/theme/motion.dart';
import '../settings/settings_controller.dart';

/// One release's highlights, as shown in What's new.
class Release {
  const Release(this.version, this.date, this.highlights);
  final String version;
  final String date;
  final List<String> highlights;
}

/// What's new, newest first: the notable changes of each release since Ilay
/// 2.0 (the native app, with Reddit Home). Add the new release at the top
/// with every release.
// TODO(whats-new): this is the Kotlin app's list as-is; it describes the
// features being ported. Replace it with the iOS app's own releases.
const changelog = [
  Release('2.0.45', 'Oct 30, 2026', [
    'Explore: the people you follow have their own Following section, and '
        'open their profile',
  ]),
  Release('2.0.44', 'Oct 30, 2026', [
    'Profiles: sort posts and comments by New, Hot or Top, and the profile '
        'header slides away as you scroll',
    'Custom feed share links (reddit.com/u/…/s/…) open the feed, not the user',
    'Swiping a comment in the Calm style slides it over the vote icon like a '
        'card, instead of tinting it',
  ]),
  Release('2.0.43', 'Oct 29, 2026', [
    'Translate posts, comments and AI summaries: on the post, in a comment\'s '
        '⋯ menu, into your phone\'s language or a second one (Settings → '
        'Translation). On the phone where it can, else with your OpenAI key or '
        'Azure Translator',
    'Reddit Home and Blend load again with the website sign-in, with their '
        'galleries, videos and GIFs, and Home no longer falls back to For You '
        'after a while away',
    'Quarantined and restricted communities: "View anyway" right in Ilay',
    'Comments: collapse only the replies, and an edge marks the ones you '
        'voted on (Settings → Posts & comments)',
    'Preview a reply before sending it',
    'Clear cache now empties images too and shows how much it frees',
    'With the website sign-in, feeds, comments, votes and saves switch to '
        'Reddit\'s app API if the website refuses them',
  ]),
  Release('2.0.41', 'Oct 28, 2026', [
    'Search works again with the website sign-in (Reddit had started '
        'refusing it)',
    'Share a Reddit post to "Summarize with Ilay": its AI summary opens over '
        'the app you\'re in',
    '"Open in Ilay" in the share menu opens a shared post in Ilay',
    'A search tab Reddit refuses no longer hides the other tabs\' results',
  ]),
  Release('2.0.40', 'Oct 26, 2026', [
    'Galleries in your feeds use the carousel too (turn it off in Settings → '
        'Media → Gallery carousel in feeds)',
  ]),
  Release('2.0.39', 'Oct 26, 2026', [
    'Material 3 Expressive menus: grouped, with the current choice '
        'highlighted (Display, sort, comment ⋯)',
    'Join, Follow, Save and favourite stars are real toggles that change '
        'shape when on',
    'For You mix slider fills from the middle, so you see which way it leans',
    "Buttons' corners tighten as you press them (dialogs, Retry, back, ☰, ⚙)",
    'One pick-one style everywhere: post type, sign-in method, feed privacy',
    'Better with screen readers: tabs, votes, layouts, toggles and the video '
        'seek bar announce their state',
    'Galleries: a fling skips several images, and each image is labelled',
  ]),
  Release('2.0.38', 'Oct 26, 2026', [
    "Connected button groups: the Inbox filters, Search sort and Explore's "
        'Popular / All',
    'Polls show as one segmented list',
    "The side bar's ☰ sits in exactly the same spot on every tab",
  ]),
  Release('2.0.37', 'Oct 25, 2026', [
    'Material 3 Expressive loading: morphing-shape indicators everywhere Ilay '
        'is loading, including pull to refresh',
    'Saving media shows a wavy progress bar',
  ]),
  Release('2.0.36', 'Oct 25, 2026', [
    'User flairs show their emoji (club badges and the like), not just their '
        'text',
    'Calm layout: images and links have evenly rounded corners',
  ]),
  Release('2.0.35', 'Oct 25, 2026', [
    'Gallery posts open as a Material 3 carousel: one big image with the next '
        'ones peeking beside it',
    'Bottom bar outline can be turned off (Settings → Appearance)',
  ]),
  Release('2.0.34', 'Oct 25, 2026', [
    "User flairs next to names in posts and comments, and set your own flair "
        "from a community's About",
    'Custom feeds: one screen with all of them, rename, describe, make public '
        "or private, share, copy someone's public feed, and tap a community to "
        'open it',
    'A ⚙ button opens Settings directly; the Expandable top bar gets a search '
        'button',
    'Neater ☰ alignment and a cleaner New post icon',
  ]),
  Release('2.0.33', 'Oct 22, 2026', [
    "And the other way: replies you opened in Reddit's notifications show as "
        "read in Ilay's Inbox (website sign-in)",
  ]),
  Release('2.0.32', 'Oct 22, 2026', [
    'With the website sign-in, replies you read in the Inbox are marked read '
        "in Reddit's notifications too (and Mark all read clears them there)",
  ]),
  Release('2.0.31', 'Oct 22, 2026', [
    'With the side bar on, swiping back on the main screen opens it, and back '
        'again closes it',
  ]),
  Release('2.0.30', 'Oct 22, 2026', [
    "What's new: this list, once after each update, and any time in Settings "
        '→ About',
    'Side bar navigation: Settings → Appearance → Navigation (bottom bar, side '
        'bar, or both)',
  ]),
  Release('2.0.29', 'Oct 21, 2026', [
    'AI summaries work with other providers (Groq, OpenRouter…) and any model '
        'ID',
    "Add a community to a custom feed from a post's ⋮ menu or the community's "
        'top bar',
    'Autoplay with sound, for feed videos (Settings → Media)',
  ]),
  Release('2.0.26 – 2.0.28', 'Oct 18, 2026', [
    'Remind me about a saved post: pick when, get a notification, and see the '
        'reminder on the post',
  ]),
  Release('2.0.24 – 2.0.25', 'Oct 17, 2026', [
    "Reddit's own notifications in the Inbox (website sign-in), with unread "
        'dots and older ones',
    'When Reddit rate-limits you, Ilay says how long to wait',
    'Select and delete several summaries at once',
  ]),
  Release('2.0.22 – 2.0.23', 'Oct 17, 2026', [
    'Profile tab: your posts, comments, saved and upvoted, with your stuff a '
        'tap away',
    'Settings moved to the ⋮ menu at the top of each tab',
    "Reddit Chat, voting in polls and Reddit's account settings (website "
        'sign-in)',
    'Poll results and your vote show in the post',
  ]),
  Release('2.0.20 – 2.0.21', 'Oct 17, 2026', [
    'Your votes stick when you go back into a thread or your profile',
    'Blend: choose Mostly Ilay, Balanced or Mostly Reddit',
    'Already seen elsewhere: drop a post you read in another app',
  ]),
  Release('2.0.19', 'Oct 17, 2026', [
    'Android 13 support',
    'Follow users',
    'Hide or dim read posts in more places',
  ]),
  Release('2.0.15 – 2.0.18', 'Oct 16, 2026', [
    'For You is out of beta and learns from more of what you do',
    'Familiar ↔ Discover: how adventurous For You should be',
    'Blend (Beta): your Reddit Home ranked by For You',
  ]),
  Release('2.0.11 – 2.0.14', 'Oct 16, 2026', [
    'Notification activity, Drafts and Ask AI about a thread',
    'Volume keys jump between comments; saved searches; collapse settings',
    'Smoother scrolling past GIFs in threads',
  ]),
  Release('2.0.1 – 2.0.7', 'Oct 14, 2026', [
    'Smoother scrolling in image-heavy feeds',
    'GIFs and stickers from your keyboard in replies and messages',
    'Hide a community from your front page, or filter it out everywhere',
    'Back never leaves the app from the main screen',
  ]),
  Release('2.0.0', 'Oct 12, 2026', [
    'Ilay rebuilt as a native Android app: faster, smoother, same data',
    'Reddit Home (experimental): your real reddit.com Home feed',
  ]),
];

const _seenPref = 'whatsNewSeen';

List<int> _parts(String v) =>
    [for (final p in v.split(' ').first.split('.')) int.tryParse(p) ?? 0];

/// Whether release [a] (its first version, for a range) is newer than
/// version [b].
bool newerVersion(String a, String b) {
  final x = _parts(a), y = _parts(b);
  for (var i = 0; i < (x.length > y.length ? x.length : y.length); i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d > 0;
  }
  return false;
}

/// Once after an update: what changed since the version you last saw here
/// (or this release's, the first time). Never on a fresh install.
Future<void> maybeShowWhatsNew(BuildContext context, WidgetRef ref) async {
  const current = RedditConstants.appVersion;
  final prefs = ref.read(sharedPrefsProvider);
  final seen = prefs.getString(_seenPref);
  await prefs.setString(_seenPref, current);
  if (seen == current) return;
  final List<Release> releases;
  if (seen == null) {
    // iOS has no install / update times: an install that already ran the
    // home shell answered the notifications suggestion (which comes after
    // this), so it's an update; otherwise it's a fresh install, and nothing
    // is "new".
    final ranBefore = (prefs.getBool('notifyInboxPrompted') ?? false) ||
        ref.read(settingsControllerProvider).notifyInbox;
    if (!ranBefore) return;
    releases = changelog.take(1).toList();
  } else {
    releases = changelog
        .where((r) => newerVersion(r.version.split(' ').last, seen))
        .take(3)
        .toList();
  }
  if (releases.isEmpty || !context.mounted) return;
  final router = GoRouter.of(context);
  final all = await showModalBottomSheet<bool>(
    context: context,
    sheetAnimationStyle: sheetMotion,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("What's new in Ilay $current",
                  style: Theme.of(ctx)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              for (final r in releases)
                _ReleaseNotes(release: r, showVersion: releases.length > 1),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('All changes')),
                    const SizedBox(width: 8),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Got it')),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (all == true) router.push('/whats_new');
}

class _ReleaseNotes extends StatelessWidget {
  const _ReleaseNotes({required this.release, this.showVersion = true});
  final Release release;
  final bool showVersion;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showVersion) ...[
            Row(
              children: [
                Text(release.version,
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: cs.primary)),
                const SizedBox(width: 8),
                Text(release.date,
                    style:
                        TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 6),
          ],
          for (final h in release.highlights)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('•', style: TextStyle(color: cs.primary)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(h)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Settings → About → What's new: every release's highlights.
class WhatsNewScreen extends StatelessWidget {
  const WhatsNewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text("What's new")),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
        itemCount: changelog.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => Container(
          key: ValueKey(changelog[i].version),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(28),
          ),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
          child: _ReleaseNotes(release: changelog[i]),
        ),
      ),
    );
  }
}
