package com.bennybar.luli_for_reddit.settings

import com.bennybar.luli_for_reddit.core.storage.Prefs
import com.bennybar.luli_for_reddit.data.PostSort
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update

/** Loads [Settings] from [Prefs] and persists every change (same keys as Flutter). */
class SettingsStore(private val p: Prefs) {
    private val _state = MutableStateFlow(load())
    val state: StateFlow<Settings> = _state
    val value: Settings get() = _state.value

    private fun load(): Settings {
        val d = Settings()
        fun b(k: String, def: Boolean) = p.getBool(k) ?: def
        fun <E : Enum<E>> idx(values: Array<E>, k: String, def: E): E =
            p.getInt(k)?.let { values.getOrNull(it) } ?: def
        return Settings(
            themeMode = idx(ThemeMode.entries.toTypedArray(), "themeMode", d.themeMode),
            amoled = b("amoled", d.amoled),
            useDynamicColor = b("useDynamicColor", d.useDynamicColor),
            jakartaFont = b("jakartaFont", d.jakartaFont),
            // Before the picker there was only the Jakarta switch (Flutter's too).
            appFont = AppFont.parse(p.getString("appFont"), if (b("jakartaFont", false)) AppFont.JAKARTA else AppFont.ROBOTO),
            inAppBrowser = b("inAppBrowser", d.inAppBrowser),
            tapToCollapse = b("tapToCollapse", d.tapToCollapse),
            hideReadPosts = b("hideReadPosts", d.hideReadPosts),
            markReadOnScroll = b("markReadOnScroll", d.markReadOnScroll),
            swipePostStart = SwipeAction.parse(p.getString("swipePostStart"), SwipeAction.UPVOTE),
            swipePostEnd = SwipeAction.parse(p.getString("swipePostEnd"), SwipeAction.DOWNVOTE),
            swipeCommentStart = SwipeAction.parse(p.getString("swipeCommentStart"), SwipeAction.UPVOTE),
            swipeCommentEnd = SwipeAction.parse(p.getString("swipeCommentEnd"), SwipeAction.DOWNVOTE),
            seedColor = p.getLong("seedColor")?.and(0xFFFFFFFFL) ?: d.seedColor,
            blurNsfw = b("blurNsfw", d.blurNsfw),
            defaultSort = idx(PostSort.entries.toTypedArray(), "defaultSort", d.defaultSort),
            defaultCommentSort = p.getString("defaultCommentSort") ?: d.defaultCommentSort,
            postDisplay = idx(PostDisplay.entries.toTypedArray(), "postDisplay", d.postDisplay),
            swipeActions = b("swipeActions", d.swipeActions),
            trackHistory = b("trackHistory", d.trackHistory),
            offlineCache = b("offlineCache", d.offlineCache),
            checkUpdates = b("checkUpdates", d.checkUpdates),
            forYouFeed = b("forYouFeed", d.forYouFeed),
            redditHomeAllowed = b("redditHomeAllowed", d.redditHomeAllowed),
            redditHomeFeed = b("redditHomeFeed", d.redditHomeFeed),
            autoHideReadForYou = b("autoHideReadForYou", d.autoHideReadForYou),
            midResThumbnails = b("midResThumbnails", d.midResThumbnails),
            subsCacheEnabled = b("subsCacheEnabled", d.subsCacheEnabled),
            subsCacheMinutes = p.getInt("subsCacheMinutes") ?: d.subsCacheMinutes,
            textScale = p.getDouble("textScale") ?: d.textScale,
            autoplayMedia = b("autoplayMedia", d.autoplayMedia),
            showApiUsage = b("showApiUsage", d.showApiUsage),
            notifyInbox = b("notifyInbox", d.notifyInbox),
            // Old installs may have stored the removed "compact" (1) or the old
            // expandable index (2); clamping maps both safely.
            topBarMode = p.getInt("topBarMode")?.let {
                TopBarMode.entries[it.coerceIn(0, TopBarMode.entries.size - 1)]
            } ?: d.topBarMode,
            navLabels = b("navLabels", d.navLabels),
            aiModel = p.getString("aiModel") ?: d.aiModel,
            aiSummaryStyle = p.getInt("aiSummaryStyle") ?: d.aiSummaryStyle,
            aiMaxChars = p.getInt("aiMaxChars") ?: d.aiMaxChars,
            aiUseCustomUrl = b("aiUseCustomUrl", d.aiUseCustomUrl),
            aiBaseUrl = p.getString("aiBaseUrl") ?: d.aiBaseUrl,
            appIcon = p.getString("appIcon") ?: d.appIcon,
        )
    }

    /** Re-reads everything from prefs (after a backup restore). */
    fun reload() {
        _state.value = load()
    }

    private inline fun set(block: (Settings) -> Settings) = _state.update(block)

    fun setThemeMode(v: ThemeMode) { p.setInt("themeMode", v.ordinal); set { it.copy(themeMode = v) } }
    fun setAmoled(v: Boolean) { p.setBool("amoled", v); set { it.copy(amoled = v) } }
    fun setUseDynamicColor(v: Boolean) { p.setBool("useDynamicColor", v); set { it.copy(useDynamicColor = v) } }
    fun setSeedColor(argb: Long) { p.setLong("seedColor", argb); set { it.copy(seedColor = argb) } }
    fun setBlurNsfw(v: Boolean) { p.setBool("blurNsfw", v); set { it.copy(blurNsfw = v) } }
    fun setDefaultSort(v: PostSort) { p.setInt("defaultSort", v.ordinal); set { it.copy(defaultSort = v) } }
    fun setDefaultCommentSort(v: String) { p.setString("defaultCommentSort", v); set { it.copy(defaultCommentSort = v) } }
    fun setPostDisplay(v: PostDisplay) { p.setInt("postDisplay", v.ordinal); set { it.copy(postDisplay = v) } }
    fun setSwipeActions(v: Boolean) { p.setBool("swipeActions", v); set { it.copy(swipeActions = v) } }
    fun setTrackHistory(v: Boolean) { p.setBool("trackHistory", v); set { it.copy(trackHistory = v) } }
    fun setOfflineCache(v: Boolean) { p.setBool("offlineCache", v); set { it.copy(offlineCache = v) } }
    fun setCheckUpdates(v: Boolean) { p.setBool("checkUpdates", v); set { it.copy(checkUpdates = v) } }

    /** Turning Reddit Home off in Settings also takes the frontpage off it. */
    fun setRedditHomeAllowed(v: Boolean) {
        p.setBool("redditHomeAllowed", v)
        set { it.copy(redditHomeAllowed = v) }
        if (!v) setRedditHomeFeed(false)
    }

    fun setRedditHomeFeed(v: Boolean) {
        p.setBool("redditHomeFeed", v)
        set { it.copy(redditHomeFeed = v) }
        if (v && value.forYouFeed) {
            p.setBool("forYouFeed", false)
            set { it.copy(forYouFeed = false) }
        }
    }

    /** One frontpage mode at a time. */
    fun setForYouFeed(v: Boolean) {
        p.setBool("forYouFeed", v)
        set { it.copy(forYouFeed = v) }
        if (v) setRedditHomeFeed(false)
    }

    fun setAutoHideReadForYou(v: Boolean) { p.setBool("autoHideReadForYou", v); set { it.copy(autoHideReadForYou = v) } }
    fun setAppFont(v: AppFont) {
        p.setString("appFont", v.key)
        p.setBool("jakartaFont", v == AppFont.JAKARTA) // keeps backups readable by older builds
        set { it.copy(appFont = v, jakartaFont = v == AppFont.JAKARTA) }
    }
    fun setHideReadPosts(v: Boolean) { p.setBool("hideReadPosts", v); set { it.copy(hideReadPosts = v) } }
    fun setMarkReadOnScroll(v: Boolean) { p.setBool("markReadOnScroll", v); set { it.copy(markReadOnScroll = v) } }

    /** [key] is one of swipePostStart / swipePostEnd / swipeCommentStart / swipeCommentEnd. */
    fun setSwipeAction(key: String, a: SwipeAction) {
        p.setString(key, a.key)
        set {
            when (key) {
                "swipePostStart" -> it.copy(swipePostStart = a)
                "swipePostEnd" -> it.copy(swipePostEnd = a)
                "swipeCommentStart" -> it.copy(swipeCommentStart = a)
                else -> it.copy(swipeCommentEnd = a)
            }
        }
    }

    fun setTapToCollapse(v: Boolean) { p.setBool("tapToCollapse", v); set { it.copy(tapToCollapse = v) } }
    fun setInAppBrowser(v: Boolean) { p.setBool("inAppBrowser", v); set { it.copy(inAppBrowser = v) } }
    fun setMidResThumbnails(v: Boolean) { p.setBool("midResThumbnails", v); set { it.copy(midResThumbnails = v) } }
    fun setSubsCacheEnabled(v: Boolean) { p.setBool("subsCacheEnabled", v); set { it.copy(subsCacheEnabled = v) } }
    fun setSubsCacheMinutes(v: Int) { p.setInt("subsCacheMinutes", v); set { it.copy(subsCacheMinutes = v) } }
    fun setTextScale(v: Double) { p.setDouble("textScale", v); set { it.copy(textScale = v) } }
    fun setAutoplayMedia(v: Boolean) { p.setBool("autoplayMedia", v); set { it.copy(autoplayMedia = v) } }
    fun setShowApiUsage(v: Boolean) { p.setBool("showApiUsage", v); set { it.copy(showApiUsage = v) } }
    fun setNotifyInbox(v: Boolean) { p.setBool("notifyInbox", v); set { it.copy(notifyInbox = v) } }
    fun setTopBarMode(v: TopBarMode) { p.setInt("topBarMode", v.ordinal); set { it.copy(topBarMode = v) } }
    fun setNavLabels(v: Boolean) { p.setBool("navLabels", v); set { it.copy(navLabels = v) } }
    fun setAiModel(v: String) { p.setString("aiModel", v); set { it.copy(aiModel = v) } }
    fun setAiSummaryStyle(v: Int) { p.setInt("aiSummaryStyle", v); set { it.copy(aiSummaryStyle = v) } }
    fun setAiMaxChars(v: Int) { p.setInt("aiMaxChars", v); set { it.copy(aiMaxChars = v) } }
    fun setAiUseCustomUrl(v: Boolean) { p.setBool("aiUseCustomUrl", v); set { it.copy(aiUseCustomUrl = v) } }
    fun setAiBaseUrl(v: String) { p.setString("aiBaseUrl", v); set { it.copy(aiBaseUrl = v) } }
    fun setAppIcon(v: String) { p.setString("appIcon", v); set { it.copy(appIcon = v) } }
}

