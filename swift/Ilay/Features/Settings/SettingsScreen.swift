import SwiftUI
import UniformTypeIdentifiers

// Left out, as PORTING.md drops them or the system's own controls replace them:
// App font, Dynamic color, Volume keys, Open Reddit app notifications in Ilay;
// Bottom bar labels and outline (the system's tab bar has neither); Save media to
// (Android's folder: on iOS media saves to the "Ilay" album). Their prefs stay untouched.

let accentSwatches: [(argb: Int, name: String)] = [
    (0xFF6750A4, "Lavender"), // default
    (0xFFEA4335, "Red"),
    (0xFFFF7043, "Orange"),
    (0xFFFFB300, "Amber"),
    (0xFF34A853, "Green"),
    (0xFF00897B, "Teal"),
    (0xFF1E88E5, "Blue"),
    (0xFF8E24AA, "Purple"),
    (0xFFD81B60, "Pink"),
]

/// Summary languages: the English name (what the AI is told) to its label. "" = the thread's own.
private let summaryLanguages: [(String, String)] = [
    ("", "Same as the thread"),
    ("English", "English"),
    ("Hebrew", "Hebrew · עברית"),
    ("Spanish", "Spanish · Español"),
    ("French", "French · Français"),
    ("German", "German · Deutsch"),
    ("Portuguese", "Portuguese · Português"),
    ("Italian", "Italian · Italiano"),
    ("Russian", "Russian · Русский"),
    ("Arabic", "Arabic · العربية"),
    ("Simplified Chinese", "Chinese · 中文"),
    ("Japanese", "Japanese · 日本語"),
    ("Hindi", "Hindi · हिन्दी"),
]

/// AI summary styles, by persisted index (`aiSummaryStyle`).
private let summaryStyleLabels = ["TL;DR", "Key points", "Consensus & disagreements", "Explain like I'm 5"]

private let aiModels = ["gpt-6.1-sol", "gpt-5.5", "gpt-5.4-mini", "gpt-5.4-nano"]

let navStyles: [(String, String)] = [
    ("Bottom bar", "The tab bar at the bottom"),
    ("Side bar", "The ☰ at the top of each tab opens it, or swipe in from the left edge"),
    ("Both", "The tab bar, plus the side bar (☰, or swipe in from the left edge)"),
]

private let customModel = "\0custom"

/// Settings → Second language: the languages Ilay can translate into (phone or service).
private let translateLanguages = [
    "ar", "de", "en", "es", "fr", "he", "hi", "id", "it", "ja", "ko", "nl", "pl", "pt", "ru", "th", "tr", "uk", "vi", "zh",
]

/// The main page's categories (#68), in groups: a section of the list, what's in it, its icon and colour.
let settingsCategories: [[(title: String, subtitle: String, icon: String, color: Color)]] = [
    [
        ("Feed", "Layout, sort, For You, what's hidden", "newspaper.fill", .blue),
        ("Appearance", "Theme, font size, app icon, navigation", "paintpalette.fill", .indigo),
        ("Posts & comments", "Comment style, collapsing, swipes", "bubble.left.and.bubble.right.fill", .green),
        ("Media", "Autoplay, NSFW blur, thumbnails", "photo.on.rectangle.angled", .pink),
    ],
    [
        ("Notifications", "Inbox alerts", "bell.badge.fill", .red),
        ("Translation", "Languages and service", "translate", .teal),
        ("AI summaries", "Key, model, style", "sparkles", .purple),
    ],
    [
        ("Data & storage", "History, cache, backup", "internaldrive.fill", .gray),
        ("Account & keys", "Login, API keys, clear data", "person.badge.key.fill", .orange),
        ("Power-user features", "API usage", "slider.horizontal.3", .brown),
    ],
    [("About", "Version, updates, licenses", "info.circle.fill", .gray)],
]

/// Whether each key is set, and how the account signed in: read from the keychain by the screen.
struct SecureFlags: Equatable {
    var aiKey = false
    var giphyKey = false
    var azureKey = false
    var web = false
}

/// Every setting, as rows. The same structure as Kotlin's `SettingsList`: one list of
/// sections, which the screen narrows to a category or to what a search matches.
@MainActor
struct SettingsCatalog {
    let s: Settings
    var secure = SecureFlags()
    var hiddenSubs = 0
    var prompts = SettingsPrompts()

    private var ctrl: SettingsStore { app.settings }

    var entries: [SettingEntry] {
        let b = RowBuilder()
        feed(b)
        appearance(b)
        postsAndComments(b)
        media(b)
        notifications(b)
        translation(b)
        aiSummaries(b)
        dataAndStorage(b)
        account(b)
        powerUser(b)
        about(b)
        return b.rows
    }

    /// One section's rows.
    func rows(section: String) -> [SettingEntry] { entries.filter { $0.section == section } }

    /// What a search shows: every row, in any section, whose title or subtitle contains it.
    func matching(_ query: String) -> [SettingEntry] {
        let q = query.trimmed.lowercased()
        return entries.filter { $0.search?.lowercased().contains(q) == true }
    }

    // MARK: - Feed

    private func feed(_ b: RowBuilder) {
        b.section("Feed")
        b.picker("Post display", value: s.postDisplay, options: PostDisplay.allCases.map { PickOption(value: $0, label: $0.label, icon: $0.icon) }, set: ctrl.setPostDisplay)
        b.toggle("Subreddit icons", "Show each community's icon on posts instead of its first letter", s.subredditIcons, set: ctrl.setSubredditIcons)
        b.picker("Default sort", value: s.defaultSort, options: PostSort.allCases.map { PickOption(value: $0, label: $0.label) }, set: ctrl.setDefaultSort)
        b.toggle(
            "Posts tab shows r/all", "Instead of your frontpage, which Explore's All button opens then. For You, Blend and Reddit Home don't apply.",
            s.postsTabAll, set: ctrl.setPostsTabAll
        )
        b.toggle("\"For You\" feed", "A personalized frontpage, built on your phone from what you read and like", s.forYouFeed, set: ctrl.setForYouFeed)
        b.toggle("Auto-hide read items in \"For You\"", "Hide posts you've marked/opened as read", s.autoHideReadForYou, set: ctrl.setAutoHideReadForYou)
        b.custom("forYouDiscovery", title: "For You mix", search: "For You mix familiar discover new communities") {
            ForYouMixSlider(value: s.forYouDiscovery)
        }
        b.link("Manage \"For You\" subreddits", "Review and undo muted / show-less subreddits", .manageForYou)
        let homeSubtitle = secure.web ? "Unofficial, against Reddit's terms. Shows your real reddit.com Home" : "Needs website sign-in"
        let prompts = prompts
        b.toggle(
            "Reddit Home (experimental)", homeSubtitle, s.redditHomeAllowed,
            enabled: secure.web || s.redditHomeAllowed,
            accent: homeAmber
        ) { v in
            if !v {
                app.settings.setRedditHomeAllowed(false)
                return
            }
            Task {
                if await confirmRedditHome() { app.settings.setRedditHomeAllowed(true) }
                prompts.refresh += 1
            }
        }
        if s.redditHomeAllowed {
            b.toggle(
                "Blend (Beta)", "For You also ranks your Reddit Home: Reddit's recommendations, under your For You choices",
                s.forYouFeed && s.blendHome
            ) { v in
                app.settings.setBlendHome(v)
                if v { app.settings.setForYouFeed(true) }
            }
            if s.forYouFeed && s.blendHome {
                let labels = ["Mostly Ilay", "Balanced", "Mostly Reddit"]
                let hints = [
                    "Reddit's picks get a small nudge, no reserved spots",
                    "About 1 post in 5 is from your Reddit Home",
                    "About 1 in 3 from your Reddit Home, and they count more",
                ]
                b.picker(
                    "Reddit ↔ Ilay", hints[s.blendReddit], value: s.blendReddit,
                    options: (0...2).map { PickOption(value: $0, label: labels[$0], subtitle: hints[$0]) },
                    set: ctrl.setBlendReddit
                )
            }
        }
        b.toggle("Floating filter chips", "On Home, show the chips under the top bar when you scroll back up", s.floatingChips, set: ctrl.setFloatingChips)
        b.divider()
        b.picker(
            "Keep feed for", "Home / For You, then a new feed (pull down to refresh anytime)", value: s.feedKeepMinutes,
            options: [10, 30, 60, 180].map { PickOption(value: $0, label: keepLabel($0)) }, set: ctrl.setFeedKeepMinutes
        )
        b.toggle("Hide read posts", "Skip posts you've already read when your front page and custom feeds load or refresh", s.hideReadPosts, set: ctrl.setHideReadPosts)
        if s.hideReadPosts {
            b.toggle("Also in subreddits", "Hide read posts when browsing a single subreddit too", s.hideReadInSubreddits, set: ctrl.setHideReadInSubreddits)
        }
        b.toggle(
            "Mark read as you scroll", s.trackHistory ? "A post you scroll past counts as read" : "Needs history tracking turned on",
            s.markReadOnScroll, enabled: s.trackHistory, set: ctrl.setMarkReadOnScroll
        )
        b.link("Content filters", "Hide posts by keyword, domain, flair or subreddit", .contentFilters)
        b.picker(
            "Hide posts for", "Posts you hide stay out of every feed for this long", value: s.hiddenPostDays,
            options: [1, 3, 7, 30, 90].map { PickOption(value: $0, label: dayLabel($0)) }, set: ctrl.setHiddenPostDays
        )
        b.tile(
            "Hidden subreddits",
            "Hidden from your front page for 7 days" + (hiddenSubs == 0 ? " · none now" : " · \(hiddenSubs) now"),
            action: showHiddenSubsSheet
        )
    }

    // MARK: - Appearance

    private func appearance(_ b: RowBuilder) {
        b.section("Appearance")
        b.picker("Theme", value: s.themeMode, options: ThemeMode.allCases.map { PickOption(value: $0, label: themeLabel($0)) }, set: ctrl.setThemeMode)
        b.custom("accent", title: "Accent color", search: "Accent color") { AccentPicker(selected: s.seedColor) }
        b.custom("appIcon", title: "App icon", search: "App icon home screen colour") { AppIconRow(current: AppIcon.parse(s.appIcon)) }
        b.custom("fontSize", title: "Font size", search: "Font size text \(Int((s.textScale * 100).rounded()))% of normal") {
            FontSizeRow(scale: s.textScale)
        }
        b.divider()
        b.picker(
            "Top bar", value: s.topBarMode,
            options: TopBarMode.allCases.map { PickOption(value: $0, label: $0.label, subtitle: $0.description) }, set: ctrl.setTopBarMode
        )
        if s.topBarMode == .full {
            b.toggle("New post in the top bar", "A New post button beside your profile picture", s.fullBarNewPost, set: ctrl.setFullBarNewPost)
        }
        b.picker("Floating button on Home", value: s.homeFab, options: HomeFab.allCases.map { PickOption(value: $0, label: $0.label) }, set: ctrl.setHomeFab)
        b.picker(
            "Navigation", value: min(max(s.navStyle, 0), 2),
            options: navStyles.indices.map { PickOption(value: $0, label: navStyles[$0].0, subtitle: navStyles[$0].1) }, set: ctrl.setNavStyle
        )
    }

    // MARK: - Posts & comments

    private func postsAndComments(_ b: RowBuilder) {
        b.section("Posts & comments")
        b.picker("Comment style", value: s.commentStyle, options: CommentStyle.allCases.map { PickOption(value: $0, label: $0.label) }, set: ctrl.setCommentStyle)
        b.picker(
            "Default comment sort", value: s.defaultCommentSort,
            options: COMMENT_SORTS.map { PickOption(value: $0.id, label: $0.label) }, set: ctrl.setDefaultCommentSort
        )
        b.picker("Thread buttons position", value: s.threadFabPosition, options: ThreadFabPosition.allCases.map { PickOption(value: $0, label: $0.label) }, set: ctrl.setThreadFabPosition)
        b.toggle("Next comment button", "Jump to the next top-level comment in threads (long-press: the previous one)", s.threadJumpNext, set: ctrl.setThreadJumpNext)
        b.toggle("OP's comments button", "Jump between comments by the original poster in threads", s.threadJumpOp, set: ctrl.setThreadJumpOp)
        b.toggle("Your comments button", "Jump between your own comments in threads", s.threadJumpMine, set: ctrl.setThreadJumpMine)
        b.toggle("Tap a comment to collapse it", "Otherwise long-press. Comment text can't be selected while this is on", s.tapToCollapse, set: ctrl.setTapToCollapse)
        b.toggle("Collapse only the replies", "Collapsing a comment keeps its own text and hides its replies", s.collapseRepliesOnly, set: ctrl.setCollapseRepliesOnly)
        b.toggle("Profile pictures in comments", "With the website sign-in: one more request per thread brings its commenters' pictures", s.commentAvatars, set: ctrl.setCommentAvatars)
        b.toggle("Mark comments you voted on", "A soft glow in the vote's color on comments you upvoted or downvoted", s.voteEdge, set: ctrl.setVoteEdge)
        let off = Int.min
        let collapseChoices = [off, 1, 0, -5, -10]
        b.picker(
            "Collapse low-scoring comments", value: s.collapseBelowScore ?? off,
            options: collapseChoices.map { PickOption(value: $0, label: $0 == off ? "Off" : "Below \($0) points") }
        ) { v in
            app.settings.setCollapseBelowScore(v == off ? nil : v)
        }
        b.toggle("Open threads collapsed", "Top-level comments show without their replies, each with a \"Show replies\" button", s.collapseTopLevel, set: ctrl.setCollapseTopLevel)
        b.toggle("Swipe actions", "Swipe posts and comments sideways", s.swipeActions, set: ctrl.setSwipeActions)
        if s.swipeActions {
            let subtitle = "Posts: \(s.swipePostStart.label) / \(s.swipePostEnd.label) · Comments: \(s.swipeCommentStart.label) / \(s.swipeCommentEnd.label)"
            b.custom("customizeSwipes", title: "Customize swipes", search: "Customize swipes \(subtitle)") {
                NavigationLink {
                    SwipeSettingsPage()
                } label: {
                    SettingLabel(title: "Customize swipes", subtitle: subtitle)
                }
            }
        }
        b.toggle("Open links inside the app", "Web links open in an in-app browser tab instead of your browser app", s.inAppBrowser, set: ctrl.setInAppBrowser)
    }

    // MARK: - Media

    private func media(_ b: RowBuilder) {
        b.section("Media")
        b.toggle("Autoplay videos", s.autoplaySound ? "Play videos as you scroll the feed" : "Play videos muted as you scroll the feed", s.autoplayMedia, set: ctrl.setAutoplayMedia)
        if s.autoplayMedia {
            b.toggle("Autoplay with sound", "Feed videos start with sound; tap the speaker to mute one", s.autoplaySound, set: ctrl.setAutoplaySound)
        }
        b.toggle("Open videos muted", "Full-screen videos start muted; tap the speaker for sound", s.viewerMuted, set: ctrl.setViewerMuted)
        b.toggle("Gallery carousel in feeds", "Galleries show a big image with the next ones beside it. Off: one image at a time", s.feedGalleryCarousel, set: ctrl.setFeedGalleryCarousel)
        b.toggle("Blur NSFW media", "Tap to reveal blurred images", s.blurNsfw, set: ctrl.setBlurNsfw)
        // Content filters' switch, here too: beside the blur is where people look for it (#94).
        b.toggle("Hide NSFW posts", "Remove them from feeds and search instead of blurring", app.contentFilters.value.hideNsfw, set: app.contentFilters.setHideNsfw)
        b.toggle("Data-saver thumbnails", "Load smaller preview images in feeds (faster, less data)", s.midResThumbnails, set: ctrl.setMidResThumbnails)
    }

    // MARK: - Notifications

    private func notifications(_ b: RowBuilder) {
        b.section("Notifications")
        let prompts = prompts
        b.toggle(
            "Inbox notifications",
            "Check for replies & messages in the background (~every 15 min) and notify you. No Firebase — polling only.",
            s.notifyInbox
        ) { v in
            Task {
                await toggleInboxNotifications(v)
                prompts.refresh += 1
            }
        }
        b.link("Notification activity", "What Ilay notified you about, what it couldn't, and why · Check now", .notificationActivity)
    }

    // MARK: - Translation

    private func translation(_ b: RowBuilder) {
        b.section("Translation")
        let languages = translateLanguages.filter { $0 != Translate.primary }
            .map { PickOption(value: $0, label: Translate.languageName($0)) }
            .sorted { $0.label < $1.label }
        b.picker(
            "Second language",
            s.translateSecondLanguage.isEmpty ? "Off: Translate offers your phone's language only" : "Translate also offers \(Translate.languageName(s.translateSecondLanguage))",
            value: s.translateSecondLanguage,
            options: [PickOption(value: "", label: "Off")] + languages,
            set: ctrl.setTranslateSecondLanguage
        )
        b.toggle("Auto-translate posts", "Posts in neither language open translated into your phone's", s.autoTranslate, set: ctrl.setAutoTranslate)
        b.picker(
            "Translation service", "For languages your phone can't translate", value: s.translateService,
            options: [
                PickOption(value: "openai", label: "OpenAI", subtitle: "Your AI summaries key; each translation costs a little"),
                PickOption(value: "azure", label: "Azure Translator", subtitle: "Your Azure key; 2 million characters a month free"),
            ],
            set: ctrl.setTranslateService
        )
        if s.translateService == "azure" {
            let prompts = prompts
            b.tile("Azure Translator key", secure.azureKey ? "Key set — tap to change or remove" : "Add your Translator resource's key") {
                prompts.ask(TextPrompt(
                    title: "Azure Translator key",
                    note: "Stored securely on this device (never in backups). Translations send the text to Microsoft.",
                    secret: true,
                    removable: secure.azureKey
                ) { r in
                    Task {
                        switch r {
                        case .remove: await app.secureStore.saveAzureTranslatorKey(nil)
                        case let .save(text): if !text.isBlank { await app.secureStore.saveAzureTranslatorKey(text.trimmed) }
                        }
                        prompts.refresh += 1
                    }
                })
            }
            b.tile("Azure region", s.azureRegion.nilIfEmpty ?? "Global") {
                prompts.ask(TextPrompt(
                    title: "Azure region",
                    hint: "e.g. westeurope",
                    note: "Your Translator resource's location. Leave empty for a global resource."
                ) { r in
                    if case let .save(text) = r { app.settings.setAzureRegion(text.trimmed) }
                }, initial: s.azureRegion)
            }
        }
    }

    // MARK: - AI summaries

    private func aiSummaries(_ b: RowBuilder) {
        b.section("AI summaries")
        let prompts = prompts
        // With a custom endpoint the key is that provider's (Groq, OpenRouter, a LiteLLM key…).
        let keyLabel = s.aiUseCustomUrl ? "API key" : "OpenAI API key"
        b.tile(keyLabel, secure.aiKey ? "Key set — tap to change or remove" : "Add a key to enable thread summaries") {
            prompts.ask(TextPrompt(
                title: keyLabel,
                hint: s.aiUseCustomUrl ? "Your provider's API key" : "sk-…",
                note: "Stored securely on this device (never in backups). Summaries send the thread text to your AI endpoint.",
                secret: true,
                removable: secure.aiKey
            ) { r in
                Task {
                    switch r {
                    case .remove: await app.secureStore.saveOpenaiKey(nil)
                    case let .save(text): if !text.isBlank { await app.secureStore.saveOpenaiKey(text.trimmed) }
                    }
                    prompts.refresh += 1
                }
            })
        }
        // The presets are OpenAI's; any other provider's model is typed in.
        let current = s.aiModel
        let presets = (aiModels + (aiModels.contains(current) ? [] : [current])).map { PickOption(value: $0, label: $0) }
        b.picker(
            "Model", value: current,
            options: presets + [PickOption(value: customModel, label: "Custom model…", subtitle: "Type your provider's model ID")],
            enabled: secure.aiKey
        ) { picked in
            if picked != customModel {
                app.settings.setAiModel(picked)
                return
            }
            prompts.ask(TextPrompt(
                title: "Model ID",
                hint: "e.g. llama-3.3-70b-versatile",
                note: "Exactly as your provider names it."
            ) { r in
                if case let .save(text) = r, !text.isBlank { app.settings.setAiModel(text.trimmed) }
            }, initial: current)
        }
        b.picker(
            "Summary style", value: min(max(s.aiSummaryStyle, 0), summaryStyleLabels.count - 1),
            options: summaryStyleLabels.indices.map { PickOption(value: $0, label: summaryStyleLabels[$0]) },
            enabled: secure.aiKey, set: ctrl.setAiSummaryStyle
        )
        // A language chosen on another build stays selectable.
        let languages = summaryLanguages.contains { $0.0 == s.aiSummaryLanguage } ? summaryLanguages : summaryLanguages + [(s.aiSummaryLanguage, s.aiSummaryLanguage)]
        b.picker(
            "Summary language", value: s.aiSummaryLanguage,
            options: languages.map { PickOption(value: $0.0, label: $0.1) },
            enabled: secure.aiKey, set: ctrl.setAiSummaryLanguage
        )
        func tokens(_ chars: Int) -> Int { Int((Double(chars) / 4000).rounded()) }
        b.picker(
            "Max thread size", "~\(tokens(s.aiMaxChars))k tokens", value: s.aiMaxChars,
            options: [50_000, 100_000, 200_000, 400_000].map { PickOption(value: $0, label: "\($0 / 1000)k characters", subtitle: "~\(tokens($0))k tokens") },
            enabled: secure.aiKey, set: ctrl.setAiMaxChars
        )
        b.toggle("Custom API base URL", "Advanced — use an OpenAI-compatible endpoint (e.g. Groq, OpenRouter, LiteLLM)", s.aiUseCustomUrl, set: ctrl.setAiUseCustomUrl)
        if s.aiUseCustomUrl {
            b.tile("API base URL", s.aiBaseUrl) {
                prompts.ask(TextPrompt(
                    title: "API base URL",
                    hint: "https://api.groq.com/openai/v1",
                    note: "With or without /v1, as your provider shows it. Then set the Model to one of theirs.",
                    keyboard: .URL
                ) { r in
                    if case let .save(text) = r, !text.isBlank { app.settings.setAiBaseUrl(text.trimmed) }
                }, initial: s.aiBaseUrl)
            }
        }
    }

    // MARK: - Data & storage

    private func dataAndStorage(_ b: RowBuilder) {
        b.section("Data & storage")
        b.toggle("Track history", s.dimRead ? "Remember and dim viewed posts (local only)" : "Remember viewed posts (local only)", s.trackHistory, set: ctrl.setTrackHistory)
        if s.trackHistory {
            // Like Sync for Reddit's: the subreddits you open most stay on top (#92).
            b.picker(
                "Recently visited order", value: s.recentSubsByVisits,
                options: [PickOption(value: false, label: "Most recent first"), PickOption(value: true, label: "Most visited first", subtitle: "The subreddits you open most stay on top")],
                set: ctrl.setRecentSubsByVisits
            )
            b.picker(
                "Dim read posts", s.readDim == .text ? "Titles and text fade, images stay bright" : s.readDim == .off ? "Read posts look like new ones" : nil, value: s.readDim,
                options: [
                    PickOption(value: ReadDim.card, label: "Whole card"), PickOption(value: ReadDim.text, label: "Text only", subtitle: "Images and videos stay bright"),
                    PickOption(value: ReadDim.off, label: "Off", subtitle: "History is still kept"),
                ],
                set: ctrl.setReadDim
            )
        }
        b.toggle(
            "Recently visited", "List the subreddits you opened last on Explore and in the side bar",
            s.showRecentlyVisited, set: ctrl.setShowRecentlyVisited
        )
        b.toggle("Offline cache", "Show the last loaded content when offline", s.offlineCache, set: ctrl.setOfflineCache)
        b.toggle("Cache subscriptions", "Keep your subreddit list in memory to speed up \"For You\"", s.subsCacheEnabled, set: ctrl.setSubsCacheEnabled)
        b.picker(
            "Subscriptions cache time", value: s.subsCacheMinutes,
            options: [5, 10, 30, 60].map { PickOption(value: $0, label: "\($0) minutes") }, enabled: s.subsCacheEnabled, set: ctrl.setSubsCacheMinutes
        )
        b.picker(
            "Image cache size", "After restarting Ilay", value: s.imageCacheMb,
            options: [256, 512, 1024, 2048].map { PickOption(value: $0, label: "\($0) MB") }, set: ctrl.setImageCacheMb
        )
        b.custom("clearCache", title: "Clear cache", search: "Clear cache saved pages, images and videos") { ClearCacheRow() }
        let prompts = prompts
        b.tile("Back up data", "Export settings, For You model & history (no login/keys)") {
            prompts.exporting = BackupDocument(text: Backup.export(app.prefs))
        }
        b.tile("Restore data", "Import a backup file") { prompts.importing = true }
    }

    // MARK: - Account & keys

    private func account(_ b: RowBuilder) {
        b.section("Account & keys")
        let web = secure.web
        b.tile("Login method", web ? "Website session (no API key) — unofficial" : "Reddit API key (recommended)") {
            Task { await showLoginMethodInfo(web) }
        }
        if web {
            b.link(
                "Reddit account settings", "Reddit's own settings: Home recommendations, notifications, muted communities",
                .redditWeb(url: RedditWeb.settings, title: "Reddit settings")
            )
        }
        b.tile("Reddit API credentials", "Re-enter your Client ID / Redirect URI") {
            Task {
                if await confirmDialog(
                    "Re-enter credentials?",
                    "You will be logged out and returned to the login screen. Your saved Client ID and Redirect URI will be pre-filled.",
                    "Continue"
                ) { await app.session.logout() }
            }
        }
        let prompts = prompts
        let giphySet = secure.giphyKey
        b.tile("Giphy API key", giphySet ? "Key set — tap to change or remove" : "Optional — enables the GIF picker") {
            prompts.ask(TextPrompt(
                title: "Giphy API key",
                note: "Stored securely on this device (never in backups).",
                secret: true,
                removable: giphySet
            ) { r in
                Task {
                    switch r {
                    case .remove: await app.secureStore.saveGiphyKey(nil)
                    case let .save(text): if !text.isBlank { await app.secureStore.saveGiphyKey(text.trimmed) }
                    }
                    prompts.refresh += 1
                }
            })
        }
        b.tile("Clear all data", "Wipes credentials, tokens and login", titleColor: .red) {
            Task {
                if await confirmDialog(
                    "Clear all data?",
                    "This wipes your API credentials, tokens and session from this device. You will need to set everything up again.",
                    "Clear",
                    destructive: true
                ) {
                    await app.secureStore.clearAll()
                    await app.client.clearCache()
                    await app.session.logout()
                }
            }
        }
    }

    // MARK: - Power-user

    private func powerUser(_ b: RowBuilder) {
        b.section("Power-user features")
        b.toggle("Show API usage instead of search", "Replace the search bar on the Posts screen with your live Reddit API rate-limit usage", s.showApiUsage, set: ctrl.setShowApiUsage)
        b.custom("rateLimit", title: "API usage", search: "API usage") { RateLimitTile() }
    }

    // MARK: - About

    private func about(_ b: RowBuilder) {
        b.section("About")
        b.link("What's new", "Ilay \(RedditConstants.appVersion) · what changed in each release", .whatsNew)
        b.toggle("Check for updates", "Check GitHub releases on launch", s.checkUpdates, set: ctrl.setCheckUpdates)
        b.tile("Check now") { Task { await checkUpdatesNow() } }
        b.toggle("Send anonymous usage stats", "App starts, which feed you use, whether Reddit Home loads. Never your account or what you read", s.analytics, set: ctrl.setAnalytics)
        b.info("Open reddit links in Ilay", "Use Share on a reddit link in another app and pick Ilay: it opens the link, or summarizes a post. In Safari, turn on the Ilay extension (Settings → Apps → Safari → Extensions) and allow it on all websites: Reddit links then open here.")
        b.toggle("Safari extension: ask which app", "On a Reddit link, choose Ilay or the Reddit app each time", s.safariAsk, set: ctrl.setSafariAsk)
        b.link("Content & conduct policy", nil, .policy)
        b.tile("Open-source licenses", "swift-markdown, swift-cmark") {
            Task {
                await infoDialog(
                    "Licenses",
                    "swift-markdown\nCopyright Apple Inc. and the Swift project authors. Apache License 2.0.\n\n"
                        + "swift-cmark (cmark-gfm)\nCopyright John MacFarlane, GitHub. BSD 2-Clause License."
                )
            }
        }
        b.custom("version", title: "Version", search: "Version \(RedditConstants.appVersion)") {
            LabeledContent("Version", value: RedditConstants.appVersion)
        }
    }
}

// MARK: - Rows

/// Adds rows to the list, each from what it shows and what it does.
@MainActor
private final class RowBuilder {
    private(set) var rows: [SettingEntry] = []
    private var section = ""
    private var group = 0

    func section(_ title: String) {
        section = title
        group = 0
    }

    func divider() { group += 1 }

    func custom<V: View>(_ id: String, title: String, search: String?, @ViewBuilder content: () -> V) {
        rows.append(SettingEntry(id: id, section: section, group: group, title: title, search: search, content: AnyView(content())))
    }

    /// A row that does something when tapped.
    func tile(_ title: String, _ subtitle: String? = nil, titleColor: Color? = nil, action: @escaping () -> Void) {
        custom("t:\(title)", title: title, search: "\(title) \(subtitle ?? "")") {
            Button(action: action) {
                SettingLabel(title: title, subtitle: subtitle, titleColor: titleColor)
            }
        }
    }

    /// A row that only informs.
    func info(_ title: String, _ subtitle: String) {
        custom("i:\(title)", title: title, search: "\(title) \(subtitle)") {
            SettingLabel(title: title, subtitle: subtitle)
        }
    }

    /// A row that opens a screen.
    func link(_ title: String, _ subtitle: String?, _ route: Route) {
        custom("l:\(title)", title: title, search: "\(title) \(subtitle ?? "")") {
            NavigationLink(value: route) {
                SettingLabel(title: title, subtitle: subtitle)
            }
        }
    }

    func toggle(_ title: String, _ subtitle: String?, _ isOn: Bool, enabled: Bool = true, accent: Color? = nil, set: @escaping (Bool) -> Void) {
        custom("s:\(title)", title: title, search: "\(title) \(subtitle ?? "")") {
            Toggle(isOn: Binding(get: { isOn }, set: set)) {
                SettingLabel(title: title, subtitle: subtitle, titleColor: accent)
            }
            .tint(accent ?? IlayTheme.accent)
            .disabled(!enabled)
        }
    }

    /// A choice on its own page; the current one shows at the row's end.
    func picker<T: Hashable>(_ title: String, _ subtitle: String? = nil, value: T, options: [PickOption<T>], enabled: Bool = true, set: @escaping (T) -> Void) {
        let current = options.first { $0.value == value }?.label ?? ""
        custom("p:\(title)", title: title, search: "\(title) \(subtitle ?? "") \(current)") {
            Picker(selection: Binding(get: { value }, set: set)) {
                ForEach(options, id: \.value) { option in
                    OptionLabel(option: option).tag(option.value)
                }
            } label: {
                SettingLabel(title: title, subtitle: subtitle)
            } currentValueLabel: {
                // Just its name: the row has no room for an option's explanation.
                Text(current)
            }
            .pickerStyle(.navigationLink)
            .disabled(!enabled)
        }
    }
}

private struct OptionLabel<T: Hashable>: View {
    let option: PickOption<T>

    var body: some View {
        if let icon = option.icon {
            Label(option.label, systemImage: icon)
        } else if let subtitle = option.subtitle {
            VStack(alignment: .leading, spacing: 2) {
                Text(option.label)
                Text(subtitle).font(.footnote).foregroundStyle(.secondary)
            }
        } else {
            Text(option.label)
        }
    }
}

/// Amber for Reddit Home's caution (readable on light and dark surfaces).
let homeAmber = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark
        ? UIColor(red: 1, green: 0xC9 / 255, blue: 0x4D / 255, alpha: 1)
        : UIColor(red: 0x9A / 255, green: 0x67 / 255, blue: 0, alpha: 1)
})

private struct AccentPicker: View {
    let selected: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Accent color")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 40), spacing: 10)], spacing: 10) {
                ForEach(accentSwatches, id: \.argb) { swatch in
                    Button {
                        app.settings.setSeedColor(swatch.argb)
                    } label: {
                        Circle()
                            .fill(Color(argb: swatch.argb))
                            .frame(width: 40, height: 40)
                            .overlay {
                                if selected == swatch.argb {
                                    Image(systemName: "checkmark").fontWeight(.bold).foregroundStyle(.white)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(swatch.name)
                    .accessibilityAddTraits(selected == swatch.argb ? .isSelected : [])
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct AppIconRow: View {
    let current: AppIcon

    var body: some View {
        Picker(selection: Binding(get: { current }, set: { picked in
            if picked == current { return }
            app.settings.setAppIcon(picked.key)
            // iOS confirms the change with its own alert.
            AppIcon.apply(picked)
        })) {
            ForEach(AppIcon.allCases) { icon in
                Label {
                    Text(icon.label)
                } icon: {
                    AppIconPreview(icon: icon, size: 40)
                }
                .tag(icon)
            }
        } label: {
            Label {
                Text("App icon")
            } icon: {
                AppIconPreview(icon: current, size: 24)
            }
        } currentValueLabel: {
            Text(current.label)
        }
        .pickerStyle(.navigationLink)
    }
}

private struct FontSizeRow: View {
    let scale: Double
    /// While dragging: only the preview follows, so the list doesn't move under the finger.
    @State private var dragging: Double?

    var body: some View {
        let shown = dragging ?? scale
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent("Font size", value: "\(Int((shown * 100).rounded()))% of normal")
            Slider(
                value: Binding(get: { shown }, set: { dragging = ($0 * 20).rounded() / 20 }),
                in: 0.8...1.4,
                step: 0.05,
                onEditingChanged: { editing in
                    if !editing, let dragging {
                        app.settings.setTextScale(dragging)
                        self.dragging = nil
                    }
                },
                minimumValueLabel: Text("A").font(.system(size: 13)),
                maximumValueLabel: Text("A").font(.system(size: 22)),
                label: { Text("Font size") }
            )
            Text("The quick brown fox jumps over the lazy dog.")
                .font(.subheadline)
                .dynamicTypeSize(IlayTheme.typeSize(shown).map { $0...$0 } ?? (.xSmall ... .accessibility5))
        }
        .padding(.vertical, 4)
    }
}

/// For You's Familiar ↔ Discover mix: how often posts from communities you don't follow come up.
private struct ForYouMixSlider: View {
    let value: Int
    @State private var dragging: Double?

    var body: some View {
        let shown = dragging ?? Double(value)
        VStack(alignment: .leading, spacing: 6) {
            SettingLabel(title: "For You mix", subtitle: {
                switch Int(shown.rounded()) {
                case -2: return "Almost only your communities"
                case -1: return "Mostly your communities"
                case 1: return "More from communities you don't follow"
                case 2: return "Lots of new communities"
                default: return "Balanced: adapts to what you open (next refresh)"
                }
            }())
            // Filled from the centre: 0 is Balanced, so the fill shows which way and how far the mix leans.
            Slider(
                value: Binding(get: { shown }, set: { dragging = $0 }),
                in: -2...2,
                step: 1,
                neutralValue: 0,
                label: { Text("For You mix") },
                onEditingChanged: { editing in
                    if !editing, let dragging {
                        app.settings.setForYouDiscovery(Int(dragging.rounded()))
                        self.dragging = nil
                    }
                }
            )
            HStack {
                Text("Familiar")
                Spacer()
                Text("Discover")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct ClearCacheRow: View {
    // What Ilay keeps in its cache folder: saved pages, images, videos.
    @State private var bytes: Int?

    private static func cacheSize() async -> Int {
        await Task.detached(priority: .utility) {
            let walker = FileManager.default.enumerator(at: FileLocations.caches, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
            var total = 0
            while let file = walker?.nextObject() as? URL {
                let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                if values?.isRegularFile == true { total += values?.fileSize ?? 0 }
            }
            return total
        }.value
    }

    var body: some View {
        Button {
            Task {
                await app.client.clearCache()
                ImageLoader.shared.clearAll()
                URLCache.shared.removeAllCachedResponses()
                bytes = await Self.cacheSize()
                app.navigator.showSnackbar("Cache cleared")
            }
        } label: {
            SettingLabel(title: "Clear cache", subtitle: bytes.map { "\($0 >> 20) MB of saved pages, images and videos" })
        }
        .task { bytes = await Self.cacheSize() }
    }
}

private struct RateLimitTile: View {
    var body: some View {
        SettingLabel(
            title: "API usage",
            subtitle: app.rateLimit.map { "\($0.used)/\($0.total) used this window · resets in \($0.secondsLeft())s" }
                ?? "Reddit allows roughly 100 requests/minute. No data yet."
        )
    }
}

/// Picks what each swipe direction does, for posts and for comments.
private struct SwipeSettingsPage: View {
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        let s = app.settings.value
        // "Right"/"left" as the user sees them; mirrored in RTL languages.
        let rtl = layoutDirection == .rightToLeft
        let startLabel = rtl ? "Swipe left" : "Swipe right"
        let endLabel = rtl ? "Swipe right" : "Swipe left"
        List {
            Section("Posts") {
                row(startLabel, "swipePostStart", s.swipePostStart, forPosts: true)
                row(endLabel, "swipePostEnd", s.swipePostEnd, forPosts: true)
            }
            Section("Comments") {
                row(startLabel, "swipeCommentStart", s.swipeCommentStart, forPosts: false)
                row(endLabel, "swipeCommentEnd", s.swipeCommentEnd, forPosts: false)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Customize swipes")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ label: String, _ key: String, _ value: SwipeAction, forPosts: Bool) -> some View {
        let options = SwipeAction.allCases.filter {
            forPosts ? $0 != .collapse : $0 != .hide && $0 != .dismiss && $0 != .hideSub
        }
        return Picker(label, selection: Binding(get: { value }, set: { app.settings.setSwipeAction(key, $0) })) {
            ForEach(options, id: \.self) { action in
                Label(action.label, systemImage: action.icon).tag(action)
            }
        }
        .pickerStyle(.navigationLink)
    }
}

// MARK: - The screen

/// Settings: the categories, or the one `section` (a page of its own).
struct SettingsScreen: View {
    var section: String? = nil

    @State private var query = ""
    @State private var prompts = SettingsPrompts()
    @State private var secure = SecureFlags()

    var body: some View {
        if section == nil {
            list.searchable(text: $query, prompt: "Search settings")
        } else {
            list
        }
    }

    private var list: some View {
        let catalog = SettingsCatalog(s: app.settings.value, secure: secure, hiddenSubs: app.hiddenHomeSubs.ids.count, prompts: prompts)
        return List {
            if !query.trimmed.isEmpty {
                let found = catalog.matching(query)
                if found.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .listRowBackground(Color.clear)
                }
                ForEach(found.map(\.section).uniqued(), id: \.self) { title in
                    Section(title) {
                        ForEach(found.filter { $0.section == title }) { $0.content }
                    }
                }
            } else if let section {
                let rows = catalog.rows(section: section)
                ForEach(rows.map(\.group).uniqued(), id: \.self) { group in
                    Section {
                        ForEach(rows.filter { $0.group == group }) { $0.content }
                    }
                }
            } else {
                ForEach(settingsCategories.indices, id: \.self) { i in
                    Section {
                        ForEach(settingsCategories[i], id: \.title) { category in
                            NavigationLink(value: Route.settingsSection(title: category.title)) {
                                Label {
                                    SettingLabel(title: category.title, subtitle: category.subtitle)
                                } icon: {
                                    Image(systemName: category.icon)
                                        .font(.footnote)
                                        .foregroundStyle(.white)
                                        .frame(width: 29, height: 29)
                                        .background(category.color, in: .rect(cornerRadius: 7, style: .continuous))
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(section ?? "Settings")
        // Secure-storage state, re-read after edits and account changes.
        .task(id: "\(prompts.refresh)|\(app.session.session?.identity ?? "")") {
            let store = app.secureStore
            secure = SecureFlags(
                aiKey: !(await store.openaiKey() ?? "").isEmpty,
                giphyKey: !(await store.giphyKey() ?? "").isEmpty,
                azureKey: !(await store.azureTranslatorKey() ?? "").isEmpty,
                web: await store.authMode() == "web"
            )
        }
        .alert(prompts.text?.title ?? "", isPresented: Binding(get: { prompts.text != nil }, set: { if !$0 { prompts.text = nil } }), presenting: prompts.text) { prompt in
            if prompt.secret {
                SecureField(prompt.hint, text: $prompts.input)
            } else {
                TextField(prompt.hint, text: $prompts.input)
                    .keyboardType(prompt.keyboard)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            if prompt.removable {
                Button("Remove", role: .destructive) { prompt.onDone(.remove) }
            }
            Button("Cancel", role: .cancel) {}
            Button("Save") { prompt.onDone(.save(prompts.input)) }
        } message: { prompt in
            if let note = prompt.note { Text(note) }
        }
        .fileExporter(
            isPresented: Binding(get: { prompts.exporting != nil }, set: { if !$0 { prompts.exporting = nil } }),
            document: prompts.exporting,
            contentType: .json,
            defaultFilename: "ilay-backup"
        ) { result in
            if case let .failure(error) = result, (error as? CocoaError)?.code != .userCancelled {
                app.navigator.showSnackbar("Backup failed: \(error.localizedDescription)")
            }
        }
        .fileImporter(isPresented: $prompts.importing, allowedContentTypes: [.json, .plainText, .data]) { result in
            Task { await restoreData(result) }
        }
    }
}

// MARK: - Actions

private func themeLabel(_ m: ThemeMode) -> String {
    switch m {
    case .system: return "Follow system"
    case .light: return "Light"
    case .dark: return "Dark"
    }
}

/// "Keep feed for" choices: how long Home / For You keep their posts before returning to them loads new ones.
private func keepLabel(_ minutes: Int) -> String {
    minutes < 60 ? "\(minutes) minutes" : minutes == 60 ? "1 hour" : "\(minutes / 60) hours"
}

private func dayLabel(_ days: Int) -> String { days == 1 ? "1 day" : "\(days) days" }

/// What Reddit Home is (unofficial, can break) before turning it on. True to turn it on.
@MainActor func confirmRedditHome() async -> Bool {
    await confirmDialog(
        "About Reddit Home",
        "Reddit Home shows your real reddit.com Home feed. Ilay loads reddit.com in a hidden browser with your website sign-in and reads which posts it shows.\n\n"
            + "• Unofficial: Reddit's terms don't allow automated use of its site, so use it at your own discretion.\n\n"
            + "• It can stop working when Reddit changes its site. Ilay then shows For You.\n\n"
            + "• Website sign-in only; it talks only to reddit.com.",
        "Turn on"
    )
}

@MainActor private func showLoginMethodInfo(_ isWeb: Bool) async {
    await infoDialog(
        "Login method",
        isWeb
            ? "You're signed in with a website session (no API key).\n\n"
                + "This isn't Reddit's official API. It can stop working if Reddit changes their site, and Reddit may consider it against their usage policy and restrict or ban accounts that use it. Use at your own risk.\n\n"
                + "To switch to the official API key method, log out and choose \"Connect Reddit account\" on the login screen."
            : "You're signed in with Reddit's official API using your own API key — the recommended, supported method.\n\n"
                + "If you can no longer create an API key, you can log out and choose \"Sign in via website\" on the login screen, but that unofficial method carries account risk."
    )
}

@MainActor private func toggleInboxNotifications(_ enable: Bool) async {
    let nav = app.navigator
    if !enable {
        app.settings.setNotifyInbox(false)
        app.inbox.cancelPolling()
        return
    }
    if await !app.inbox.requestPermission() {
        nav.showSnackbar("Notification permission denied. Enable it in system settings to get inbox alerts.")
        return
    }
    app.settings.setNotifyInbox(true)
    // Prime the "seen" set with current unread so turning this on doesn't fire a
    // notification for every pre-existing item, then start the periodic poll.
    _ = await app.inbox.pollInbox(notify: false)
    app.inbox.registerPolling()
    nav.showSnackbar("Inbox notifications on. Reddit is checked about every 15 minutes.")
}

@MainActor private func checkUpdatesNow() async {
    let nav = app.navigator
    nav.showSnackbar("Checking…")
    guard let info = await UpdateChecker.check() else {
        nav.showSnackbar("You're on the latest version (\(RedditConstants.appVersion)).")
        return
    }
    let download = await confirmDialog("Update available — v\(info.version)", "A newer version is available on GitHub.", "Download", cancel: "Later")
    // The release page: its .apk assets are Android's.
    if download { nav.openInBrowser(info.url) }
}

@MainActor func restoreData(_ result: Result<URL, Error>) async {
    do {
        let file = try result.get()
        let scoped = file.startAccessingSecurityScopedResource()
        defer { if scoped { file.stopAccessingSecurityScopedResource() } }
        let n = try Backup.import(app.prefs, String(decoding: try Data(contentsOf: file), as: UTF8.self))
        reloadLocalData()
        await infoDialog("Restore complete", "Imported \(n) settings. Restart Ilay to apply everything.", close: "OK")
    } catch {
        if (error as? CocoaError)?.code != .userCancelled {
            app.navigator.showSnackbar("Restore failed: \(error.localizedDescription)")
        }
    }
}

/// Re-reads everything a restore may have changed: settings, every per-account
/// store, and the session. (`AppContainer.start` must not run twice, so this
/// reloads the stores directly.)
@MainActor func reloadLocalData() {
    app.settings.reload()
    // A restored icon choice only takes effect once it's switched. Only when it
    // differs: iOS shows an alert for every switch.
    let icon = AppIcon.parse(app.settings.value.appIcon)
    if UIApplication.shared.alternateIconName != (icon == .violet ? nil : "AppIcon-\(icon.key)") { AppIcon.apply(icon) }
    let user = app.session.username
    let stores: [UserScoped] = [
        app.postOverrides, app.commentVotes, app.hiddenPosts, app.dismissedPosts, app.hiddenHomeSubs,
        app.summaries, app.history, app.recentSubreddits, app.threadVisits, app.contentFilters, app.offline, app.feed, app.forYou, app.inbox, app.redditNotifications,
    ]
    stores.forEach { $0.onUserChanged(user) }
    app.session.reload()
}
