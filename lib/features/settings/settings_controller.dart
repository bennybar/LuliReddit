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
}

final settingsControllerProvider =
    NotifierProvider<SettingsController, Settings>(SettingsController.new);
