import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/rate_limit.dart';
import '../../core/providers.dart';
import '../../core/reddit_constants.dart';
import '../../data/reddit_repository.dart';
import '../auth/auth_controller.dart';
import '../updates/update_checker.dart';
import 'settings_controller.dart';

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

/// The settings list — reusable both as the full Settings screen and embedded
/// (e.g. inside the Account tab). Pass [embedded] when nesting in a scroll view.
class SettingsList extends ConsumerWidget {
  const SettingsList({super.key, this.embedded = false});
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsControllerProvider);
    final ctrl = ref.read(settingsControllerProvider.notifier);

    return ListView(
      shrinkWrap: embedded,
      physics: embedded ? const NeverScrollableScrollPhysics() : null,
      children: [
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
          const Divider(),
          _section(context, 'Feed'),
          ListTile(
            leading: const Icon(Icons.sort_rounded),
            title: const Text('Default sort'),
            subtitle: Text(s.defaultSort.label),
            onTap: () => _pickSort(context, ctrl, s.defaultSort),
          ),
          ListTile(
            leading: Icon(s.postDisplay.icon),
            title: const Text('Post display'),
            subtitle: Text(s.postDisplay.label),
            onTap: () => _pickDisplay(context, ctrl, s.postDisplay),
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
          SwitchListTile(
            secondary: const Icon(Icons.auto_awesome_rounded),
            title: const Text('"For You" feed (Beta)'),
            subtitle: const Text(
                'Personalized frontpage built on-device. Reddit\'s own '
                'recommendations aren\'t available to third-party apps.'),
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
          SwitchListTile(
            secondary: const Icon(Icons.swipe_rounded),
            title: const Text('Swipe to vote'),
            subtitle: const Text('Swipe posts/comments right=up, left=down'),
            value: s.swipeActions,
            onChanged: ctrl.setSwipeActions,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.play_circle_outline_rounded),
            title: const Text('Autoplay videos'),
            subtitle: const Text('Play videos muted as you scroll the feed'),
            value: s.autoplayMedia,
            onChanged: ctrl.setAutoplayMedia,
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
          const Divider(),
          _section(context, 'History & data'),
          ListTile(
            leading: const Icon(Icons.history_rounded),
            title: const Text('History'),
            subtitle: const Text('Recently viewed (stored on this device)'),
            onTap: () => context.push('/history'),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.visibility_outlined),
            title: const Text('Track history'),
            subtitle: const Text('Remember and dim viewed posts (local only)'),
            value: s.trackHistory,
            onChanged: ctrl.setTrackHistory,
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
          ListTile(
            leading: const Icon(Icons.cached_rounded),
            title: const Text('Clear cache'),
            onTap: () async {
              await ref.read(redditClientProvider).clearCache();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Cache cleared')));
              }
            },
          ),
          const Divider(),
          _section(context, 'Updates & links'),
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
            title: Text('Open reddit links in Luli'),
            subtitle: Text(
                'Already supported via the Android "open with" chooser. To make '
                'Luli the verified default, enable it under system app settings '
                '› Open by default.'),
          ),
          _RateLimitTile(),
          ListTile(
            leading: const Icon(Icons.gavel_rounded),
            title: const Text('Content & conduct policy'),
            onTap: () => context.push('/policy'),
          ),
          const Divider(),
          _section(context, 'Account'),
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
          const SizedBox(height: 24),
        ],
    );
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

  Widget _section(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w700,
                )),
      );

  void _pickTheme(
      BuildContext context, SettingsController ctrl, ThemeMode current) {
    showModalBottomSheet(
      context: context,
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

  void _pickDisplay(
      BuildContext context, SettingsController ctrl, PostDisplay current) {
    showModalBottomSheet(
      context: context,
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
      await ref.read(authControllerProvider.notifier).logout();
    }
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
