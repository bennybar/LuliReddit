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
        s.commentButtonsOnTap = b("commentButtonsOnTap", s.commentButtonsOnTap)
        s.voteEdge = b("voteEdge", s.voteEdge)
        s.voteGlow = b("voteGlow", s.voteGlow)
        s.commentAvatars = b("commentAvatars", s.commentAvatars)
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
        s.subredditPrefix = b("subredditPrefix", s.subredditPrefix)
        s.postAvatars = b("postAvatars", s.postAvatars)
        s.sideBarUserPrefix = b("sideBarUserPrefix", s.sideBarUserPrefix)
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
        s.postTextLines = p.getInt("postTextLines") ?? s.postTextLines
        s.commentStyle = idx("commentStyle", s.commentStyle)
        s.swipeActions = b("swipeActions", s.swipeActions)
        s.floatingChips = b("floatingChips", s.floatingChips)
        s.fullBarNewPost = b("fullBarNewPost", s.fullBarNewPost)
        s.trackHistory = b("trackHistory", s.trackHistory)
        s.showRecentlyVisited = b("showRecentlyVisited", s.showRecentlyVisited)
        s.newPostsPill = b("newPostsPill", s.newPostsPill)
        s.exploreSections = ExploreSection.parse(p.getStringList(ExploreSection.prefsKey))
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
        s.digestEnabled = b("digestEnabled", s.digestEnabled)
        s.digestSize = min(max(p.getInt("digestSize") ?? s.digestSize, 0), 2)
        // Unknown (1 is a bottom tab, not offered yet): the chip.
        // 0 the Posts chip, 1 a bottom tab, 2 menu only; anything else: the chip.
        s.digestPlace = (0...2).contains(p.getInt("digestPlace") ?? 0) ? p.getInt("digestPlace") ?? 0 : 0
        s.digestShowRead = b("digestShowRead", s.digestShowRead)
        s.digestAi = b("digestAi", s.digestAi)
        s.digestOverview = b("digestOverview", s.digestOverview)
        s.digestOrder = min(max(p.getInt("digestOrder") ?? s.digestOrder, 0), 3)
        s.digestSwipe = min(max(p.getInt("digestSwipe") ?? s.digestSwipe, 0), 2)
        s.digestAiBuilds = min(max(p.getInt("digestAiBuilds") ?? s.digestAiBuilds, 0), 1)
        s.digestAiPick = b("digestAiPick", s.digestAiPick)
        s.digestAiWhy = b("digestAiWhy", s.digestAiWhy)
        s.digestLanguage = p.getString("digestLanguage")
        s.digestNotify = b("digestNotify", s.digestNotify)
        s.digestTime = min(max(p.getInt("digestTime") ?? s.digestTime, 0), 24 * 60 - 1)
        s.forYouDiscovery = min(max(p.getInt("forYouDiscovery") ?? s.forYouDiscovery, -2), 2)
        s.midResThumbnails = b("midResThumbnails", s.midResThumbnails)
        s.subsCacheEnabled = b("subsCacheEnabled", s.subsCacheEnabled)
        s.subsCacheMinutes = p.getInt("subsCacheMinutes") ?? s.subsCacheMinutes
        s.imageCacheMb = p.getInt("imageCacheMb") ?? s.imageCacheMb
        s.videoCacheMb = p.getInt("videoCacheMb") ?? s.videoCacheMb
        s.feedKeepMinutes = p.getInt("feedKeepMinutes") ?? s.feedKeepMinutes
        s.hiddenPostDays = p.getInt("hiddenPostDays") ?? s.hiddenPostDays
        s.textScale = p.getDouble("textScale") ?? s.textScale
        s.titleTextScale = min(max(p.getDouble("titleTextScale") ?? s.titleTextScale, 0.8), 1.6)
        s.postTextScale = min(max(p.getDouble("postTextScale") ?? s.postTextScale, 0.8), 1.6)
        s.commentTextScale = min(max(p.getDouble("commentTextScale") ?? s.commentTextScale, 0.8), 1.6)
        s.autoplayMedia = b("autoplayMedia", s.autoplayMedia)
        s.autoplayWifiOnly = b("autoplayWifiOnly", s.autoplayWifiOnly)
        s.autoplaySound = b("autoplaySound", s.autoplaySound)
        s.viewerMuted = b("viewerMuted", s.viewerMuted)
        s.loopVideos = b("loopVideos", s.loopVideos)
        s.feedGalleryCarousel = b("feedGalleryCarousel", s.feedGalleryCarousel)
        s.showApiUsage = b("showApiUsage", s.showApiUsage)
        s.notifyInbox = b("notifyInbox", s.notifyInbox)
        s.inboxCheckMinutes = p.getInt("inboxCheckMinutes") ?? s.inboxCheckMinutes
        s.homeFab = idx("homeFab", s.homeFab)
        s.threadFabPosition = idx("threadFabPosition", s.threadFabPosition)
        s.threadJumpOp = b("threadJumpOp", s.threadJumpOp)
        s.threadJumpMine = b("threadJumpMine", s.threadJumpMine)
        s.threadJumpNext = b("threadJumpNext", s.threadJumpNext)
        s.threadButtonsHideOnScroll = b("threadButtonsHideOnScroll", s.threadButtonsHideOnScroll)
        s.resumeThreads = b("resumeThreads", s.resumeThreads)
        // Old installs may have stored the removed "compact" (1) or the old
        // expandable index (2); clamping maps both safely.
        if let m = p.getInt("cornerRoundness") {
            s.cornerRoundness = CornerRoundness(rawValue: min(max(m, 0), CornerRoundness.allCases.count - 1))!
        }
        if let m = p.getInt("topBarMode") {
            s.topBarMode = TopBarMode(rawValue: min(max(m, 0), TopBarMode.allCases.count - 1))!
        }
        s.navLabels = b("navLabels", s.navLabels)
        s.inboxInProfile = b("inboxInProfile", s.inboxInProfile)
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
    func setPostTextLines(_ v: Int) { p.setInt("postTextLines", v); set { $0.postTextLines = v } }
    func setCommentStyle(_ v: CommentStyle) { p.setInt("commentStyle", v.rawValue); set { $0.commentStyle = v } }
    func setSwipeActions(_ v: Bool) { p.setBool("swipeActions", v); set { $0.swipeActions = v } }
    func setFloatingChips(_ v: Bool) { p.setBool("floatingChips", v); set { $0.floatingChips = v } }
    func setFullBarNewPost(_ v: Bool) { p.setBool("fullBarNewPost", v); set { $0.fullBarNewPost = v } }
    func setTrackHistory(_ v: Bool) { p.setBool("trackHistory", v); set { $0.trackHistory = v } }
    func setNewPostsPill(_ v: Bool) { p.setBool("newPostsPill", v); set { $0.newPostsPill = v } }
    func setShowRecentlyVisited(_ v: Bool) { p.setBool("showRecentlyVisited", v); set { $0.showRecentlyVisited = v } }
    /// `entries` nil: back to the default Explore (and whatever sections later versions add to it).
    func setExploreSections(_ entries: [ExploreEntry]?) {
        if let entries { p.setStringList(ExploreSection.prefsKey, ExploreSection.toPrefs(entries)) } else { p.remove(ExploreSection.prefsKey) }
        set { $0.exploreSections = ExploreSection.parse(entries.map(ExploreSection.toPrefs)) }
    }
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
    func setDigestEnabled(_ v: Bool) { p.setBool("digestEnabled", v); set { $0.digestEnabled = v } }
    func setDigestSize(_ v: Int) { p.setInt("digestSize", v); set { $0.digestSize = v } }
    func setDigestPlace(_ v: Int) { p.setInt("digestPlace", v); set { $0.digestPlace = v } }
    func setDigestShowRead(_ v: Bool) { p.setBool("digestShowRead", v); set { $0.digestShowRead = v } }
    func setDigestAi(_ v: Bool) { p.setBool("digestAi", v); set { $0.digestAi = v } }
    func setDigestOverview(_ v: Bool) { p.setBool("digestOverview", v); set { $0.digestOverview = v } }
    func setDigestSwipe(_ v: Int) { p.setInt("digestSwipe", v); set { $0.digestSwipe = v } }
    func setDigestOrder(_ v: Int) { p.setInt("digestOrder", v); set { $0.digestOrder = v } }
    func setDigestAiBuilds(_ v: Int) { p.setInt("digestAiBuilds", v); set { $0.digestAiBuilds = v } }
    func setDigestAiPick(_ v: Bool) { p.setBool("digestAiPick", v); set { $0.digestAiPick = v } }
    func setDigestAiWhy(_ v: Bool) { p.setBool("digestAiWhy", v); set { $0.digestAiWhy = v } }
    func setDigestLanguage(_ v: String?) { if let v { p.setString("digestLanguage", v) } else { p.remove("digestLanguage") }; set { $0.digestLanguage = v } }
    func setDigestNotify(_ v: Bool) { p.setBool("digestNotify", v); set { $0.digestNotify = v } }
    func setDigestTime(_ v: Int) { p.setInt("digestTime", v); set { $0.digestTime = v } }
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
    func setSubredditPrefix(_ v: Bool) { p.setBool("subredditPrefix", v); set { $0.subredditPrefix = v } }
    func setPostAvatars(_ v: Bool) { p.setBool("postAvatars", v); set { $0.postAvatars = v } }
    func setSideBarUserPrefix(_ v: Bool) { p.setBool("sideBarUserPrefix", v); set { $0.sideBarUserPrefix = v } }
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
    func setCommentButtonsOnTap(_ v: Bool) { p.setBool("commentButtonsOnTap", v); set { $0.commentButtonsOnTap = v } }
    func setCollapseRepliesOnly(_ v: Bool) { p.setBool("collapseRepliesOnly", v); set { $0.collapseRepliesOnly = v } }
    func setVoteEdge(_ v: Bool) { p.setBool("voteEdge", v); set { $0.voteEdge = v } }
    func setVoteGlow(_ v: Bool) { p.setBool("voteGlow", v); set { $0.voteGlow = v } }
    func setCommentAvatars(_ v: Bool) { p.setBool("commentAvatars", v); set { $0.commentAvatars = v } }
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
    /// Off keeps the Wi-Fi choice, so the quick on/off switch turns back on to it.
    func setAutoplayMode(_ m: AutoplayMode) {
        setAutoplayMedia(m != .off)
        if m != .off { p.setBool("autoplayWifiOnly", m == .wifi); set { $0.autoplayWifiOnly = m == .wifi } }
    }
    func setAutoplaySound(_ v: Bool) { p.setBool("autoplaySound", v); set { $0.autoplaySound = v } }
    func setViewerMuted(_ v: Bool) { p.setBool("viewerMuted", v); set { $0.viewerMuted = v } }
    func setLoopVideos(_ v: Bool) { p.setBool("loopVideos", v); set { $0.loopVideos = v } }
    func setFeedGalleryCarousel(_ v: Bool) { p.setBool("feedGalleryCarousel", v); set { $0.feedGalleryCarousel = v } }
    func setShowApiUsage(_ v: Bool) { p.setBool("showApiUsage", v); set { $0.showApiUsage = v } }
    func setNotifyInbox(_ v: Bool) { p.setBool("notifyInbox", v); set { $0.notifyInbox = v } }
    func setInboxCheckMinutes(_ v: Int) { p.setInt("inboxCheckMinutes", v); set { $0.inboxCheckMinutes = v } }
    func setHomeFab(_ v: HomeFab) { p.setInt("homeFab", v.rawValue); set { $0.homeFab = v } }
    func setThreadFabPosition(_ v: ThreadFabPosition) { p.setInt("threadFabPosition", v.rawValue); set { $0.threadFabPosition = v } }
    func setThreadJumpOp(_ v: Bool) { p.setBool("threadJumpOp", v); set { $0.threadJumpOp = v } }
    func setThreadJumpMine(_ v: Bool) { p.setBool("threadJumpMine", v); set { $0.threadJumpMine = v } }
    func setThreadJumpNext(_ v: Bool) { p.setBool("threadJumpNext", v); set { $0.threadJumpNext = v } }
    func setThreadButtonsHideOnScroll(_ v: Bool) { p.setBool("threadButtonsHideOnScroll", v); set { $0.threadButtonsHideOnScroll = v } }
    func setResumeThreads(_ v: Bool) { p.setBool("resumeThreads", v); set { $0.resumeThreads = v } }
    func setTopBarMode(_ v: TopBarMode) { p.setInt("topBarMode", v.rawValue); set { $0.topBarMode = v } }
    func setCornerRoundness(_ v: CornerRoundness) { p.setInt("cornerRoundness", v.rawValue); set { $0.cornerRoundness = v } }
    func setTitleTextScale(_ v: Double) { p.setDouble("titleTextScale", v); set { $0.titleTextScale = v } }
    func setPostTextScale(_ v: Double) { p.setDouble("postTextScale", v); set { $0.postTextScale = v } }
    func setCommentTextScale(_ v: Double) { p.setDouble("commentTextScale", v); set { $0.commentTextScale = v } }

    /// All text sizes back to normal: the app's and the three on top of it.
    func resetTextScales() {
        for k in ["textScale", "titleTextScale", "postTextScale", "commentTextScale"] { p.remove(k) }
        set {
            $0.textScale = 1
            $0.titleTextScale = 1
            $0.postTextScale = 1
            $0.commentTextScale = 1
        }
    }

    func setNavLabels(_ v: Bool) { p.setBool("navLabels", v); set { $0.navLabels = v } }
    func setInboxInProfile(_ v: Bool) { p.setBool("inboxInProfile", v); set { $0.inboxInProfile = v } }
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
