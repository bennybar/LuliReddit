import 'dart:convert';
import 'dart:io' show Directory, File, Platform;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_icon.dart';
import '../../core/backup.dart';
import '../../core/network/rate_limit.dart';
import '../../core/theme/motion.dart';
import '../../core/widgets/pick_one_menu.dart';
import '../../data/ai_service.dart';
import '../post/comments_controller.dart' show commentSorts, commentSortLabels;
import '../../core/providers.dart';
import '../../core/reddit_constants.dart';
import '../../data/reddit_repository.dart';
import '../auth/auth_controller.dart';
import '../feed/expiring_ids.dart';
import '../feed/swipe_actions.dart';
import '../media/media_folder.dart';
import '../notifications/inbox_poller.dart';
import '../notifications/notification_service.dart';
import '../updates/update_checker.dart';
import 'settings_controller.dart';

/// Summary languages: (English name the prompt uses, label). '' = the
/// thread's own.
const _summaryLanguages = [
  ('', 'Same as the thread'),
  ('English', 'English'),
  ('Hebrew', 'Hebrew · עברית'),
  ('Spanish', 'Spanish · Español'),
  ('French', 'French · Français'),
  ('German', 'German · Deutsch'),
  ('Portuguese', 'Portuguese · Português'),
  ('Italian', 'Italian · Italiano'),
  ('Russian', 'Russian · Русский'),
  ('Arabic', 'Arabic · العربية'),
  ('Simplified Chinese', 'Chinese · 中文'),
  ('Japanese', 'Japanese · 日本語'),
  ('Hindi', 'Hindi · हिन्दी'),
];

/// Blend's Reddit ↔ Ilay presets, by persisted index (`blendReddit`).
const _blendPresets = [
  ('Mostly Ilay', "Reddit's picks get a small nudge, no reserved spots"),
  ('Balanced', 'About 1 post in 5 is from your Reddit Home'),
  ('Mostly Reddit', 'About 1 in 3 from your Reddit Home, and they count more'),
];

/// Settings › Navigation, by persisted index (`navStyle`). iOS has no back
/// gesture on the main screen, so the side bar comes out with an edge swipe.
const _navStyles = [
  ('Bottom bar', 'The floating bar at the bottom'),
  ('Side bar',
      'The ☰ at the top of each tab, or swipe from the left edge, opens it'),
  ('Both', 'The bottom bar, plus the side bar (☰ or edge swipe)'),
];

const _accentSwatches = <Color>[
  Color(0xFF6750A4), // Bloom lavender (default)
  Color(0xFFEA4335), // red
  Color(0xFFFF7043), // orange
  Color(0xFFFFB300), // amber
  Color(0xFF34A853), // green
  Color(0xFF00897B), // teal
  Color(0xFF1E88E5), // blue
  Color(0xFF8E24AA), // purple
  Color(0xFFD81B60), // pink
];

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: const SettingsList(),
      );
}

/// The settings list — reusable both as the full Settings screen and
/// embedded. Pass [embedded] when nesting in a scroll view.
class SettingsList extends ConsumerStatefulWidget {
  const SettingsList({super.key, this.embedded = false});
  final bool embedded;

  @override
  ConsumerState<SettingsList> createState() => _SettingsListState();
}

class _SettingsListState extends ConsumerState<SettingsList> {
  String _query = '';

  /// Searches a tile's title/subtitle text. Non-tile widgets (dividers,
  /// sliders, section headers) are dropped from search results.
  bool _matches(Widget w, String q) {
    String t(Object? x) => x is Text ? (x.data ?? '') : '';
    String text;
    if (w is ListTile) {
      text = '${t(w.title)} ${t(w.subtitle)}';
    } else if (w is SwitchListTile) {
      text = '${t(w.title)} ${t(w.subtitle)}';
    } else {
      return false;
    }
    return text.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsControllerProvider);
    final ctrl = ref.read(settingsControllerProvider.notifier);
    final cs = Theme.of(context).colorScheme;
    final aiKeySet =
        ref.watch(openAiKeyProvider).valueOrNull?.isNotEmpty ?? false;

    final all = <Widget>[
          _section(context, 'Feed'),
          ListTile(
            leading: Icon(s.postDisplay.icon),
            title: const Text('Post display'),
            subtitle: Text(s.postDisplay.label),
            onTap: () => _pickDisplay(context, ctrl, s.postDisplay),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.image_rounded),
            title: const Text('Subreddit icons'),
            subtitle: const Text(
                "Show each community's icon on posts instead of its first "
                'letter'),
            value: s.subredditIcons,
            onChanged: ctrl.setSubredditIcons,
          ),
          ListTile(
            leading: const Icon(Icons.sort_rounded),
            title: const Text('Default sort'),
            subtitle: Text(s.defaultSort.label),
            onTap: () => _pickSort(context, ctrl, s.defaultSort),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.auto_awesome_rounded),
            title: const Text('"For You" feed'),
            subtitle: const Text('A personalized frontpage, built on your '
                'phone from what you read and like'),
            value: s.forYouFeed,
            onChanged: ctrl.setForYouFeed,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.mark_email_read_outlined),
            title: const Text('Auto-hide read items in "For You"'),
            subtitle: const Text('Hide posts you\'ve marked/opened as read'),
            value: s.autoHideReadForYou,
            onChanged: ctrl.setAutoHideReadForYou,
          ),
          _ForYouMixSlider(
              value: s.forYouDiscovery, onChanged: ctrl.setForYouDiscovery),
          ListTile(
            leading: const Icon(Icons.tune_rounded),
            title: const Text('Manage "For You" subreddits'),
            subtitle: const Text('Review and undo muted / show-less subreddits'),
            onTap: () => context.push('/manage_for_you'),
          ),
          Builder(builder: (context) {
            final web = ref.watch(authModeProvider).valueOrNull == 'web';
            final amber = _homeAmber(context);
            return SwitchListTile(
              secondary: Icon(Icons.warning_amber_rounded, color: amber),
              title: Text('Reddit Home (experimental)',
                  style: TextStyle(color: amber)),
              subtitle: Text(
                  web
                      ? 'Unofficial, against Reddit\'s terms. Shows your real '
                          'reddit.com Home'
                      : 'Needs website sign-in',
                  style: TextStyle(color: amber)),
              activeTrackColor: amber,
              activeThumbColor: Theme.of(context).colorScheme.onError,
              value: s.redditHomeAllowed,
              onChanged: !web && !s.redditHomeAllowed
                  ? null
                  : (v) async {
                      if (!v) return ctrl.setRedditHomeAllowed(false);
                      if (await _confirmRedditHome(context)) {
                        ctrl.setRedditHomeAllowed(true);
                      }
                    },
            );
          }),
          if (s.redditHomeAllowed)
            SwitchListTile(
              secondary: const Icon(Icons.merge_rounded),
              title: const Text('Blend (Beta)'),
              subtitle: const Text('For You also ranks your Reddit Home: '
                  "Reddit's recommendations, under your For You choices"),
              value: s.forYouFeed && s.blendHome,
              onChanged: (v) {
                ctrl.setBlendHome(v);
                if (v) ctrl.setForYouFeed(true);
              },
            ),
          if (s.redditHomeAllowed && s.forYouFeed && s.blendHome)
            ListTile(
              leading: const Icon(Icons.merge_rounded),
              title: const Text('Reddit ↔ Ilay'),
              subtitle: Text('${_blendPresets[s.blendReddit].$1}: '
                  '${_blendPresets[s.blendReddit].$2[0].toLowerCase()}'
                  '${_blendPresets[s.blendReddit].$2.substring(1)}'),
              onTap: () =>
                  _pickBlend(context, s.blendReddit, ctrl.setBlendReddit),
            ),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Keep feed for'),
            subtitle: Text('Home / For You: ${_keepLabel(s.feedKeepMinutes)}, '
                'then a new feed (pull down to refresh anytime)'),
            onTap: () => _pickInt(context, s.feedKeepMinutes,
                const [10, 30, 60, 180], _keepLabel, ctrl.setFeedKeepMinutes),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.visibility_off_outlined),
            title: const Text('Hide read posts'),
            subtitle: const Text(
                'Skip posts you\'ve already read when your front page and '
                'custom feeds load or refresh'),
            value: s.hideReadPosts,
            onChanged: ctrl.setHideReadPosts,
          ),
          if (s.hideReadPosts)
            SwitchListTile(
              secondary: const Icon(Icons.visibility_off_outlined),
              title: const Text('Also in subreddits'),
              subtitle: const Text(
                  'Hide read posts when browsing a single subreddit too'),
              value: s.hideReadInSubreddits,
              onChanged: ctrl.setHideReadInSubreddits,
            ),
          SwitchListTile(
            secondary: const Icon(Icons.done_all_rounded),
            title: const Text('Mark read as you scroll'),
            subtitle: Text(s.trackHistory
                ? 'A post you scroll past counts as read'
                : 'Needs history tracking turned on'),
            value: s.markReadOnScroll,
            onChanged: s.trackHistory ? ctrl.setMarkReadOnScroll : null,
          ),
          ListTile(
            leading: const Icon(Icons.filter_alt_outlined),
            title: const Text('Content filters'),
            subtitle: const Text(
                'Hide posts by keyword, domain, flair or subreddit'),
            onTap: () => context.push('/content_filters'),
          ),
          ListTile(
            leading: const Icon(Icons.visibility_off_outlined),
            title: const Text('Hide posts for'),
            subtitle: Text('Posts you hide stay out of every feed for '
                '${_dayLabel(s.hiddenPostDays)}'),
            onTap: () => _pickInt(context, s.hiddenPostDays,
                const [1, 3, 7, 30, 90], _dayLabel, (v) {
              ctrl.setHiddenPostDays(v);
              ref.read(hiddenPostsProvider.notifier).refresh();
            }),
          ),
          Builder(builder: (context) {
            final n = ref.watch(hiddenHomeSubsProvider).length;
            return ListTile(
              leading: const Icon(Icons.do_not_disturb_on_rounded),
              title: const Text('Hidden subreddits'),
              subtitle: Text('Hidden from your front page for 7 days'
                  '${n == 0 ? ' · none now' : ' · $n now'}'),
              onTap: () => showDialog<void>(
                  context: context, builder: (_) => const _HiddenSubsDialog()),
            );
          }),
          const Divider(),
          _section(context, 'Appearance'),
          ListTile(
            leading: const Icon(Icons.brightness_6_rounded),
            title: const Text('Theme'),
            subtitle: Text(switch (s.themeMode) {
              ThemeMode.system => 'Follow system',
              ThemeMode.light => 'Light',
              ThemeMode.dark => 'Dark',
            }),
            onTap: () => _pickTheme(context, ctrl, s.themeMode),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.dark_mode_rounded),
            title: const Text('AMOLED black'),
            subtitle: const Text('Pure black surfaces in dark mode'),
            value: s.amoled,
            onChanged: ctrl.setAmoled,
          ),
          ListTile(
            leading: const Icon(Icons.font_download_rounded),
            title: const Text('App font'),
            subtitle: Text(s.appFont.label),
            onTap: () => showModalBottomSheet(
              context: context,
              sheetAnimationStyle: sheetMotion,
              showDragHandle: true,
              builder: (ctx) => SafeArea(
                child: RadioGroup<AppFont>(
                  groupValue: s.appFont,
                  onChanged: (v) {
                    if (v != null) ctrl.setAppFont(v);
                    Navigator.pop(ctx);
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final f in AppFont.values)
                        RadioListTile<AppFont>(
                          value: f,
                          title: Text(f.label),
                          subtitle: Text(f.description),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.palette_rounded),
            title: const Text('Dynamic color'),
            subtitle: const Text('Use colors from your wallpaper'),
            value: s.useDynamicColor,
            onChanged: ctrl.setUseDynamicColor,
          ),
          Opacity(
            opacity: s.useDynamicColor ? 0.4 : 1,
            child: IgnorePointer(
              ignoring: s.useDynamicColor,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Accent color',
                        style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final c in _accentSwatches)
                          GestureDetector(
                            onTap: () => ctrl.setSeedColor(c.toARGB32()),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: s.seedColor == c.toARGB32()
                                      ? Theme.of(context).colorScheme.onSurface
                                      : Colors.transparent,
                                  width: 3,
                                ),
                              ),
                              child: s.seedColor == c.toARGB32()
                                  ? const Icon(Icons.check, color: Colors.white)
                                  : null,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          ListTile(
            leading: AppIconPreview(AppIcon.parse(s.appIcon)),
            title: const Text('App icon'),
            subtitle: Text(AppIcon.parse(s.appIcon).label),
            onTap: () async {
              final picked =
                  await _pickAppIcon(context, AppIcon.parse(s.appIcon));
              if (picked == null) return;
              ctrl.setAppIcon(picked.name);
              try {
                await AppIcon.apply(picked);
              } catch (_) {}
            },
          ),
          ListTile(
            leading: const Icon(Icons.format_size_rounded),
            title: const Text('Font size'),
            subtitle: Text('${(s.textScale * 100).round()}% of normal'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Row(
              children: [
                const Text('A', style: TextStyle(fontSize: 13)),
                Expanded(
                  child: Slider(
                    value: s.textScale,
                    min: 0.8,
                    max: 1.4,
                    divisions: 12,
                    label: '${(s.textScale * 100).round()}%',
                    onChanged: ctrl.setTextScale,
                  ),
                ),
                const Text('A', style: TextStyle(fontSize: 22)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'The quick brown fox jumps over the lazy dog.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.view_headline_rounded),
            title: const Text('Top bar'),
            subtitle: Text(s.topBarMode.label),
            onTap: () => _pickTopBar(context, ctrl, s.topBarMode),
          ),
          ListTile(
            leading: const Icon(Icons.menu_rounded),
            title: const Text('Navigation'),
            subtitle: Text(_navStyles[s.navStyle.clamp(0, 2)].$1),
            onTap: () => _pickNavStyle(context, ctrl, s.navStyle),
          ),
          if (s.navStyle != 1)
            SwitchListTile(
              secondary: const Icon(Icons.label_outline_rounded),
              title: const Text('Bottom bar labels'),
              subtitle:
                  const Text('Show text labels under the navigation icons'),
              value: s.navLabels,
              onChanged: ctrl.setNavLabels,
            ),
          if (s.navStyle != 1)
            SwitchListTile(
              secondary: const Icon(Icons.crop_free_rounded),
              title: const Text('Bottom bar outline'),
              subtitle: const Text('A thin outline around the bottom bar. '
                  'Off: just its shadow, Material 3 style'),
              value: s.navOutline,
              onChanged: ctrl.setNavOutline,
            ),
          const Divider(),
          _section(context, 'Posts & comments'),
          ListTile(
            leading: const Icon(Icons.forum_outlined),
            title: const Text('Default comment sort'),
            subtitle:
                Text(commentSortLabels[s.defaultCommentSort] ?? s.defaultCommentSort),
            onTap: () => _pickCommentSort(context, ctrl, s.defaultCommentSort),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.unfold_less_rounded),
            title: const Text('Tap a comment to collapse it'),
            subtitle: const Text(
                'Otherwise long-press. Comment text can\'t be selected while '
                'this is on'),
            value: s.tapToCollapse,
            onChanged: ctrl.setTapToCollapse,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.unfold_less_rounded),
            title: const Text('Collapse only the replies'),
            subtitle: const Text(
                'Collapsing a comment keeps its own text and hides its '
                'replies'),
            value: s.collapseRepliesOnly,
            onChanged: ctrl.setCollapseRepliesOnly,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.thumbs_up_down_rounded),
            title: const Text('Mark comments you voted on'),
            subtitle: const Text(
                'An edge in the vote\'s color on comments you upvoted or '
                'downvoted'),
            value: s.voteEdge,
            onChanged: ctrl.setVoteEdge,
          ),
          ListTile(
            leading: const Icon(Icons.unfold_less_rounded),
            title: const Text('Collapse low-scoring comments'),
            subtitle: Text(s.collapseBelowScore == null
                ? 'Off'
                : 'Comments below ${s.collapseBelowScore} points start '
                    'collapsed'),
            onTap: () =>
                _pickCollapseBelow(context, ctrl, s.collapseBelowScore),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.unfold_less_rounded),
            title: const Text('Open threads collapsed'),
            subtitle: const Text('Top-level comments show without their '
                'replies, each with a "Show replies" button'),
            value: s.collapseTopLevel,
            onChanged: ctrl.setCollapseTopLevel,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.swipe_rounded),
            title: const Text('Swipe actions'),
            subtitle: const Text('Swipe posts and comments sideways'),
            value: s.swipeActions,
            onChanged: ctrl.setSwipeActions,
          ),
          if (s.swipeActions)
            ListTile(
              leading: const SizedBox(width: 24),
              title: const Text('Customize swipes'),
              subtitle: Text(
                  'Posts: ${s.swipePostStart.label} / ${s.swipePostEnd.label} · '
                  'Comments: ${s.swipeCommentStart.label} / '
                  '${s.swipeCommentEnd.label}'),
              onTap: () => showModalBottomSheet<void>(
                context: context,
                sheetAnimationStyle: sheetMotion,
                showDragHandle: true,
                builder: (_) => const _SwipeSettingsSheet(),
              ),
            ),
          SwitchListTile(
            secondary: const Icon(Icons.open_in_browser_rounded),
            title: const Text('Open links inside the app'),
            subtitle: const Text(
                'Web links open in an in-app browser tab instead of your '
                'browser app'),
            value: s.inAppBrowser,
            onChanged: ctrl.setInAppBrowser,
          ),
          const Divider(),
          _section(context, 'Media'),
          SwitchListTile(
            secondary: const Icon(Icons.play_circle_outline_rounded),
            title: const Text('Autoplay videos'),
            subtitle: Text(s.autoplaySound
                ? 'Play videos as you scroll the feed'
                : 'Play videos muted as you scroll the feed'),
            value: s.autoplayMedia,
            onChanged: ctrl.setAutoplayMedia,
          ),
          if (s.autoplayMedia)
            SwitchListTile(
              secondary: const Icon(Icons.volume_up_rounded),
              title: const Text('Autoplay with sound'),
              subtitle: const Text(
                  'Feed videos start with sound; tap the speaker to mute one'),
              value: s.autoplaySound,
              onChanged: ctrl.setAutoplaySound,
            ),
          SwitchListTile(
            secondary: const Icon(Icons.view_carousel_rounded),
            title: const Text('Gallery carousel in feeds'),
            subtitle: const Text('Galleries show a big image with the next '
                'ones beside it. Off: one image at a time'),
            value: s.feedGalleryCarousel,
            onChanged: ctrl.setFeedGalleryCarousel,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.blur_on_rounded),
            title: const Text('Blur NSFW media'),
            subtitle: const Text('Tap to reveal blurred images'),
            value: s.blurNsfw,
            onChanged: ctrl.setBlurNsfw,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.image_outlined),
            title: const Text('Data-saver thumbnails'),
            subtitle: const Text(
                'Load smaller preview images in feeds (faster, less data)'),
            value: s.midResThumbnails,
            onChanged: ctrl.setMidResThumbnails,
          ),
          if (Platform.isAndroid) const _MediaFolderTile(),
          const Divider(),
          _section(context, 'Notifications'),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_active_outlined),
            title: const Text('Inbox notifications'),
            subtitle: const Text(
                'Check for replies & messages in the background (~every 15 min) '
                'and notify you. No Firebase — polling only.'),
            value: s.notifyInbox,
            onChanged: (v) => _toggleInboxNotifications(context, ref, v),
          ),
          ListTile(
            leading: const Icon(Icons.history_rounded),
            title: const Text('Notification activity'),
            subtitle: const Text("What Ilay notified you about, what it "
                "couldn't, and why · Check now"),
            onTap: () => context.push('/notification_activity'),
          ),
          const Divider(),
          _section(context, 'AI summaries'),
          ListTile(
            leading: const Icon(Icons.key_rounded),
            // With a custom endpoint the key is that provider's (Groq,
            // OpenRouter, a LiteLLM key…).
            title: Text(s.aiUseCustomUrl ? 'API key' : 'OpenAI API key'),
            subtitle: Text(aiKeySet
                ? 'Key set — tap to change or remove'
                : 'Add a key to enable thread summaries'),
            onTap: () =>
                _editOpenAiKey(context, ref, aiKeySet, s.aiUseCustomUrl),
          ),
          ListTile(
            enabled: aiKeySet,
            leading: const Icon(Icons.smart_toy_outlined),
            title: const Text('Model'),
            subtitle: Text(s.aiModel),
            onTap: () => _pickAiModel(context, ctrl, s.aiModel),
          ),
          ListTile(
            enabled: aiKeySet,
            leading: const Icon(Icons.auto_awesome_rounded),
            title: const Text('Summary style'),
            subtitle: Text(SummaryStyle
                .values[s.aiSummaryStyle.clamp(0, SummaryStyle.values.length - 1)]
                .label),
            onTap: () => _pickAiStyle(context, ctrl, s.aiSummaryStyle),
          ),
          ListTile(
            enabled: aiKeySet,
            leading: const Icon(Icons.translate_rounded),
            title: const Text('Summary language'),
            subtitle: Text(_summaryLanguages
                    .where((l) => l.$1 == s.aiSummaryLanguage)
                    .firstOrNull
                    ?.$2 ??
                s.aiSummaryLanguage),
            onTap: () =>
                _pickSummaryLanguage(context, ctrl, s.aiSummaryLanguage),
          ),
          ListTile(
            enabled: aiKeySet,
            leading: const Icon(Icons.straighten_rounded),
            title: const Text('Max thread size'),
            subtitle: Text('${(s.aiMaxChars / 1000).round()}k characters '
                '(~${(s.aiMaxChars / 4000).round()}k tokens)'),
            onTap: () => _pickAiMaxChars(context, ctrl, s.aiMaxChars),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.dns_rounded),
            title: const Text('Custom API base URL'),
            subtitle: const Text('Advanced — use an OpenAI-compatible '
                'endpoint (e.g. Groq, OpenRouter, LiteLLM)'),
            value: s.aiUseCustomUrl,
            onChanged: ctrl.setAiUseCustomUrl,
          ),
          if (s.aiUseCustomUrl)
            ListTile(
              leading: const Icon(Icons.link_rounded),
              title: const Text('API base URL'),
              subtitle: Text(s.aiBaseUrl),
              onTap: () => _editAiBaseUrl(context, ctrl, s.aiBaseUrl),
            ),
          const Divider(),
          _section(context, 'Data & storage'),
          SwitchListTile(
            secondary: const Icon(Icons.visibility_outlined),
            title: const Text('Track history'),
            subtitle: const Text('Remember and dim viewed posts (local only)'),
            value: s.trackHistory,
            onChanged: ctrl.setTrackHistory,
          ),
          if (s.trackHistory)
            ListTile(
              leading: const Icon(Icons.visibility_outlined),
              title: const Text('Dim read posts'),
              subtitle: Text(s.dimReadTextOnly
                  ? 'Text only: titles and text fade, images stay bright'
                  : 'Whole card'),
              onTap: () => _pickDimRead(context, ctrl, s.dimReadTextOnly),
            ),
          SwitchListTile(
            secondary: const Icon(Icons.cloud_off_rounded),
            title: const Text('Offline cache'),
            subtitle:
                const Text('Show the last loaded content when offline'),
            value: s.offlineCache,
            onChanged: ctrl.setOfflineCache,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.dns_outlined),
            title: const Text('Cache subscriptions'),
            subtitle: const Text(
                'Keep your subreddit list in memory to speed up "For You"'),
            value: s.subsCacheEnabled,
            onChanged: ctrl.setSubsCacheEnabled,
          ),
          ListTile(
            enabled: s.subsCacheEnabled,
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Subscriptions cache time'),
            subtitle: Text('${s.subsCacheMinutes} minutes'),
            onTap: () => _pickCacheMinutes(context, ctrl, s.subsCacheMinutes),
          ),
          // What Ilay keeps in its cache folder: saved pages and images.
          StatefulBuilder(
            builder: (context, setTile) => FutureBuilder<int>(
              future: cacheBytes(),
              builder: (context, size) => ListTile(
                leading: const Icon(Icons.cached_rounded),
                title: const Text('Clear cache'),
                subtitle: size.data == null
                    ? null
                    : Text('${size.data! >> 20} MB of saved pages and images'),
                onTap: () async {
                  await ref.read(redditClientProvider).clearCache();
                  await DefaultCacheManager().emptyCache();
                  PaintingBinding.instance.imageCache.clear();
                  setTile(() {});
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Cache cleared')));
                  }
                },
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: const Text('Back up data'),
            subtitle: const Text(
                'Export settings, For You model & history (no login/keys)'),
            onTap: () => _backupData(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.restore_rounded),
            title: const Text('Restore data'),
            subtitle: const Text('Import a backup file'),
            onTap: () => _restoreData(context, ref),
          ),
          const Divider(),
          _section(context, 'Account & keys'),
          ListTile(
            leading: Icon(ref.watch(authModeProvider).valueOrNull == 'web'
                ? Icons.public_rounded
                : Icons.api_rounded),
            title: const Text('Login method'),
            subtitle: Text(ref.watch(authModeProvider).valueOrNull == 'web'
                ? 'Website session (no API key) — unofficial'
                : 'Reddit API key (recommended)'),
            onTap: () => _showLoginMethodInfo(
                context, ref.read(authModeProvider).valueOrNull == 'web'),
          ),
          if (ref.watch(authModeProvider).valueOrNull == 'web')
            ListTile(
              leading: const Icon(Icons.manage_accounts_rounded),
              title: const Text('Reddit account settings'),
              subtitle: const Text("Reddit's own settings: Home "
                  'recommendations, notifications, muted communities'),
              onTap: () => context.push(Uri(path: '/reddit_web',
                  queryParameters: {
                    'url': 'https://www.reddit.com/settings',
                    'title': 'Reddit settings',
                  }).toString()),
            ),
          ListTile(
            leading: const Icon(Icons.vpn_key_rounded),
            title: const Text('Reddit API credentials'),
            subtitle: const Text('Re-enter your Client ID / Redirect URI'),
            onTap: () => _reenterCredentials(context, ref),
          ),
          ListTile(
            leading: Icon(Icons.delete_forever_rounded,
                color: Theme.of(context).colorScheme.error),
            title: Text('Clear all data',
                style:
                    TextStyle(color: Theme.of(context).colorScheme.error)),
            subtitle: const Text('Wipes credentials, tokens and login'),
            onTap: () => _clearAll(context, ref),
          ),
          const Divider(),
          _section(context, 'Power-user features'),
          SwitchListTile(
            secondary: const Icon(Icons.speed_rounded),
            title: const Text('Show API usage instead of search'),
            subtitle: const Text(
                'Replace the search bar on the Posts screen with your live '
                'Reddit API rate-limit usage'),
            value: s.showApiUsage,
            onChanged: ctrl.setShowApiUsage,
          ),
          _RateLimitTile(),
          const Divider(),
          _section(context, 'About'),
          ListTile(
            leading: const Icon(Icons.new_releases_rounded),
            title: const Text("What's new"),
            subtitle: const Text('Ilay ${RedditConstants.appVersion} · what '
                'changed in each release'),
            onTap: () => context.push('/whats_new'),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.system_update_rounded),
            title: const Text('Check for updates'),
            subtitle: const Text('Check GitHub releases on launch'),
            value: s.checkUpdates,
            onChanged: ctrl.setCheckUpdates,
          ),
          ListTile(
            leading: const Icon(Icons.update_rounded),
            title: const Text('Check now'),
            onTap: () => _checkUpdatesNow(context, ref),
          ),
          const ListTile(
            leading: Icon(Icons.link_rounded),
            title: Text('Open reddit links in Ilay'),
            subtitle: Text(
                'Already supported via the Android "open with" chooser. To make '
                'Ilay the verified default, enable it under system app settings '
                '› Open by default.'),
          ),
          ListTile(
            leading: const Icon(Icons.gavel_rounded),
            title: const Text('Content & conduct policy'),
            onTap: () => context.push('/policy'),
          ),
          const SizedBox(height: 24),
    ];

    final q = _query.trim().toLowerCase();
    final shown = q.isEmpty ? all : all.where((w) => _matches(w, q)).toList();
    return ListView(
      shrinkWrap: widget.embedded,
      physics: widget.embedded ? const NeverScrollableScrollPhysics() : null,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search settings',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: cs.surfaceContainerHigh,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        ...shown,
        if (q.isNotEmpty && shown.isEmpty)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: Text('No settings found')),
          ),
      ],
    );
  }

  Future<void> _backupData(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    // Anchor the iOS/iPad share popover to a valid on-screen rect. (Using the
    // settings ListView's render box gave an off-screen rect when scrolled,
    // which iOS rejects.)
    final size = MediaQuery.of(context).size;
    final origin =
        Rect.fromCenter(center: size.center(Offset.zero), width: 40, height: 40);
    try {
      final json = Backup.export(ref.read(sharedPrefsProvider));
      final path = await Backup.writeTempFile(json);
      await Share.shareXFiles([XFile(path)],
          subject: 'Ilay backup', sharePositionOrigin: origin);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Backup failed: $e')));
    }
  }

  Future<void> _restoreData(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (res == null) return;
      final bytes = res.files.single.bytes;
      if (bytes == null) return;
      final n =
          await Backup.import(ref.read(sharedPrefsProvider), utf8.decode(bytes));
      if (!context.mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Restore complete'),
          content: Text(
              'Imported $n settings. Restart Ilay to apply everything.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Restore failed: $e')));
    }
  }

  Future<void> _checkUpdatesNow(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Checking…')));
    final info = await UpdateChecker().check();
    if (!context.mounted) return;
    if (info == null) {
      messenger.showSnackBar(SnackBar(
          content: Text(
              "You're on the latest version (${RedditConstants.appVersion}).")));
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Update available — v${info.version}'),
        content: const Text('A newer version is available on GitHub.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Later')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              launchUrl(Uri.parse(info.apkUrl ?? info.url),
                  mode: LaunchMode.externalApplication);
            },
            child: const Text('Download'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleInboxNotifications(
      BuildContext context, WidgetRef ref, bool enable) async {
    final ctrl = ref.read(settingsControllerProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    if (!enable) {
      ctrl.setNotifyInbox(false);
      await cancelInboxPolling();
      return;
    }
    final granted = await NotificationService.instance.requestPermission();
    if (!granted) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Notification permission denied. Enable it in system '
              'settings to get inbox alerts.')));
      return;
    }
    ctrl.setNotifyInbox(true);
    // Prime the "seen" set with current unread so turning this on doesn't fire a
    // notification for every pre-existing item, then start the periodic poll.
    await pollInbox(notify: false);
    await registerInboxPolling();
    messenger.showSnackBar(const SnackBar(
        content: Text('Inbox notifications on. Reddit is checked about every '
            '15 minutes.')));
  }

  Widget _section(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w700,
                )),
      );

  Future<AppIcon?> _pickAppIcon(BuildContext context, AppIcon current) =>
      showModalBottomSheet<AppIcon>(
        context: context,
        sheetAnimationStyle: sheetMotion,
        showDragHandle: true,
        builder: (ctx) {
          final cs = Theme.of(ctx).colorScheme;
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                  child: Text('App icon',
                      style: Theme.of(ctx).textTheme.titleLarge),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    alignment: WrapAlignment.spaceEvenly,
                    runSpacing: 16,
                    children: [
                      for (final icon in AppIcon.values)
                        InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => Navigator.pop(ctx, icon),
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(5),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        width: 3,
                                        color: icon == current
                                            ? cs.primary
                                            : Colors.transparent),
                                  ),
                                  child: AppIconPreview(icon, size: 56),
                                ),
                                const SizedBox(height: 8),
                                Text(icon.label,
                                    style: Theme.of(ctx)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(
                                            color: icon == current
                                                ? cs.primary
                                                : cs.onSurface)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          );
        },
      );

  void _pickTheme(
      BuildContext context, SettingsController ctrl, ThemeMode current) {
    showModalBottomSheet(
      context: context,
      sheetAnimationStyle: sheetMotion,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: RadioGroup<ThemeMode>(
          groupValue: current,
          onChanged: (v) {
            if (v != null) ctrl.setThemeMode(v);
            Navigator.pop(ctx);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final m in ThemeMode.values)
                RadioListTile<ThemeMode>(
                  value: m,
                  title: Text(switch (m) {
                    ThemeMode.system => 'Follow system',
                    ThemeMode.light => 'Light',
                    ThemeMode.dark => 'Dark',
                  }),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _pickSort(
      BuildContext context, SettingsController ctrl, PostSort current) {
    showModalBottomSheet(
      context: context,
      sheetAnimationStyle: sheetMotion,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: RadioGroup<PostSort>(
          groupValue: current,
          onChanged: (v) {
            if (v != null) ctrl.setDefaultSort(v);
            Navigator.pop(ctx);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final sort in PostSort.values)
                RadioListTile<PostSort>(
                  value: sort,
                  title: Text(sort.label),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _pickCacheMinutes(
      BuildContext context, SettingsController ctrl, int current) {
    const options = [5, 10, 30, 60];
    showModalBottomSheet(
      context: context,
      sheetAnimationStyle: sheetMotion,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: RadioGroup<int>(
          groupValue: current,
          onChanged: (v) {
            if (v != null) ctrl.setSubsCacheMinutes(v);
            Navigator.pop(ctx);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final m in options)
                RadioListTile<int>(value: m, title: Text('$m minutes')),
            ],
          ),
        ),
      ),
    );
  }

  /// Blend's Reddit ↔ Ilay presets, each with what it does.
  void _pickBlend(
      BuildContext context, int current, void Function(int) onPick) {
    showModalBottomSheet(
      context: context,
      sheetAnimationStyle: sheetMotion,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: RadioGroup<int>(
          groupValue: current,
          onChanged: (v) {
            if (v != null) onPick(v);
            Navigator.pop(ctx);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < _blendPresets.length; i++)
                RadioListTile<int>(
                  value: i,
                  title: Text(_blendPresets[i].$1),
                  subtitle: Text(_blendPresets[i].$2),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _pickInt(BuildContext context, int current, List<int> options,
      String Function(int) label, void Function(int) onPick) {
    showModalBottomSheet(
      context: context,
      sheetAnimationStyle: sheetMotion,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: RadioGroup<int>(
          groupValue: current,
          onChanged: (v) {
            if (v != null) onPick(v);
            Navigator.pop(ctx);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final o in options)
                RadioListTile<int>(value: o, title: Text(label(o))),
            ],
          ),
        ),
      ),
    );
  }

  void _pickDimRead(
      BuildContext context, SettingsController ctrl, bool current) {
    showModalBottomSheet(
      context: context,
      sheetAnimationStyle: sheetMotion,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: RadioGroup<bool>(
          groupValue: current,
          onChanged: (v) {
            if (v != null) ctrl.setDimReadTextOnly(v);
            Navigator.pop(ctx);
          },
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<bool>(value: false, title: Text('Whole card')),
              RadioListTile<bool>(
                value: true,
                title: Text('Text only'),
                subtitle: Text('Images and videos stay bright'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _pickDisplay(
      BuildContext context, SettingsController ctrl, PostDisplay current) {
    showModalBottomSheet(
      context: context,
      sheetAnimationStyle: sheetMotion,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: RadioGroup<PostDisplay>(
          groupValue: current,
          onChanged: (v) {
            if (v != null) ctrl.setPostDisplay(v);
            Navigator.pop(ctx);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final d in PostDisplay.values)
                RadioListTile<PostDisplay>(
                  value: d,
                  secondary: Icon(d.icon),
                  title: Text(d.label),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _pickTopBar(
      BuildContext context, SettingsController ctrl, TopBarMode current) {
    showModalBottomSheet(
      context: context,
      sheetAnimationStyle: sheetMotion,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: RadioGroup<TopBarMode>(
          groupValue: current,
          onChanged: (v) {
            if (v != null) ctrl.setTopBarMode(v);
            Navigator.pop(ctx);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final m in TopBarMode.values)
                RadioListTile<TopBarMode>(
                  value: m,
                  title: Text(m.label),
                  subtitle: Text(m.description),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _pickNavStyle(
      BuildContext context, SettingsController ctrl, int current) {
    showModalBottomSheet(
      context: context,
      sheetAnimationStyle: sheetMotion,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: RadioGroup<int>(
          groupValue: current,
          onChanged: (v) {
            if (v != null) ctrl.setNavStyle(v);
            Navigator.pop(ctx);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < _navStyles.length; i++)
                RadioListTile<int>(
                  value: i,
                  title: Text(_navStyles[i].$1),
                  subtitle: Text(_navStyles[i].$2),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _pickCommentSort(
      BuildContext context, SettingsController ctrl, String current) {
    showModalBottomSheet(
      context: context,
      sheetAnimationStyle: sheetMotion,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in commentSorts)
              ListTile(
                title: Text(commentSortLabels[s] ?? s),
                trailing:
                    s == current ? const Icon(Icons.check_rounded) : null,
                onTap: () {
                  ctrl.setDefaultCommentSort(s);
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _editOpenAiKey(
      BuildContext context, WidgetRef ref, bool hasKey, bool custom) async {
    final ctrl = TextEditingController();
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(custom ? 'API key' : 'OpenAI API key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                  hintText: custom ? "Your provider's API key" : 'sk-…'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Stored securely on this device (never in backups). Summaries '
              'send the thread text to your AI endpoint.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          if (hasKey)
            TextButton(
                onPressed: () => Navigator.pop(ctx, 'remove'),
                child: const Text('Remove')),
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, 'save'),
              child: const Text('Save')),
        ],
      ),
    );
    if (action == null) return;
    final store = ref.read(secureStoreProvider);
    if (action == 'remove') {
      await store.saveOpenaiKey(null);
    } else if (ctrl.text.trim().isNotEmpty) {
      await store.saveOpenaiKey(ctrl.text.trim());
    }
    ref.invalidate(openAiKeyProvider);
  }

  Future<void> _pickAiModel(
      BuildContext context, SettingsController ctrl, String current) async {
    // The presets are OpenAI's; any other provider's model is typed in.
    const presets = ['gpt-6.1-sol', 'gpt-5.5', 'gpt-5.4-mini', 'gpt-5.4-nano'];
    final models = [...presets, if (!presets.contains(current)) current];
    final custom = await showModalBottomSheet<bool>(
      context: context,
      sheetAnimationStyle: sheetMotion,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final m in models)
              ListTile(
                title: Text(m),
                trailing:
                    m == current ? const Icon(Icons.check_rounded) : null,
                onTap: () {
                  ctrl.setAiModel(m);
                  Navigator.pop(ctx);
                },
              ),
            ListTile(
              title: const Text('Custom model…'),
              subtitle: const Text("Type your provider's model ID"),
              onTap: () => Navigator.pop(ctx, true),
            ),
          ],
        ),
      ),
    );
    if (custom != true || !context.mounted) return;
    final c = TextEditingController(text: current);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Model ID'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: c,
              autofocus: true,
              autocorrect: false,
              decoration: const InputDecoration(
                  hintText: 'e.g. llama-3.3-70b-versatile'),
            ),
            const SizedBox(height: 8),
            const Text('Exactly as your provider names it.',
                style: TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (ok == true && c.text.trim().isNotEmpty) ctrl.setAiModel(c.text.trim());
  }

  void _pickSummaryLanguage(
      BuildContext context, SettingsController ctrl, String current) {
    showModalBottomSheet(
      context: context,
      sheetAnimationStyle: sheetMotion,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (value, label) in _summaryLanguages)
                ListTile(
                  title: Text(label),
                  trailing: value == current
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onTap: () {
                    ctrl.setAiSummaryLanguage(value);
                    Navigator.pop(ctx);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _pickCollapseBelow(
      BuildContext context, SettingsController ctrl, int? current) {
    showModalBottomSheet(
      context: context,
      sheetAnimationStyle: sheetMotion,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final v in const <int?>[null, 1, 0, -5, -10])
              ListTile(
                title: Text(v == null ? 'Off' : 'Below $v points'),
                trailing:
                    v == current ? const Icon(Icons.check_rounded) : null,
                onTap: () {
                  ctrl.setCollapseBelowScore(v);
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _pickAiStyle(
      BuildContext context, SettingsController ctrl, int current) {
    showModalBottomSheet(
      context: context,
      sheetAnimationStyle: sheetMotion,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < SummaryStyle.values.length; i++)
              ListTile(
                title: Text(SummaryStyle.values[i].label),
                trailing:
                    i == current ? const Icon(Icons.check_rounded) : null,
                onTap: () {
                  ctrl.setAiSummaryStyle(i);
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _pickAiMaxChars(
      BuildContext context, SettingsController ctrl, int current) {
    const options = [50000, 100000, 200000, 400000];
    showModalBottomSheet(
      context: context,
      sheetAnimationStyle: sheetMotion,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final v in options)
              ListTile(
                title: Text('${(v / 1000).round()}k characters'),
                subtitle: Text('~${(v / 4000).round()}k tokens'),
                trailing:
                    v == current ? const Icon(Icons.check_rounded) : null,
                onTap: () {
                  ctrl.setAiMaxChars(v);
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _editAiBaseUrl(
      BuildContext context, SettingsController ctrl, String current) async {
    final c = TextEditingController(text: current);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('API base URL'),
        content: TextField(
          controller: c,
          autofocus: true,
          autocorrect: false,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
              hintText: 'https://api.groq.com/openai/v1',
              helperText: 'With or without /v1, as your provider shows it. '
                  'Then set the Model to one of theirs.',
              helperMaxLines: 3),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (ok == true && c.text.trim().isNotEmpty) {
      ctrl.setAiBaseUrl(c.text.trim());
    }
  }

  void _showLoginMethodInfo(BuildContext context, bool isWeb) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Login method'),
        content: Text(
          isWeb
              ? 'You\'re signed in with a website session (no API key).\n\n'
                  'This isn\'t Reddit\'s official API. It can stop working if '
                  'Reddit changes their site, and Reddit may consider it against '
                  'their usage policy and restrict or ban accounts that use it. '
                  'Use at your own risk.\n\n'
                  'To switch to the official API key method, log out and choose '
                  '"Connect Reddit account" on the login screen.'
              : 'You\'re signed in with Reddit\'s official API using your own '
                  'API key — the recommended, supported method.\n\n'
                  'If you can no longer create an API key, you can log out and '
                  'choose "Sign in via website" on the login screen, but that '
                  'unofficial method carries account risk.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  Future<void> _reenterCredentials(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Re-enter credentials?'),
        content: const Text(
            'You will be logged out and returned to the login screen. Your '
            'saved Client ID and Redirect URI will be pre-filled.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Continue')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(authControllerProvider.notifier).logout();
    }
  }

  Future<void> _clearAll(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all data?'),
        content: const Text(
            'This wipes your API credentials, tokens and session from this '
            'device. You will need to set everything up again.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Clear')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(secureStoreProvider).clearAll();
      await ref.read(redditClientProvider).clearCache();
      await ref.read(authControllerProvider.notifier).logout();
    }
  }
}

/// Reddit Home's amber: a caution, not an error.
Color _homeAmber(BuildContext context) =>
    Theme.of(context).colorScheme.surface.computeLuminance() > 0.5
        ? const Color(0xFF9A6700)
        : const Color(0xFFFFC94D);

/// What Reddit Home is (unofficial, can break) before turning it on. True to
/// turn it on.
Future<bool> _confirmRedditHome(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      const gap = SizedBox(height: 6);
      return AlertDialog(
        icon: Icon(Icons.warning_amber_rounded,
            size: 40, color: _homeAmber(ctx)),
        title: const Text('About Reddit Home', textAlign: TextAlign.center),
        content: SingleChildScrollView(
          child: DefaultTextStyle.merge(
            style: const TextStyle(height: 20 / 14),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Reddit Home shows your real reddit.com Home feed. Ilay '
                    'loads reddit.com in a hidden browser with your website '
                    'sign-in and reads which posts it shows.'),
                SizedBox(height: 10),
                Text("• Unofficial: Reddit's terms don't allow automated use "
                    'of its site, so use it at your own discretion.'),
                gap,
                Text('• It can stop working when Reddit changes its site. '
                    'Ilay then shows For You.'),
                gap,
                Text('• Website sign-in only; it talks only to reddit.com.'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Turn on')),
        ],
      );
    },
  );
  return ok ?? false;
}

/// For You's Familiar ↔ Discover mix, filled from the centre (Material 3
/// Expressive's centred track): 0 is Balanced, so the fill shows which way
/// and how far the mix leans.
class _ForYouMixSlider extends StatefulWidget {
  const _ForYouMixSlider({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  State<_ForYouMixSlider> createState() => _ForYouMixSliderState();
}

class _ForYouMixSliderState extends State<_ForYouMixSlider> {
  late double _v = widget.value.toDouble();

  @override
  void didUpdateWidget(_ForYouMixSlider old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _v = widget.value.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.fromLTRB(56, 8, 24, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('For You mix', style: Theme.of(context).textTheme.bodyLarge),
          Text(
            switch (_v.round()) {
              -2 => 'Almost only your communities',
              -1 => 'Mostly your communities',
              1 => "More from communities you don't follow",
              2 => 'Lots of new communities',
              _ => 'Balanced: adapts to what you open (next refresh)',
            },
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
          SliderTheme(
            // The stops sit on the fill or the track whichever side of the
            // handle they are, so one colour reads on both.
            data: SliderTheme.of(context).copyWith(
                trackShape: const _CentredTrackShape(),
                activeTickMarkColor: cs.onSecondaryContainer,
                inactiveTickMarkColor: cs.onSecondaryContainer),
            child: Slider(
              value: _v,
              min: -2,
              max: 2,
              divisions: 4,
              onChanged: (v) => setState(() => _v = v),
              onChangeEnd: (v) => widget.onChanged(v.round()),
            ),
          ),
          Row(
            children: [
              Expanded(child: Text('Familiar', style: muted)),
              Text('Discover', style: muted),
            ],
          ),
        ],
      ),
    );
  }
}

/// A slider track filled from its middle to the thumb, either way
/// (Material 3 Expressive's CenteredTrack): the track parts keep their gap
/// around the bar handle, with tight (2) corners beside it.
class _CentredTrackShape extends SliderTrackShape with BaseSliderTrackShape {
  const _CentredTrackShape();

  @override
  void paint(PaintingContext context, Offset offset,
      {required RenderBox parentBox,
      required SliderThemeData sliderTheme,
      required Animation<double> enableAnimation,
      required Offset thumbCenter,
      Offset? secondaryOffset,
      bool isEnabled = false,
      bool isDiscrete = false,
      required TextDirection textDirection}) {
    final rect = getPreferredRect(
        parentBox: parentBox,
        offset: offset,
        sliderTheme: sliderTheme,
        isEnabled: isEnabled,
        isDiscrete: isDiscrete);
    final round = Radius.circular(rect.height / 2);
    const tight = Radius.circular(2);
    final gap = sliderTheme.trackGap ?? 6;
    final x = thumbCenter.dx;
    final mid = rect.center.dx;
    final canvas = context.canvas;
    final track = Paint()..color = sliderTheme.inactiveTrackColor!;
    final fill = Paint()..color = sliderTheme.activeTrackColor!;
    if (x - gap > rect.left) {
      canvas.drawRRect(
          RRect.fromLTRBAndCorners(rect.left, rect.top, x - gap, rect.bottom,
              topLeft: round,
              bottomLeft: round,
              topRight: tight,
              bottomRight: tight),
          track);
    }
    if (x + gap < rect.right) {
      canvas.drawRRect(
          RRect.fromLTRBAndCorners(x + gap, rect.top, rect.right, rect.bottom,
              topLeft: tight,
              bottomLeft: tight,
              topRight: round,
              bottomRight: round),
          track);
    }
    // The fill runs from the middle up to the handle's gap.
    final from = x > mid ? mid : x + gap;
    final to = x > mid ? x - gap : mid;
    if (to > from) {
      canvas.drawRRect(
          RRect.fromLTRBAndCorners(from, rect.top, to, rect.bottom,
              topLeft: tight,
              bottomLeft: tight,
              topRight: tight,
              bottomRight: tight),
          fill);
    }
  }
}

/// Picks what each swipe direction does, for posts and for comments.
class _SwipeSettingsSheet extends ConsumerWidget {
  const _SwipeSettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsControllerProvider);
    final ctrl = ref.read(settingsControllerProvider.notifier);
    // "Right"/"left" as the user sees them; mirrored in RTL languages.
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final startLabel = rtl ? 'Swipe left' : 'Swipe right';
    final endLabel = rtl ? 'Swipe right' : 'Swipe left';
    Widget row(String label, String key, SwipeAction value, bool forPosts) {
      final options = SwipeAction.values.where((a) => forPosts
          ? a != SwipeAction.collapse
          : a != SwipeAction.hide &&
              a != SwipeAction.dismiss &&
              a != SwipeAction.hideSub);
      final cs = Theme.of(context).colorScheme;
      return ListTile(
        title: Text(label),
        // A text button opening Kotlin's PickOneMenu.
        trailing: PopupMenuButton<SwipeAction>(
          tooltip: label,
          onSelected: (a) => ctrl.setSwipeAction(key, a),
          itemBuilder: (_) => pickOneMenu(
              [for (final a in options) (a, a.label)], value,
              icon: (a) => a.icon),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(value.icon, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Text(value.label,
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(color: cs.primary)),
              Icon(Icons.expand_more_rounded, color: cs.primary),
            ]),
          ),
        ),
      );
    }

    Widget header(String title) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  )),
        );

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header('Posts'),
          row(startLabel, 'swipePostStart', s.swipePostStart, true),
          row(endLabel, 'swipePostEnd', s.swipePostEnd, true),
          header('Comments'),
          row(startLabel, 'swipeCommentStart', s.swipeCommentStart, false),
          row(endLabel, 'swipeCommentEnd', s.swipeCommentEnd, false),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

/// "Save media to": the gallery's Ilay album, or a folder the user picks.
class _MediaFolderTile extends ConsumerWidget {
  const _MediaFolderTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folder = ref.watch(mediaFolderProvider);
    final ctrl = ref.read(mediaFolderProvider.notifier);
    return ListTile(
      leading: const Icon(Icons.folder_rounded),
      title: const Text('Save media to'),
      subtitle: Text(folder?.name ?? 'Gallery (Ilay album)'),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        sheetAnimationStyle: sheetMotion,
        showDragHandle: true,
        builder: (sheet) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_rounded),
                title: const Text('Gallery (Ilay album)'),
                trailing: folder == null ? const Icon(Icons.check) : null,
                onTap: () {
                  Navigator.pop(sheet);
                  ctrl.useGallery();
                },
              ),
              ListTile(
                leading: const Icon(Icons.create_new_folder_rounded),
                title: Text(folder == null ? 'Choose a folder…' : folder.name),
                subtitle: folder == null ? null : const Text('Tap to change'),
                trailing: folder != null ? const Icon(Icons.check) : null,
                onTap: () {
                  Navigator.pop(sheet);
                  ctrl.pick();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RateLimitTile extends ConsumerWidget {
  const _RateLimitTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rl = ref.watch(rateLimitProvider);
    return ListTile(
      leading: const Icon(Icons.speed_rounded),
      title: const Text('API usage'),
      subtitle: Text(rl == null
          ? 'Reddit allows roughly 100 requests/minute. No data yet.'
          : '${rl.used}/${rl.total} used this window · resets in ${rl.resetSeconds}s'),
    );
  }
}

String _keepLabel(int minutes) => minutes < 60
    ? '$minutes minutes'
    : minutes == 60
        ? '1 hour'
        : '${minutes ~/ 60} hours';

String _dayLabel(int days) => days == 1 ? '1 day' : '$days days';

/// The subreddits hidden from the front page ("Hide r/… for 7 days"), each
/// with Unhide.
class _HiddenSubsDialog extends ConsumerWidget {
  const _HiddenSubsDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subs = ref.watch(hiddenHomeSubsProvider).toList()..sort();
    return AlertDialog(
      title: const Text('Hidden subreddits'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (subs.isEmpty)
              const Text("None. Hide one from a post's ⋮ menu or a swipe; it "
                  'comes back after 7 days.'),
            for (final sub in subs)
              Row(
                children: [
                  Expanded(child: Text('r/$sub')),
                  TextButton(
                    onPressed: () =>
                        ref.read(hiddenHomeSubsProvider.notifier).remove(sub),
                    child: const Text('Unhide'),
                  ),
                ],
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done')),
      ],
    );
  }
}

/// The size of Ilay's cache folder (saved pages, images), in bytes.
Future<int> cacheBytes() async {
  final dir = await getTemporaryDirectory();
  var total = 0;
  await for (final f in Directory(dir.path).list(recursive: true)) {
    if (f is File) total += await f.length();
  }
  return total;
}
