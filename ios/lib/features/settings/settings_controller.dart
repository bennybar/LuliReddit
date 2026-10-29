import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/analytics.dart';
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

/// The app's typeface (Settings → App font), persisted by name (`appFont`).
enum AppFont {
  system('San Francisco', "The system's default"),
  googleSans('Google Sans', "The typeface of Google's own apps"),
  jakarta('Plus Jakarta Sans', 'Rounder, with Unbounded for headlines');

  const AppFont(this.label, this.description);
  final String label;
  final String description;

  /// Before the picker there was only the Jakarta switch; without either,
  /// Google Sans.
  static AppFont parse(String? name, bool jakartaSwitch) =>
      values.where((f) => f.name == name).firstOrNull ??
      (jakartaSwitch ? jakarta : googleSans);
}

/// How posts are laid out in feeds. Persisted by index (`postDisplay`).
enum PostDisplay { large, card, mini, calm, calmCards }

extension PostDisplayLabel on PostDisplay {
  String get label => switch (this) {
        PostDisplay.large => 'Default',
        PostDisplay.card => 'Cards',
        PostDisplay.mini => 'Mini cards',
        PostDisplay.calm => 'Calm',
        PostDisplay.calmCards => 'Calm cards',
      };
  IconData get icon => switch (this) {
        PostDisplay.large => Icons.view_agenda_outlined,
        PostDisplay.card => Icons.calendar_view_day_rounded,
        PostDisplay.mini => Icons.view_list_rounded,
        PostDisplay.calm => Icons.spa_rounded,
        PostDisplay.calmCards => Icons.spa_outlined,
      };

  /// Both Calm layouts share the Calm post view and the ⋮-sheet read toggle.
  bool get isCalm => this == PostDisplay.calm || this == PostDisplay.calmCards;
}

class Settings {
  const Settings({
    required this.themeMode,
    required this.amoled,
    required this.useDynamicColor,
    required this.jakartaFont,
    required this.inAppBrowser,
    required this.tapToCollapse,
    required this.collapseRepliesOnly,
    required this.voteEdge,
    required this.autoTranslate,
    required this.translateSecondLanguage,
    required this.translateService,
    required this.azureRegion,
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
    required this.blendReddit,
    required this.blendHome,
    required this.forYouDiscovery,
    required this.navOutline,
    required this.navStyle,
    required this.collapseBelowScore,
    required this.aiSummaryLanguage,
    required this.collapseTopLevel,
    required this.feedGalleryCarousel,
    required this.autoplaySound,
    required this.hiddenPostDays,
    required this.feedKeepMinutes,
    required this.subredditIcons,
    required this.dimReadTextOnly,
    required this.hideReadInSubreddits,
    required this.appFont,
    required this.appIcon,
  });

  final ThemeMode themeMode;
  final bool amoled;
  final bool useDynamicColor;
  final bool jakartaFont; // Plus Jakarta Sans + Unbounded instead of Roboto
  final bool inAppBrowser; // open web links in a Custom Tab, not the browser app
  final bool tapToCollapse; // tap a comment to collapse it (else long-press)
  // Collapsing keeps the comment's own text, hides its replies.
  final bool collapseRepliesOnly;
  // Comments you voted on get an edge in the vote's color.
  final bool voteEdge;
  // Posts in neither translation language open translated into the phone's.
  final bool autoTranslate;
  // Language code Translate also offers ('' = none).
  final String translateSecondLanguage;
  // For what the phone can't translate: 'openai' (the AI key) or 'azure'.
  final String translateService;
  // The Azure Translator resource's region ('' = global).
  final String azureRegion;
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
  final bool forYouFeed; // frontpage uses the "For You" feed
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
  // Blend: Reddit ↔ Ilay — 0 mostly Ilay, 1 balanced, 2 mostly Reddit.
  final int blendReddit;
  // With forYouFeed + Reddit Home allowed: Blend, For You ranking over your
  // Reddit Home too.
  final bool blendHome;
  // For You's Familiar (-2) ↔ Discover (+2) slider; 0 = adaptive default.
  final int forYouDiscovery;
  final bool navOutline; // thin outline around the floating bottom bar
  final int navStyle; // 0 bottom bar, 1 side bar, 2 both
  // Comments scoring below this start collapsed (null = off).
  final int? collapseBelowScore;
  // English name of the language summaries are written in; '' = the
  // thread's own.
  final String aiSummaryLanguage;
  // Threads open with top-level comments' replies collapsed.
  final bool collapseTopLevel;
  final bool feedGalleryCarousel; // galleries in feeds as the M3 carousel (else one image at a time)
  final bool autoplaySound; // feed videos start unmuted
  final int hiddenPostDays; // how long Ilay keeps posts you hid out of every feed (Reddit hides them too)
  final int feedKeepMinutes; // how long the frontpage keeps its posts before returning to it reloads
  final bool subredditIcons; // cards show the subreddit's icon (else its first letter)
  final bool dimReadTextOnly; // read posts: dim only title / text (images stay bright), else the whole card
  final bool hideReadInSubreddits; // …in single subreddits too (else front page / custom feeds only)
  final AppFont appFont; // the app's typeface
  final String appIcon; // app icon colour (AppIcon key)

  Settings copyWith({
    ThemeMode? themeMode,
    bool? amoled,
    bool? useDynamicColor,
    bool? jakartaFont,
    bool? inAppBrowser,
    bool? tapToCollapse,
    bool? collapseRepliesOnly,
    bool? voteEdge,
    bool? autoTranslate,
    String? translateSecondLanguage,
    String? translateService,
    String? azureRegion,
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
    int? blendReddit,
    bool? blendHome,
    int? forYouDiscovery,
    bool? navOutline,
    int? navStyle,
    int? collapseBelowScore,
    bool clearCollapseBelowScore = false,
    String? aiSummaryLanguage,
    bool? collapseTopLevel,
    bool? feedGalleryCarousel,
    bool? autoplaySound,
    int? hiddenPostDays,
    int? feedKeepMinutes,
    bool? subredditIcons,
    bool? dimReadTextOnly,
    bool? hideReadInSubreddits,
    AppFont? appFont,
    String? appIcon,
  }) =>
      Settings(
        themeMode: themeMode ?? this.themeMode,
        amoled: amoled ?? this.amoled,
        useDynamicColor: useDynamicColor ?? this.useDynamicColor,
        jakartaFont: jakartaFont ?? this.jakartaFont,
        inAppBrowser: inAppBrowser ?? this.inAppBrowser,
        tapToCollapse: tapToCollapse ?? this.tapToCollapse,
        collapseRepliesOnly: collapseRepliesOnly ?? this.collapseRepliesOnly,
        voteEdge: voteEdge ?? this.voteEdge,
        autoTranslate: autoTranslate ?? this.autoTranslate,
        translateSecondLanguage:
            translateSecondLanguage ?? this.translateSecondLanguage,
        translateService: translateService ?? this.translateService,
        azureRegion: azureRegion ?? this.azureRegion,
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
        blendReddit: blendReddit ?? this.blendReddit,
        blendHome: blendHome ?? this.blendHome,
        forYouDiscovery: forYouDiscovery ?? this.forYouDiscovery,
        navOutline: navOutline ?? this.navOutline,
        navStyle: navStyle ?? this.navStyle,
        collapseBelowScore: clearCollapseBelowScore
            ? null
            : (collapseBelowScore ?? this.collapseBelowScore),
        aiSummaryLanguage: aiSummaryLanguage ?? this.aiSummaryLanguage,
        collapseTopLevel: collapseTopLevel ?? this.collapseTopLevel,
        feedGalleryCarousel: feedGalleryCarousel ?? this.feedGalleryCarousel,
        autoplaySound: autoplaySound ?? this.autoplaySound,
        hiddenPostDays: hiddenPostDays ?? this.hiddenPostDays,
        feedKeepMinutes: feedKeepMinutes ?? this.feedKeepMinutes,
        subredditIcons: subredditIcons ?? this.subredditIcons,
        dimReadTextOnly: dimReadTextOnly ?? this.dimReadTextOnly,
        hideReadInSubreddits: hideReadInSubreddits ?? this.hideReadInSubreddits,
        appFont: appFont ?? this.appFont,
        appIcon: appIcon ?? this.appIcon,
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
      collapseRepliesOnly: p.getBool('collapseRepliesOnly') ?? false,
      voteEdge: p.getBool('voteEdge') ?? true,
      autoTranslate: p.getBool('autoTranslate') ?? false,
      translateSecondLanguage: p.getString('translateSecondLanguage') ?? '',
      translateService: p.getString('translateService') ?? 'openai',
      azureRegion: p.getString('azureRegion') ?? '',
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
          PostDisplay.values[p.getInt('postDisplay') ?? PostDisplay.calm.index],
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
      blendReddit: (p.getInt('blendReddit') ?? 1).clamp(0, 2),
      blendHome: p.getBool('blendHome') ?? false,
      forYouDiscovery: (p.getInt('forYouDiscovery') ?? 0).clamp(-2, 2),
      navOutline: p.getBool('navOutline') ?? true,
      navStyle: (p.getInt('navStyle') ?? 0).clamp(0, 2),
      collapseBelowScore: p.getInt('collapseBelowScore'),
      aiSummaryLanguage: p.getString('aiSummaryLanguage') ?? '',
      collapseTopLevel: p.getBool('collapseTopLevel') ?? false,
      feedGalleryCarousel: p.getBool('feedGalleryCarousel') ?? true,
      autoplaySound: p.getBool('autoplaySound') ?? false,
      hiddenPostDays: p.getInt('hiddenPostDays') ?? 7,
      feedKeepMinutes: p.getInt('feedKeepMinutes') ?? 30,
      subredditIcons: p.getBool('subredditIcons') ?? true,
      dimReadTextOnly: p.getBool('dimReadTextOnly') ?? false,
      hideReadInSubreddits: p.getBool('hideReadInSubreddits') ?? false,
      appFont: AppFont.parse(p.getString('appFont'), p.getBool('jakartaFont') ?? false),
      appIcon: p.getString('appIcon') ?? 'violet',
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
    // Anonymous: how many opt in to Home after the warning, and turn it off
    // again.
    if (v != state.redditHomeAllowed) {
      Analytics.track('home_toggled', {'on': v});
    }
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

  void setCollapseRepliesOnly(bool v) {
    _prefs.setBool('collapseRepliesOnly', v);
    state = state.copyWith(collapseRepliesOnly: v);
  }

  void setVoteEdge(bool v) {
    _prefs.setBool('voteEdge', v);
    state = state.copyWith(voteEdge: v);
  }

  void setAutoTranslate(bool v) {
    _prefs.setBool('autoTranslate', v);
    state = state.copyWith(autoTranslate: v);
  }

  void setTranslateSecondLanguage(String v) {
    _prefs.setString('translateSecondLanguage', v);
    state = state.copyWith(translateSecondLanguage: v);
  }

  void setTranslateService(String v) {
    _prefs.setString('translateService', v);
    state = state.copyWith(translateService: v);
  }

  void setAzureRegion(String v) {
    _prefs.setString('azureRegion', v);
    state = state.copyWith(azureRegion: v);
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

  void setAppIcon(String v) {
    _prefs.setString('appIcon', v);
    state = state.copyWith(appIcon: v);
  }

  void setAppFont(AppFont v) {
    _prefs.setString('appFont', v.name);
    // Keeps backups readable by older builds, which only had the switch.
    _prefs.setBool('jakartaFont', v == AppFont.jakarta);
    state = state.copyWith(appFont: v, jakartaFont: v == AppFont.jakarta);
  }

  void setHideReadInSubreddits(bool v) {
    _prefs.setBool('hideReadInSubreddits', v);
    state = state.copyWith(hideReadInSubreddits: v);
  }

  void setDimReadTextOnly(bool v) {
    _prefs.setBool('dimReadTextOnly', v);
    state = state.copyWith(dimReadTextOnly: v);
  }

  void setSubredditIcons(bool v) {
    _prefs.setBool('subredditIcons', v);
    state = state.copyWith(subredditIcons: v);
  }

  void setFeedKeepMinutes(int v) {
    _prefs.setInt('feedKeepMinutes', v);
    state = state.copyWith(feedKeepMinutes: v);
  }

  void setHiddenPostDays(int v) {
    _prefs.setInt('hiddenPostDays', v);
    state = state.copyWith(hiddenPostDays: v);
  }

  void setAutoplaySound(bool v) {
    _prefs.setBool('autoplaySound', v);
    state = state.copyWith(autoplaySound: v);
  }

  void setFeedGalleryCarousel(bool v) {
    _prefs.setBool('feedGalleryCarousel', v);
    state = state.copyWith(feedGalleryCarousel: v);
  }

  void setCollapseTopLevel(bool v) {
    _prefs.setBool('collapseTopLevel', v);
    state = state.copyWith(collapseTopLevel: v);
  }

  void setAiSummaryLanguage(String v) {
    _prefs.setString('aiSummaryLanguage', v);
    state = state.copyWith(aiSummaryLanguage: v);
  }

  void setCollapseBelowScore(int? v) {
    v == null
        ? _prefs.remove('collapseBelowScore')
        : _prefs.setInt('collapseBelowScore', v);
    state = state.copyWith(
        collapseBelowScore: v, clearCollapseBelowScore: v == null);
  }

  void setNavStyle(int v) {
    _prefs.setInt('navStyle', v);
    state = state.copyWith(navStyle: v);
  }

  void setNavOutline(bool v) {
    _prefs.setBool('navOutline', v);
    state = state.copyWith(navOutline: v);
  }

  void setForYouDiscovery(int v) {
    _prefs.setInt('forYouDiscovery', v);
    state = state.copyWith(forYouDiscovery: v);
  }

  void setBlendHome(bool v) {
    _prefs.setBool('blendHome', v);
    state = state.copyWith(blendHome: v);
  }

  void setBlendReddit(int v) {
    _prefs.setInt('blendReddit', v);
    state = state.copyWith(blendReddit: v);
  }
}

final settingsControllerProvider =
    NotifierProvider<SettingsController, Settings>(SettingsController.new);
