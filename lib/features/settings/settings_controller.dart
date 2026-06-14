import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_theme.dart';
import '../../data/reddit_repository.dart';

/// Provided via override in main() after SharedPreferences is loaded.
final sharedPrefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPrefsProvider not initialized'),
);

/// How posts are laid out in feeds.
enum PostDisplay { large, card, mini }

extension PostDisplayLabel on PostDisplay {
  String get label => switch (this) {
        PostDisplay.large => 'Default',
        PostDisplay.card => 'Cards',
        PostDisplay.mini => 'Mini cards',
      };
  IconData get icon => switch (this) {
        PostDisplay.large => Icons.view_agenda_outlined,
        PostDisplay.card => Icons.calendar_view_day_rounded,
        PostDisplay.mini => Icons.view_list_rounded,
      };
}

class Settings {
  const Settings({
    required this.themeMode,
    required this.amoled,
    required this.useDynamicColor,
    required this.seedColor,
    required this.blurNsfw,
    required this.defaultSort,
    required this.postDisplay,
    required this.swipeActions,
    required this.trackHistory,
    required this.offlineCache,
    required this.checkUpdates,
    required this.forYouFeed,
    required this.autoHideReadForYou,
    required this.midResThumbnails,
    required this.subsCacheEnabled,
    required this.subsCacheMinutes,
    required this.textScale,
    required this.autoplayMedia,
    required this.showApiUsage,
    required this.notifyInbox,
  });

  final ThemeMode themeMode;
  final bool amoled;
  final bool useDynamicColor;
  final int seedColor; // ARGB int
  final bool blurNsfw;
  final PostSort defaultSort;
  final PostDisplay postDisplay;
  final bool swipeActions;
  final bool trackHistory;
  final bool offlineCache;
  final bool checkUpdates;
  final bool forYouFeed; // frontpage uses the "For You (Beta)" feed
  final bool autoHideReadForYou; // hide already-read items in For You
  final bool midResThumbnails; // load smaller preview images in feeds
  final bool subsCacheEnabled; // cache subscription list in memory
  final int subsCacheMinutes; // how long to keep the subs cache
  final double textScale; // global text size multiplier (0.8–1.4)
  final bool autoplayMedia; // autoplay videos/GIFs in feeds
  final bool showApiUsage; // show API usage instead of search on Posts screen
  final bool notifyInbox; // background-poll the inbox + local notifications

  Settings copyWith({
    ThemeMode? themeMode,
    bool? amoled,
    bool? useDynamicColor,
    int? seedColor,
    bool? blurNsfw,
    PostSort? defaultSort,
    PostDisplay? postDisplay,
    bool? swipeActions,
    bool? trackHistory,
    bool? offlineCache,
    bool? checkUpdates,
    bool? forYouFeed,
    bool? autoHideReadForYou,
    bool? midResThumbnails,
    bool? subsCacheEnabled,
    int? subsCacheMinutes,
    double? textScale,
    bool? autoplayMedia,
    bool? showApiUsage,
    bool? notifyInbox,
  }) =>
      Settings(
        themeMode: themeMode ?? this.themeMode,
        amoled: amoled ?? this.amoled,
        useDynamicColor: useDynamicColor ?? this.useDynamicColor,
        seedColor: seedColor ?? this.seedColor,
        blurNsfw: blurNsfw ?? this.blurNsfw,
        defaultSort: defaultSort ?? this.defaultSort,
        postDisplay: postDisplay ?? this.postDisplay,
        swipeActions: swipeActions ?? this.swipeActions,
        trackHistory: trackHistory ?? this.trackHistory,
        offlineCache: offlineCache ?? this.offlineCache,
        checkUpdates: checkUpdates ?? this.checkUpdates,
        forYouFeed: forYouFeed ?? this.forYouFeed,
        autoHideReadForYou: autoHideReadForYou ?? this.autoHideReadForYou,
        midResThumbnails: midResThumbnails ?? this.midResThumbnails,
        subsCacheEnabled: subsCacheEnabled ?? this.subsCacheEnabled,
        subsCacheMinutes: subsCacheMinutes ?? this.subsCacheMinutes,
        textScale: textScale ?? this.textScale,
        autoplayMedia: autoplayMedia ?? this.autoplayMedia,
        showApiUsage: showApiUsage ?? this.showApiUsage,
        notifyInbox: notifyInbox ?? this.notifyInbox,
      );
}

class SettingsController extends Notifier<Settings> {
  SharedPreferences get _prefs => ref.read(sharedPrefsProvider);

  @override
  Settings build() {
    final p = _prefs;
    return Settings(
      themeMode: ThemeMode.values[p.getInt('themeMode') ?? 0],
      amoled: p.getBool('amoled') ?? false,
      // Default off so the Bloom palette shows out of the box; users can opt
      // into wallpaper-based dynamic color.
      useDynamicColor: p.getBool('useDynamicColor') ?? false,
      seedColor: p.getInt('seedColor') ?? AppTheme.seed.toARGB32(),
      blurNsfw: p.getBool('blurNsfw') ?? true,
      defaultSort: PostSort.values[p.getInt('defaultSort') ?? PostSort.best.index],
      postDisplay:
          PostDisplay.values[p.getInt('postDisplay') ?? PostDisplay.large.index],
      swipeActions: p.getBool('swipeActions') ?? true,
      trackHistory: p.getBool('trackHistory') ?? true,
      offlineCache: p.getBool('offlineCache') ?? true,
      checkUpdates: p.getBool('checkUpdates') ?? true,
      forYouFeed: p.getBool('forYouFeed') ?? false,
      autoHideReadForYou: p.getBool('autoHideReadForYou') ?? false,
      midResThumbnails: p.getBool('midResThumbnails') ?? true,
      subsCacheEnabled: p.getBool('subsCacheEnabled') ?? true,
      subsCacheMinutes: p.getInt('subsCacheMinutes') ?? 10,
      textScale: p.getDouble('textScale') ?? 1.0,
      autoplayMedia: p.getBool('autoplayMedia') ?? true,
      showApiUsage: p.getBool('showApiUsage') ?? false,
      notifyInbox: p.getBool('notifyInbox') ?? false,
    );
  }

  void setThemeMode(ThemeMode mode) {
    _prefs.setInt('themeMode', mode.index);
    state = state.copyWith(themeMode: mode);
  }

  void setAmoled(bool v) {
    _prefs.setBool('amoled', v);
    state = state.copyWith(amoled: v);
  }

  void setUseDynamicColor(bool v) {
    _prefs.setBool('useDynamicColor', v);
    state = state.copyWith(useDynamicColor: v);
  }

  void setSeedColor(int argb) {
    _prefs.setInt('seedColor', argb);
    state = state.copyWith(seedColor: argb);
  }

  void setBlurNsfw(bool v) {
    _prefs.setBool('blurNsfw', v);
    state = state.copyWith(blurNsfw: v);
  }

  void setDefaultSort(PostSort sort) {
    _prefs.setInt('defaultSort', sort.index);
    state = state.copyWith(defaultSort: sort);
  }

  void setPostDisplay(PostDisplay display) {
    _prefs.setInt('postDisplay', display.index);
    state = state.copyWith(postDisplay: display);
  }

  void setSwipeActions(bool v) {
    _prefs.setBool('swipeActions', v);
    state = state.copyWith(swipeActions: v);
  }

  void setTrackHistory(bool v) {
    _prefs.setBool('trackHistory', v);
    state = state.copyWith(trackHistory: v);
  }

  void setOfflineCache(bool v) {
    _prefs.setBool('offlineCache', v);
    state = state.copyWith(offlineCache: v);
  }

  void setCheckUpdates(bool v) {
    _prefs.setBool('checkUpdates', v);
    state = state.copyWith(checkUpdates: v);
  }

  void setForYouFeed(bool v) {
    _prefs.setBool('forYouFeed', v);
    state = state.copyWith(forYouFeed: v);
  }

  void setAutoHideReadForYou(bool v) {
    _prefs.setBool('autoHideReadForYou', v);
    state = state.copyWith(autoHideReadForYou: v);
  }

  void setMidResThumbnails(bool v) {
    _prefs.setBool('midResThumbnails', v);
    state = state.copyWith(midResThumbnails: v);
  }

  void setSubsCacheEnabled(bool v) {
    _prefs.setBool('subsCacheEnabled', v);
    state = state.copyWith(subsCacheEnabled: v);
  }

  void setSubsCacheMinutes(int v) {
    _prefs.setInt('subsCacheMinutes', v);
    state = state.copyWith(subsCacheMinutes: v);
  }

  void setTextScale(double v) {
    _prefs.setDouble('textScale', v);
    state = state.copyWith(textScale: v);
  }

  void setAutoplayMedia(bool v) {
    _prefs.setBool('autoplayMedia', v);
    state = state.copyWith(autoplayMedia: v);
  }

  void setShowApiUsage(bool v) {
    _prefs.setBool('showApiUsage', v);
    state = state.copyWith(showApiUsage: v);
  }

  void setNotifyInbox(bool v) {
    _prefs.setBool('notifyInbox', v);
    state = state.copyWith(notifyInbox: v);
  }
}

final settingsControllerProvider =
    NotifierProvider<SettingsController, Settings>(SettingsController.new);
