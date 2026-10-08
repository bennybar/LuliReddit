import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_theme.dart';
import '../../data/reddit_repository.dart';
import '../feed/swipe_actions.dart';

/// Provided via override in main() after SharedPreferences is loaded.
final sharedPrefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPrefsProvider not initialized'),
);

/// Where the Posts-screen actions (search, new post, profile) live.
enum TopBarMode { full, expandable }

extension TopBarModeLabel on TopBarMode {
  String get label => switch (this) {
        TopBarMode.full => 'Full top bar',
        TopBarMode.expandable => 'Expandable',
      };
  String get description => switch (this) {
        TopBarMode.full =>
          'Search, new post and profile across the top (current)',
        TopBarMode.expandable =>
          'Just a title with one button that floats the full top bar in on demand',
      };
}

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
    required this.jakartaFont,
    required this.inAppBrowser,
    required this.tapToCollapse,
    required this.hideReadPosts,
    required this.markReadOnScroll,
    required this.swipePostStart,
    required this.swipePostEnd,
    required this.swipeCommentStart,
    required this.swipeCommentEnd,
    required this.seedColor,
    required this.blurNsfw,
    required this.defaultSort,
    required this.defaultCommentSort,
    required this.postDisplay,
    required this.swipeActions,
    required this.trackHistory,
    required this.offlineCache,
    required this.checkUpdates,
    required this.forYouFeed,
    required this.redditHomeAllowed,
    required this.redditHomeFeed,
    required this.autoHideReadForYou,
    required this.midResThumbnails,
    required this.subsCacheEnabled,
    required this.subsCacheMinutes,
    required this.textScale,
    required this.autoplayMedia,
    required this.showApiUsage,
    required this.notifyInbox,
    required this.topBarMode,
    required this.navLabels,
    required this.aiModel,
    required this.aiSummaryStyle,
    required this.aiMaxChars,
    required this.aiUseCustomUrl,
    required this.aiBaseUrl,
  });

  final ThemeMode themeMode;
  final bool amoled;
  final bool useDynamicColor;
  final bool jakartaFont; // Plus Jakarta Sans + Unbounded instead of Roboto
  final bool inAppBrowser; // open web links in a Custom Tab, not the browser app
  final bool tapToCollapse; // tap a comment to collapse it (else long-press)
  final bool hideReadPosts; // skip already-read posts when feeds load
  final bool markReadOnScroll; // a post scrolled past counts as read
  // What swiping does: "start" = from the start edge (rightward in LTR).
  final SwipeAction swipePostStart, swipePostEnd;
  final SwipeAction swipeCommentStart, swipeCommentEnd;
  final int seedColor; // ARGB int
  final bool blurNsfw;
  final PostSort defaultSort;
  final String defaultCommentSort; // reddit comment sort id (confidence, top, …)
  final PostDisplay postDisplay;
  final bool swipeActions;
  final bool trackHistory;
  final bool offlineCache;
  final bool checkUpdates;
  final bool forYouFeed; // frontpage uses the "For You (Beta)" feed
  // Experimental Reddit Home: the user accepted its risk warning in Settings
  // (allowed), and the frontpage currently shows it (feed).
  final bool redditHomeAllowed;
  final bool redditHomeFeed;
  final bool autoHideReadForYou; // hide already-read items in For You
  final bool midResThumbnails; // load smaller preview images in feeds
  final bool subsCacheEnabled; // cache subscription list in memory
  final int subsCacheMinutes; // how long to keep the subs cache
  final double textScale; // global text size multiplier (0.8–1.4)
  final bool autoplayMedia; // autoplay videos/GIFs in feeds
  final bool showApiUsage; // show API usage instead of search on Posts screen
  final bool notifyInbox; // background-poll the inbox + local notifications
  final TopBarMode topBarMode; // Posts-screen action layout
  final bool navLabels; // show text labels on the bottom nav bar
  final String aiModel; // OpenAI(-compatible) model id for summaries
  final int aiSummaryStyle; // index into SummaryStyle
  final int aiMaxChars; // max thread text sent to the model
  final bool aiUseCustomUrl; // use a custom API base URL
  final String aiBaseUrl; // custom base URL (when enabled)

  Settings copyWith({
    ThemeMode? themeMode,
    bool? amoled,
    bool? useDynamicColor,
    bool? jakartaFont,
    bool? inAppBrowser,
    bool? tapToCollapse,
    bool? hideReadPosts,
    bool? markReadOnScroll,
    SwipeAction? swipePostStart,
    SwipeAction? swipePostEnd,
    SwipeAction? swipeCommentStart,
    SwipeAction? swipeCommentEnd,
    int? seedColor,
    bool? blurNsfw,
    PostSort? defaultSort,
    String? defaultCommentSort,
    PostDisplay? postDisplay,
    bool? swipeActions,
    bool? trackHistory,
    bool? offlineCache,
    bool? checkUpdates,
    bool? forYouFeed,
    bool? redditHomeAllowed,
    bool? redditHomeFeed,
    bool? autoHideReadForYou,
    bool? midResThumbnails,
    bool? subsCacheEnabled,
    int? subsCacheMinutes,
    double? textScale,
    bool? autoplayMedia,
    bool? showApiUsage,
    bool? notifyInbox,
    TopBarMode? topBarMode,
    bool? navLabels,
    String? aiModel,
    int? aiSummaryStyle,
    int? aiMaxChars,
    bool? aiUseCustomUrl,
    String? aiBaseUrl,
  }) =>
      Settings(
        themeMode: themeMode ?? this.themeMode,
        amoled: amoled ?? this.amoled,
        useDynamicColor: useDynamicColor ?? this.useDynamicColor,
        jakartaFont: jakartaFont ?? this.jakartaFont,
        inAppBrowser: inAppBrowser ?? this.inAppBrowser,
        tapToCollapse: tapToCollapse ?? this.tapToCollapse,
        hideReadPosts: hideReadPosts ?? this.hideReadPosts,
        markReadOnScroll: markReadOnScroll ?? this.markReadOnScroll,
        swipePostStart: swipePostStart ?? this.swipePostStart,
        swipePostEnd: swipePostEnd ?? this.swipePostEnd,
        swipeCommentStart: swipeCommentStart ?? this.swipeCommentStart,
        swipeCommentEnd: swipeCommentEnd ?? this.swipeCommentEnd,
        seedColor: seedColor ?? this.seedColor,
        blurNsfw: blurNsfw ?? this.blurNsfw,
        defaultSort: defaultSort ?? this.defaultSort,
        defaultCommentSort: defaultCommentSort ?? this.defaultCommentSort,
        postDisplay: postDisplay ?? this.postDisplay,
        swipeActions: swipeActions ?? this.swipeActions,
        trackHistory: trackHistory ?? this.trackHistory,
        offlineCache: offlineCache ?? this.offlineCache,
        checkUpdates: checkUpdates ?? this.checkUpdates,
        forYouFeed: forYouFeed ?? this.forYouFeed,
        redditHomeAllowed: redditHomeAllowed ?? this.redditHomeAllowed,
        redditHomeFeed: redditHomeFeed ?? this.redditHomeFeed,
        autoHideReadForYou: autoHideReadForYou ?? this.autoHideReadForYou,
        midResThumbnails: midResThumbnails ?? this.midResThumbnails,
        subsCacheEnabled: subsCacheEnabled ?? this.subsCacheEnabled,
        subsCacheMinutes: subsCacheMinutes ?? this.subsCacheMinutes,
        textScale: textScale ?? this.textScale,
        autoplayMedia: autoplayMedia ?? this.autoplayMedia,
        showApiUsage: showApiUsage ?? this.showApiUsage,
        notifyInbox: notifyInbox ?? this.notifyInbox,
        topBarMode: topBarMode ?? this.topBarMode,
        navLabels: navLabels ?? this.navLabels,
        aiModel: aiModel ?? this.aiModel,
        aiSummaryStyle: aiSummaryStyle ?? this.aiSummaryStyle,
        aiMaxChars: aiMaxChars ?? this.aiMaxChars,
        aiUseCustomUrl: aiUseCustomUrl ?? this.aiUseCustomUrl,
        aiBaseUrl: aiBaseUrl ?? this.aiBaseUrl,
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
      jakartaFont: p.getBool('jakartaFont') ?? false,
      inAppBrowser: p.getBool('inAppBrowser') ?? false,
      tapToCollapse: p.getBool('tapToCollapse') ?? false,
      hideReadPosts: p.getBool('hideReadPosts') ?? false,
      markReadOnScroll: p.getBool('markReadOnScroll') ?? false,
      swipePostStart:
          SwipeAction.parse(p.getString('swipePostStart'), SwipeAction.upvote),
      swipePostEnd:
          SwipeAction.parse(p.getString('swipePostEnd'), SwipeAction.downvote),
      swipeCommentStart: SwipeAction.parse(
          p.getString('swipeCommentStart'), SwipeAction.upvote),
      swipeCommentEnd: SwipeAction.parse(
          p.getString('swipeCommentEnd'), SwipeAction.downvote),
      seedColor: p.getInt('seedColor') ?? AppTheme.seed.toARGB32(),
      blurNsfw: p.getBool('blurNsfw') ?? true,
      defaultSort: PostSort.values[p.getInt('defaultSort') ?? PostSort.best.index],
      defaultCommentSort: p.getString('defaultCommentSort') ?? 'confidence',
      postDisplay:
          PostDisplay.values[p.getInt('postDisplay') ?? PostDisplay.large.index],
      swipeActions: p.getBool('swipeActions') ?? true,
      trackHistory: p.getBool('trackHistory') ?? true,
      offlineCache: p.getBool('offlineCache') ?? true,
      checkUpdates: p.getBool('checkUpdates') ?? true,
      forYouFeed: p.getBool('forYouFeed') ?? false,
      redditHomeAllowed: p.getBool('redditHomeAllowed') ?? false,
      redditHomeFeed: p.getBool('redditHomeFeed') ?? false,
      autoHideReadForYou: p.getBool('autoHideReadForYou') ?? false,
      midResThumbnails: p.getBool('midResThumbnails') ?? true,
      subsCacheEnabled: p.getBool('subsCacheEnabled') ?? true,
      subsCacheMinutes: p.getInt('subsCacheMinutes') ?? 10,
      textScale: p.getDouble('textScale') ?? 1.0,
      autoplayMedia: p.getBool('autoplayMedia') ?? true,
      showApiUsage: p.getBool('showApiUsage') ?? false,
      notifyInbox: p.getBool('notifyInbox') ?? false,
      // Default to Expandable. Old installs may have stored the removed
      // "compact" (1) or the old expandable index (2); clamp maps both safely.
      topBarMode: p.getInt('topBarMode') == null
          ? TopBarMode.expandable
          : TopBarMode.values[
              p.getInt('topBarMode')!.clamp(0, TopBarMode.values.length - 1)],
      navLabels: p.getBool('navLabels') ?? true,
      aiModel: p.getString('aiModel') ?? 'gpt-5.4-mini',
      aiSummaryStyle: p.getInt('aiSummaryStyle') ?? 1, // Key points
      aiMaxChars: p.getInt('aiMaxChars') ?? 100000,
      aiUseCustomUrl: p.getBool('aiUseCustomUrl') ?? false,
      aiBaseUrl: p.getString('aiBaseUrl') ?? 'https://api.openai.com',
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

  void setDefaultCommentSort(String sort) {
    _prefs.setString('defaultCommentSort', sort);
    state = state.copyWith(defaultCommentSort: sort);
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

  /// Turning Reddit Home off in Settings also takes the frontpage off it.
  void setRedditHomeAllowed(bool v) {
    _prefs.setBool('redditHomeAllowed', v);
    state = state.copyWith(redditHomeAllowed: v);
    if (!v) setRedditHomeFeed(false);
  }

  void setRedditHomeFeed(bool v) {
    _prefs.setBool('redditHomeFeed', v);
    state = state.copyWith(redditHomeFeed: v);
    if (v && state.forYouFeed) {
      _prefs.setBool('forYouFeed', false);
      state = state.copyWith(forYouFeed: false);
    }
  }

  void setForYouFeed(bool v) {
    _prefs.setBool('forYouFeed', v);
    state = state.copyWith(forYouFeed: v);
    if (v) setRedditHomeFeed(false); // one frontpage mode at a time
  }

  void setAutoHideReadForYou(bool v) {
    _prefs.setBool('autoHideReadForYou', v);
    state = state.copyWith(autoHideReadForYou: v);
  }

  void setJakartaFont(bool v) {
    _prefs.setBool('jakartaFont', v);
    state = state.copyWith(jakartaFont: v);
  }

  void setHideReadPosts(bool v) {
    _prefs.setBool('hideReadPosts', v);
    state = state.copyWith(hideReadPosts: v);
  }

  void setMarkReadOnScroll(bool v) {
    _prefs.setBool('markReadOnScroll', v);
    state = state.copyWith(markReadOnScroll: v);
  }

  /// [key] is one of swipePostStart / swipePostEnd / swipeCommentStart /
  /// swipeCommentEnd.
  void setSwipeAction(String key, SwipeAction a) {
    _prefs.setString(key, a.name);
    state = switch (key) {
      'swipePostStart' => state.copyWith(swipePostStart: a),
      'swipePostEnd' => state.copyWith(swipePostEnd: a),
      'swipeCommentStart' => state.copyWith(swipeCommentStart: a),
      _ => state.copyWith(swipeCommentEnd: a),
    };
  }

  void setTapToCollapse(bool v) {
    _prefs.setBool('tapToCollapse', v);
    state = state.copyWith(tapToCollapse: v);
  }

  void setInAppBrowser(bool v) {
    _prefs.setBool('inAppBrowser', v);
    state = state.copyWith(inAppBrowser: v);
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

  void setTopBarMode(TopBarMode v) {
    _prefs.setInt('topBarMode', v.index);
    state = state.copyWith(topBarMode: v);
  }

  void setNavLabels(bool v) {
    _prefs.setBool('navLabels', v);
    state = state.copyWith(navLabels: v);
  }

  void setAiModel(String v) {
    _prefs.setString('aiModel', v);
    state = state.copyWith(aiModel: v);
  }

  void setAiSummaryStyle(int v) {
    _prefs.setInt('aiSummaryStyle', v);
    state = state.copyWith(aiSummaryStyle: v);
  }

  void setAiMaxChars(int v) {
    _prefs.setInt('aiMaxChars', v);
    state = state.copyWith(aiMaxChars: v);
  }

  void setAiUseCustomUrl(bool v) {
    _prefs.setBool('aiUseCustomUrl', v);
    state = state.copyWith(aiUseCustomUrl: v);
  }

  void setAiBaseUrl(String v) {
    _prefs.setString('aiBaseUrl', v);
    state = state.copyWith(aiBaseUrl: v);
  }
}

final settingsControllerProvider =
    NotifierProvider<SettingsController, Settings>(SettingsController.new);
