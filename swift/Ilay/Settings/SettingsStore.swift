import Foundation
import Observation

/// Loads [Settings] from [Prefs] and persists every change (same keys as Flutter).
@MainActor @Observable
final class SettingsStore {
    @ObservationIgnored private let p: Prefs
    /// Runs after every change, with the old and new settings (AppContainer's wiring).
    @ObservationIgnored var onChange: ((Settings, Settings) -> Void)?

    private(set) var value: Settings

    init(prefs: Prefs) {
        p = prefs
        value = SettingsStore.load(prefs)
    }

    private static func load(_ p: Prefs) -> Settings {
        var s = Settings()
        func b(_ k: String, _ def: Bool) -> Bool { p.getBool(k) ?? def }
        func idx<E: RawRepresentable>(_ k: String, _ def: E) -> E where E.RawValue == Int {
            p.getInt(k).flatMap(E.init(rawValue:)) ?? def
        }
        s.themeMode = idx("themeMode", s.themeMode)
        s.amoled = b("amoled", s.amoled)
        s.inAppBrowser = b("inAppBrowser", s.inAppBrowser)
        s.tapToCollapse = b("tapToCollapse", s.tapToCollapse)
        s.collapseRepliesOnly = b("collapseRepliesOnly", s.collapseRepliesOnly)
        s.voteEdge = b("voteEdge", s.voteEdge)
        s.autoTranslate = b("autoTranslate", s.autoTranslate)
        s.translateSecondLanguage = p.getString("translateSecondLanguage") ?? s.translateSecondLanguage
        s.translateService = p.getString("translateService") ?? s.translateService
        s.azureRegion = p.getString("azureRegion") ?? s.azureRegion
        s.collapseBelowScore = p.getInt("collapseBelowScore")
        s.collapseTopLevel = b("collapseTopLevel", s.collapseTopLevel)
        s.hideReadPosts = b("hideReadPosts", s.hideReadPosts)
        s.hideReadInSubreddits = b("hideReadInSubreddits", s.hideReadInSubreddits)
        s.recentSubsByVisits = b("recentSubredditsByVisits", s.recentSubsByVisits)
        s.dimReadTextOnly = b("dimReadTextOnly", s.dimReadTextOnly)
        s.dimRead = b("dimRead", s.dimRead)
        s.subredditIcons = b("subredditIcons", s.subredditIcons)
        s.markReadOnScroll = b("markReadOnScroll", s.markReadOnScroll)
        s.swipePostStart = SwipeAction.parse(p.getString("swipePostStart"), .upvote)
        s.swipePostEnd = SwipeAction.parse(p.getString("swipePostEnd"), .downvote)
        s.swipeCommentStart = SwipeAction.parse(p.getString("swipeCommentStart"), .upvote)
        s.swipeCommentEnd = SwipeAction.parse(p.getString("swipeCommentEnd"), .downvote)
        s.seedColor = p.getLong("seedColor").map { $0 & 0xFFFF_FFFF } ?? s.seedColor
        s.blurNsfw = b("blurNsfw", s.blurNsfw)
        s.defaultSort = idx("defaultSort", s.defaultSort)
        for row in p.getStringList("subredditSorts") ?? [] {
            let parts = row.components(separatedBy: "|")
            guard parts.count > 2,
                  let sort = PostSort.allCases.first(where: { $0.path == parts[1] }),
                  let time = TopTime.allCases.first(where: { $0.param == parts[2] }) else { continue }
            s.subredditSorts[parts[0]] = SubredditSort(sort: sort, time: time)
        }
        s.defaultCommentSort = p.getString("defaultCommentSort") ?? s.defaultCommentSort
        s.postDisplay = idx("postDisplay", s.postDisplay)
        s.commentStyle = idx("commentStyle", s.commentStyle)
        s.swipeActions = b("swipeActions", s.swipeActions)
        s.floatingChips = b("floatingChips", s.floatingChips)
        s.fullBarNewPost = b("fullBarNewPost", s.fullBarNewPost)
        s.trackHistory = b("trackHistory", s.trackHistory)
        s.showRecentlyVisited = b("showRecentlyVisited", s.showRecentlyVisited)
        s.offlineCache = b("offlineCache", s.offlineCache)
        s.checkUpdates = b("checkUpdates", s.checkUpdates)
        s.safariAsk = b("safariAsk", s.safariAsk)
        s.analytics = b("analytics", s.analytics)
        s.forYouFeed = b("forYouFeed", s.forYouFeed)
        s.postsTabAll = b("postsTabAll", s.postsTabAll)
        s.redditHomeAllowed = b("redditHomeAllowed", s.redditHomeAllowed)
        s.redditHomeFeed = b("redditHomeFeed", s.redditHomeFeed)
        s.autoHideReadForYou = b("autoHideReadForYou", s.autoHideReadForYou)
        s.blendHome = b("blendHome", s.blendHome)
        s.blendReddit = min(max(p.getInt("blendReddit") ?? s.blendReddit, 0), 2)
        s.forYouDiscovery = min(max(p.getInt("forYouDiscovery") ?? s.forYouDiscovery, -2), 2)
        s.midResThumbnails = b("midResThumbnails", s.midResThumbnails)
        s.subsCacheEnabled = b("subsCacheEnabled", s.subsCacheEnabled)
        s.subsCacheMinutes = p.getInt("subsCacheMinutes") ?? s.subsCacheMinutes
        s.imageCacheMb = p.getInt("imageCacheMb") ?? s.imageCacheMb
        s.videoCacheMb = p.getInt("videoCacheMb") ?? s.videoCacheMb
        s.feedKeepMinutes = p.getInt("feedKeepMinutes") ?? s.feedKeepMinutes
        s.hiddenPostDays = p.getInt("hiddenPostDays") ?? s.hiddenPostDays
        s.textScale = p.getDouble("textScale") ?? s.textScale
        s.autoplayMedia = b("autoplayMedia", s.autoplayMedia)
        s.autoplaySound = b("autoplaySound", s.autoplaySound)
        s.viewerMuted = b("viewerMuted", s.viewerMuted)
        s.feedGalleryCarousel = b("feedGalleryCarousel", s.feedGalleryCarousel)
        s.showApiUsage = b("showApiUsage", s.showApiUsage)
        s.notifyInbox = b("notifyInbox", s.notifyInbox)
        s.homeFab = idx("homeFab", s.homeFab)
        // Old installs may have stored the removed "compact" (1) or the old
        // expandable index (2); clamping maps both safely.
        if let m = p.getInt("topBarMode") {
            s.topBarMode = TopBarMode(rawValue: min(max(m, 0), TopBarMode.allCases.count - 1))!
        }
        s.navLabels = b("navLabels", s.navLabels)
        s.navStyle = min(max(p.getInt("navStyle") ?? s.navStyle, 0), 2)
        s.navOutline = b("navOutline", s.navOutline)
        s.backScrollsToTop = b("backScrollsToTop", s.backScrollsToTop)
        s.aiModel = p.getString("aiModel") ?? s.aiModel
        s.aiSummaryStyle = p.getInt("aiSummaryStyle") ?? s.aiSummaryStyle
        s.aiSummaryLanguage = p.getString("aiSummaryLanguage") ?? s.aiSummaryLanguage
        s.aiMaxChars = p.getInt("aiMaxChars") ?? s.aiMaxChars
        s.aiUseCustomUrl = b("aiUseCustomUrl", s.aiUseCustomUrl)
        s.aiBaseUrl = p.getString("aiBaseUrl") ?? s.aiBaseUrl
        s.appIcon = p.getString("appIcon") ?? s.appIcon
        return s
    }

    /// Re-reads everything from prefs (after a backup restore).
    func reload() { publish(SettingsStore.load(p)) }

    private func publish(_ next: Settings) {
        let old = value
        value = next
        onChange?(old, next)
    }

    private func set(_ change: (inout Settings) -> Void) {
        var next = value
        change(&next)
        publish(next)
    }

    func setThemeMode(_ v: ThemeMode) { p.setInt("themeMode", v.rawValue); set { $0.themeMode = v } }
    func setAmoled(_ v: Bool) { p.setBool("amoled", v); set { $0.amoled = v } }
    func setSeedColor(_ argb: Int) { p.setLong("seedColor", argb); set { $0.seedColor = argb } }
    func setBlurNsfw(_ v: Bool) { p.setBool("blurNsfw", v); set { $0.blurNsfw = v } }
    func setDefaultSort(_ v: PostSort) { p.setInt("defaultSort", v.rawValue); set { $0.defaultSort = v } }

    /// [v] nil: [name] goes back to following the default sort.
    func setSubredditSort(_ name: String, _ v: SubredditSort?) {
        var next = value.subredditSorts
        next[name.lowercased()] = v
        p.setStringList("subredditSorts", next.map { "\($0.key)|\($0.value.sort.path)|\($0.value.time.param)" })
        set { $0.subredditSorts = next }
    }

    func setDefaultCommentSort(_ v: String) { p.setString("defaultCommentSort", v); set { $0.defaultCommentSort = v } }
    func setPostDisplay(_ v: PostDisplay) { p.setInt("postDisplay", v.rawValue); set { $0.postDisplay = v } }
    func setCommentStyle(_ v: CommentStyle) { p.setInt("commentStyle", v.rawValue); set { $0.commentStyle = v } }
    func setSwipeActions(_ v: Bool) { p.setBool("swipeActions", v); set { $0.swipeActions = v } }
    func setFloatingChips(_ v: Bool) { p.setBool("floatingChips", v); set { $0.floatingChips = v } }
    func setFullBarNewPost(_ v: Bool) { p.setBool("fullBarNewPost", v); set { $0.fullBarNewPost = v } }
    func setTrackHistory(_ v: Bool) { p.setBool("trackHistory", v); set { $0.trackHistory = v } }
    func setShowRecentlyVisited(_ v: Bool) { p.setBool("showRecentlyVisited", v); set { $0.showRecentlyVisited = v } }
    func setOfflineCache(_ v: Bool) { p.setBool("offlineCache", v); set { $0.offlineCache = v } }
    func setCheckUpdates(_ v: Bool) { p.setBool("checkUpdates", v); set { $0.checkUpdates = v } }
    func setSafariAsk(_ v: Bool) { p.setBool("safariAsk", v); set { $0.safariAsk = v }; SharedHandover.shareSafariAsk() }
    func setAnalytics(_ v: Bool) { p.setBool("analytics", v); set { $0.analytics = v } }
    func setPostsTabAll(_ v: Bool) { p.setBool("postsTabAll", v); set { $0.postsTabAll = v } }

    /// Turning Reddit Home off in Settings also takes the frontpage off it.
    func setRedditHomeAllowed(_ v: Bool) {
        // Anonymous: how many opt in to Home after the warning, and turn it off again.
        if v != value.redditHomeAllowed { Analytics.track("home_toggled", ["on": .bool(v)]) }
        p.setBool("redditHomeAllowed", v)
        set { $0.redditHomeAllowed = v }
        if !v { setRedditHomeFeed(false) }
    }

    func setRedditHomeFeed(_ v: Bool) {
        p.setBool("redditHomeFeed", v)
        set { $0.redditHomeFeed = v }
        if v, value.forYouFeed {
            p.setBool("forYouFeed", false)
            set { $0.forYouFeed = false }
        }
    }

    /// One frontpage mode at a time.
    func setForYouFeed(_ v: Bool) {
        p.setBool("forYouFeed", v)
        set { $0.forYouFeed = v }
        if v { setRedditHomeFeed(false) }
    }

    func setBlendHome(_ v: Bool) { p.setBool("blendHome", v); set { $0.blendHome = v } }
    func setBlendReddit(_ v: Int) { p.setInt("blendReddit", v); set { $0.blendReddit = v } }
    func setAutoHideReadForYou(_ v: Bool) { p.setBool("autoHideReadForYou", v); set { $0.autoHideReadForYou = v } }
    func setForYouDiscovery(_ v: Int) { p.setInt("forYouDiscovery", v); set { $0.forYouDiscovery = v } }
    func setHideReadPosts(_ v: Bool) { p.setBool("hideReadPosts", v); set { $0.hideReadPosts = v } }
    func setHideReadInSubreddits(_ v: Bool) { p.setBool("hideReadInSubreddits", v); set { $0.hideReadInSubreddits = v } }
    func setRecentSubsByVisits(_ v: Bool) { p.setBool("recentSubredditsByVisits", v); set { $0.recentSubsByVisits = v } }
    /// Off leaves `dimReadTextOnly` as it was, so turning dimming back on restores the old choice.
    func setReadDim(_ v: ReadDim) {
        p.setBool("dimRead", v != .off)
        if v != .off { p.setBool("dimReadTextOnly", v == .text) }
        set {
            $0.dimRead = v != .off
            if v != .off { $0.dimReadTextOnly = v == .text }
        }
    }
    func setSubredditIcons(_ v: Bool) { p.setBool("subredditIcons", v); set { $0.subredditIcons = v } }
    func setMarkReadOnScroll(_ v: Bool) { p.setBool("markReadOnScroll", v); set { $0.markReadOnScroll = v } }

    /// [key] is one of swipePostStart / swipePostEnd / swipeCommentStart / swipeCommentEnd.
    func setSwipeAction(_ key: String, _ a: SwipeAction) {
        p.setString(key, a.key)
        set {
            switch key {
            case "swipePostStart": $0.swipePostStart = a
            case "swipePostEnd": $0.swipePostEnd = a
            case "swipeCommentStart": $0.swipeCommentStart = a
            default: $0.swipeCommentEnd = a
            }
        }
    }

    func setTapToCollapse(_ v: Bool) { p.setBool("tapToCollapse", v); set { $0.tapToCollapse = v } }
    func setCollapseRepliesOnly(_ v: Bool) { p.setBool("collapseRepliesOnly", v); set { $0.collapseRepliesOnly = v } }
    func setVoteEdge(_ v: Bool) { p.setBool("voteEdge", v); set { $0.voteEdge = v } }
    func setAutoTranslate(_ v: Bool) { p.setBool("autoTranslate", v); set { $0.autoTranslate = v } }
    func setTranslateSecondLanguage(_ v: String) { p.setString("translateSecondLanguage", v); set { $0.translateSecondLanguage = v } }
    func setTranslateService(_ v: String) { p.setString("translateService", v); set { $0.translateService = v } }
    func setAzureRegion(_ v: String) { p.setString("azureRegion", v); set { $0.azureRegion = v } }

    func setCollapseBelowScore(_ v: Int?) {
        if let v { p.setInt("collapseBelowScore", v) } else { p.remove("collapseBelowScore") }
        set { $0.collapseBelowScore = v }
    }

    func setCollapseTopLevel(_ v: Bool) { p.setBool("collapseTopLevel", v); set { $0.collapseTopLevel = v } }
    func setInAppBrowser(_ v: Bool) { p.setBool("inAppBrowser", v); set { $0.inAppBrowser = v } }
    func setMidResThumbnails(_ v: Bool) { p.setBool("midResThumbnails", v); set { $0.midResThumbnails = v } }
    func setSubsCacheEnabled(_ v: Bool) { p.setBool("subsCacheEnabled", v); set { $0.subsCacheEnabled = v } }
    func setSubsCacheMinutes(_ v: Int) { p.setInt("subsCacheMinutes", v); set { $0.subsCacheMinutes = v } }
    func setImageCacheMb(_ v: Int) { p.setInt("imageCacheMb", v); set { $0.imageCacheMb = v } }
    func setVideoCacheMb(_ v: Int) { p.setInt("videoCacheMb", v); set { $0.videoCacheMb = v } }
    func setFeedKeepMinutes(_ v: Int) { p.setInt("feedKeepMinutes", v); set { $0.feedKeepMinutes = v } }
    func setHiddenPostDays(_ v: Int) { p.setInt("hiddenPostDays", v); set { $0.hiddenPostDays = v } }
    func setTextScale(_ v: Double) { p.setDouble("textScale", v); set { $0.textScale = v } }
    func setAutoplayMedia(_ v: Bool) { p.setBool("autoplayMedia", v); set { $0.autoplayMedia = v } }
    func setAutoplaySound(_ v: Bool) { p.setBool("autoplaySound", v); set { $0.autoplaySound = v } }
    func setViewerMuted(_ v: Bool) { p.setBool("viewerMuted", v); set { $0.viewerMuted = v } }
    func setFeedGalleryCarousel(_ v: Bool) { p.setBool("feedGalleryCarousel", v); set { $0.feedGalleryCarousel = v } }
    func setShowApiUsage(_ v: Bool) { p.setBool("showApiUsage", v); set { $0.showApiUsage = v } }
    func setNotifyInbox(_ v: Bool) { p.setBool("notifyInbox", v); set { $0.notifyInbox = v } }
    func setHomeFab(_ v: HomeFab) { p.setInt("homeFab", v.rawValue); set { $0.homeFab = v } }
    func setTopBarMode(_ v: TopBarMode) { p.setInt("topBarMode", v.rawValue); set { $0.topBarMode = v } }
    func setNavLabels(_ v: Bool) { p.setBool("navLabels", v); set { $0.navLabels = v } }
    func setNavStyle(_ v: Int) { p.setInt("navStyle", v); set { $0.navStyle = v } }
    func setNavOutline(_ v: Bool) { p.setBool("navOutline", v); set { $0.navOutline = v } }
    func setBackScrollsToTop(_ v: Bool) { p.setBool("backScrollsToTop", v); set { $0.backScrollsToTop = v } }
    func setAiModel(_ v: String) { p.setString("aiModel", v); set { $0.aiModel = v } }
    func setAiSummaryStyle(_ v: Int) { p.setInt("aiSummaryStyle", v); set { $0.aiSummaryStyle = v } }
    func setAiSummaryLanguage(_ v: String) { p.setString("aiSummaryLanguage", v); set { $0.aiSummaryLanguage = v } }
    func setAiMaxChars(_ v: Int) { p.setInt("aiMaxChars", v); set { $0.aiMaxChars = v } }
    func setAiUseCustomUrl(_ v: Bool) { p.setBool("aiUseCustomUrl", v); set { $0.aiUseCustomUrl = v } }
    func setAiBaseUrl(_ v: String) { p.setString("aiBaseUrl", v); set { $0.aiBaseUrl = v } }
    func setAppIcon(_ v: String) { p.setString("appIcon", v); set { $0.appIcon = v } }
}
