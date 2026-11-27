import Foundation

// Left out of [Settings] as Android / Material only (PORTING.md), their keys
// stay reserved and untouched in the prefs, never reuse them: `useDynamicColor`,
// `appFont`, `jakartaFont`, `volumeKeyNavigation`, `redditAppNotifications`.

/// Order matters: persisted by index (`themeMode`), same as Flutter's ThemeMode.
/// Feed autoplay: off, only on an unmetered network (Wi-Fi), or always.
enum AutoplayMode: Int, CaseIterable, Sendable {
    case off, wifi, always
    var label: String {
        switch self {
        case .off: "Off"
        case .wifi: "On Wi-Fi only"
        case .always: "Always"
        }
    }

    /// The mode from its two prefs: the old switch (`autoplayMedia`) and, added
    /// later, `autoplayWifiOnly`, so a stored on is Always and off is Off.
    init(media: Bool, wifiOnly: Bool) { self = !media ? .off : wifiOnly ? .wifi : .always }

    /// Whether feed videos play now: on, and on Wi-Fi when that's asked for.
    func allows(unmetered: Bool) -> Bool { self == .always || (self == .wifi && unmetered) }
}

enum ThemeMode: Int, CaseIterable, Sendable { case system, light, dark }

/// Where the Posts-screen actions (search, new post, profile) live. Persisted by index.
enum TopBarMode: Int, CaseIterable, Sendable {
    case full, expandable

    var label: String { self == .full ? "Full top bar" : "Expandable" }
    var description: String {
        self == .full
            ? "Search, new post and profile across the top (current)"
            : "A big title that shrinks into the bar as you scroll, with search and ⋯ beside it"
    }
}

/// How round feed posts' cards and media are (#283): `factor` scales each corner's radius.
/// Persisted by index (`cornerRoundness`, never reorder).
enum CornerRoundness: Int, CaseIterable, Sendable {
    case round, medium, small, square

    var label: String {
        switch self {
        case .round: "Round"
        case .medium: "Medium"
        case .small: "Small"
        case .square: "Square"
        }
    }

    var description: String {
        switch self {
        case .round: "Soft, round corners, as designed"
        case .medium: "Less round"
        case .small: "Slightly rounded: photos keep more of their corners"
        case .square: "No rounding"
        }
    }

    var factor: CGFloat {
        switch self {
        case .round: 1
        case .medium: 0.6
        case .small: 0.3
        case .square: 0
        }
    }
}

/// `r` at `factor`: as is at 1, none at 0, otherwise scaled but not under 4pt (or `r` if smaller).
func scaleCorner(_ r: CGFloat, _ factor: CGFloat) -> CGFloat {
    if factor >= 1 { return r }
    if factor <= 0 { return 0 }
    return max(r * factor, min(r, 4))
}

/// The floating button on Home (#62). Persisted by index (`homeFab`).
enum HomeFab: Int, CaseIterable, Sendable {
    case off, newPost, search

    var label: String {
        switch self {
        case .off: return "Off"
        case .newPost: return "New post"
        case .search: return "Search"
        }
    }
}

/// How posts are laid out in feeds. Persisted by index (`postDisplay`).
enum PostDisplay: Int, CaseIterable, Sendable {
    // compact / compactCards (#284, after Sync for Reddit): appended, as it's stored by raw value.
    case large, card, mini, calm, calmCards, compact, compactCards

    var label: String {
        switch self {
        case .large: return "Default"
        case .card: return "Cards"
        case .mini: return "Mini cards"
        case .calm: return "Calm"
        case .calmCards: return "Calm cards"
        case .compact: return "Compact"
        case .compactCards: return "Compact cards"
        }
    }

    /// SF Symbol.
    var icon: String {
        switch self {
        case .large: return "rectangle.grid.1x2"
        case .card: return "rectangle.split.1x2"
        case .mini: return "list.bullet"
        case .calm: return "leaf.fill"
        case .calmCards: return "leaf"
        case .compact: return "list.bullet.rectangle"
        case .compactCards: return "rectangle.stack"
        }
    }

    /// Both Calm layouts share the Calm post view and the ⋮-sheet read toggle.
    var isCalm: Bool { self == .calm || self == .calmCards }

    /// The card has its own read toggle; the others offer it in the ⋮ sheet.
    var readToggleOnCard: Bool { self == .large || self == .card || self == .mini }

    /// Shows the poster's picture, so it asks for posters' pictures (as Settings › Poster's picture).
    var showsPosters: Bool { self == .compactCards }
}

/// What a swipe on a post or comment does. Persisted by [rawValue] (Flutter's enum name).
enum SwipeAction: String, CaseIterable, Sendable {
    case none, upvote, downvote, save, reply
    case hide // posts only
    case dismiss // posts only; local, 24h
    case hideSub // posts only; local
    case collapse // comments only

    var key: String { rawValue }

    var label: String {
        switch self {
        case .none: return "Nothing"
        case .upvote: return "Upvote"
        case .downvote: return "Downvote"
        case .save: return "Save"
        case .reply: return "Reply"
        case .hide: return "Hide"
        case .dismiss: return "Dismiss (Home / For You)"
        case .hideSub: return "Hide subreddit 7 days (front page)"
        case .collapse: return "Collapse"
        }
    }

    /// SF Symbol.
    var icon: String {
        switch self {
        case .none: return "nosign"
        case .upvote: return "arrow.up"
        case .downvote: return "arrow.down"
        case .save: return "bookmark.fill"
        case .reply: return "arrowshape.turn.up.left.fill"
        case .hide: return "eye.slash.fill"
        case .dismiss: return "xmark"
        case .hideSub: return "minus.circle.fill"
        case .collapse: return "chevron.up.chevron.down"
        }
    }

    static func parse(_ key: String?, _ fallback: SwipeAction) -> SwipeAction {
        key.flatMap(SwipeAction.init(rawValue:)) ?? fallback
    }
}

/// How comments look (#54): only two layouts, so "same as posts" follows Calm or not. Persisted by index.
/// Where a thread's floating buttons sit (#126). Persisted by index (`threadFabPosition`).
enum ThreadFabPosition: Int, CaseIterable, Sendable {
    case left, middle, right

    var label: String {
        switch self {
        case .left: return "Left"
        case .middle: return "Middle"
        case .right: return "Right"
        }
    }
}

enum CommentStyle: Int, CaseIterable, Sendable {
    case same, cards, calm

    var label: String {
        switch self {
        case .same: return "Same as posts"
        case .cards: return "Cards"
        case .calm: return "Calm"
        }
    }
}

/// A subreddit's own default sort (#60). Persisted in `subredditSorts` as "name|sort|time".
/// A section of the Explore tab (#161). Persisted by `rawValue` (never change one) in
/// `prefsKey`: their order, a hidden one as "-id". Your communities aren't one: they stay
/// last, with the filter and sort.
enum ExploreSection: String, CaseIterable, Sendable {
    // "all" its own section since #171; "popular" was both before.
    case popular, all, customFeeds, recentlyVisited, recommended, popularCommunities, favorites, following

    static let prefsKey = "exploreSections"

    var label: String {
        switch self {
        case .popular: "Popular"
        case .all: "All"
        case .customFeeds: "Custom feeds"
        case .recentlyVisited: "Recently visited"
        case .recommended: "Recommended for you"
        case .popularCommunities: "Popular communities"
        case .favorites: "Favorites"
        case .following: "Following"
        }
    }

    /// A list of your communities: these give way to the filter's results.
    var isCommunityList: Bool { self == .recentlyVisited || self == .recommended || self == .favorites || self == .following }

    /// The stored order: ids it doesn't know are dropped, and sections missing from it are
    /// added, shown, in their default order (Explore before #161), so later ones still appear.
    static func parse(_ stored: [String]?) -> [ExploreEntry] {
        var out: [ExploreEntry] = []
        for raw in stored ?? [] {
            let id = raw.hasPrefix("-") ? String(raw.dropFirst()) : raw
            guard let section = ExploreSection(rawValue: id), !out.contains(where: { $0.section == section }) else { continue }
            out.append(ExploreEntry(section: section, shown: !raw.hasPrefix("-")))
        }
        // Stored before All had its own section (#171): "popular" was both, so All goes right
        // after it, shown or hidden as it was, not to the end.
        if let popular = out.firstIndex(where: { $0.section == .popular }), !out.contains(where: { $0.section == .all }) {
            out.insert(ExploreEntry(section: .all, shown: out[popular].shown), at: popular + 1)
        }
        for section in allCases where !out.contains(where: { $0.section == section }) { out.append(ExploreEntry(section: section, shown: true)) }
        return out
    }

    static func toPrefs(_ entries: [ExploreEntry]) -> [String] { entries.map { $0.shown ? $0.section.rawValue : "-\($0.section.rawValue)" } }
}

struct ExploreEntry: Equatable, Sendable {
    var section: ExploreSection
    var shown: Bool
}

struct SubredditSort: Equatable, Sendable {
    let sort: PostSort
    let time: TopTime
}

/// Every user setting. Keys/defaults match the Flutter build exactly.
struct Settings: Equatable, Sendable {
    /// Bloom primary — the default accent.
    static let defaultSeed = 0xFF6750A4

    var themeMode: ThemeMode = .system
    var amoled = false
    var inAppBrowser = false // open web links in an in-app browser, not the browser app
    var tapToCollapse = false // tap a comment to collapse it (else long-press)
    var collapseRepliesOnly = false // collapsing keeps the comment's own text, hides its replies
    var commentButtonsOnTap = false // a comment's buttons show only when it's tapped (#239)
    var voteEdge = true // comments you voted on are marked in the vote's color
    var voteGlow = true // ...with a soft glow (and the thread's post too); false: the edge line (#141)
    var commentAvatars = true // commenters' profile pictures (website sign-in, #133)
    var autoTranslate = false // posts in neither translation language open translated into the phone's
    var translateSecondLanguage = "" // language code Translate also offers ("" = none)
    var translateService = "openai" // for what the phone can't translate: "openai" (the AI key) or "azure"
    var azureRegion = "" // the Azure Translator resource's region ("" = global)
    var collapseBelowScore: Int? = nil // comments scoring below this start collapsed (nil = off)
    var collapseTopLevel = false // threads open with top-level comments' replies collapsed
    var hideReadPosts = false // skip already-read posts when feeds load
    var hideReadInSubreddits = false // …in single subreddits too (else front page / custom feeds only)
    var recentSubsByVisits = false // "Recently visited" lists the most visited first (#92), else the newest
    var dimReadTextOnly = false // read posts: dim only title / text (images stay bright), else the whole card
    var dimRead = true // read posts dim at all (#106); off: history is still kept, nothing fades
    var subredditIcons = true // cards show the subreddit's icon (else its first letter)
    var subredditPrefix = true // subreddit and user names show as "r/name" and "u/name" (else just "name", #97, #289); display only
    var postAvatars = false // the poster's picture on the subreddit icon (#270): one more request per page
    var sideBarUserPrefix = true // the side bar shows your name as "u/name" (else just "name", #167)
    var markReadOnScroll = false // a post scrolled past counts as read
    // What swiping does: "start" = from the start edge (rightward in LTR).
    var swipePostStart: SwipeAction = .upvote
    var swipePostEnd: SwipeAction = .downvote
    var swipeCommentStart: SwipeAction = .upvote
    var swipeCommentEnd: SwipeAction = .downvote
    var seedColor = Settings.defaultSeed // ARGB
    var blurNsfw = true
    var defaultSort: PostSort = .best
    var subredditSorts: [String: SubredditSort] = [:] // by lowercase name; overrides defaultSort there
    var defaultCommentSort = "confidence" // reddit comment sort id
    var postDisplay: PostDisplay = .calm
    var postTextLines = 0 // a post's text in feeds, in lines (#186); 0: the layout's own (2–3)
    var commentStyle: CommentStyle = .same
    var swipeActions = true
    var floatingChips = true // Home: filter chips float under the top bar past the list's own
    var fullBarNewPost = true // Full top bar: a New post button beside your avatar
    var trackHistory = true
    var saveSearchHistory = true // Search keeps your recent searches; off: none kept or shown (#302)
    var newPostsPill = true // a stale feed's fresh posts wait behind a "New posts" pill (#292)
    var showRecentlyVisited = true // Explore and the side bar list the subreddits you opened last
    var exploreSections = ExploreSection.parse(nil) // Explore's sections, and their order (#161)
    var offlineCache = true
    var checkUpdates = true
    var safariAsk = false // the Safari extension asks: Ilay or the Reddit app
    var analytics = true // anonymous usage stats (Aptabase)
    var forYouFeed = false // frontpage uses the "For You" feed
    var postsTabAll = false // the Posts tab shows r/all instead of the frontpage, which Explore's All button opens then
    var blendHome = false // with forYouFeed + Reddit Home allowed: "Blend (Beta)", For You ranking over your Reddit Home too
    var blendReddit = 1 // Blend: Reddit ↔ Ilay — 0 mostly Ilay, 1 balanced, 2 mostly Reddit
    // The Digest (docs/digest-spec.md). Its communities are per account (DigestModule).
    var digestEnabled = false
    var digestSize = 1 // DigestSize index: 0 Brief, 1 Standard, 2 Everything notable
    var digestPlace = 0 // 0 a chip on Posts, 1 a bottom tab, 2 menu only
    var digestShowRead = false // the Digest keeps read posts (dimmed) instead of hiding them
    var digestAi = false // the AI picks and explains (never on unless the user turns it on)
    var digestOverview = false // with the AI: a paragraph about the day on top
    var digestAiBuilds = 1 // which builds use the AI: 0 every build, 1 the day's first and Rebuild (refreshes stay quick)
    var digestAiPick = true // with the AI: it picks the posts (off: the numbers pick)
    var digestAiWhy = true // with the AI: it writes each post's "why"
    var digestLanguage: String? = nil // the AI's language for the Digest; nil = as AI summaries
    var digestNotify = false // a daily notification at digestTime
    var digestTime = 480 // minutes after midnight, local (08:00)
    var digestSwipe = 0 // which swipe marks read in the Digest: 0 left, 1 right, 2 both
    var digestOrder = 0 // DigestOrder index: 0 Most notable, 1 Most upvoted, 2 Newest, 3 AI's assessment
    // Experimental Reddit Home: the user accepted its risk warning (allowed),
    // and the frontpage currently shows it (feed).
    var redditHomeAllowed = false
    var redditHomeFeed = false
    var autoHideReadForYou = false // hide already-read items in For You
    var forYouDiscovery = 0 // For You's Familiar (-2) ↔ Discover (+2) slider; 0 = adaptive default
    var midResThumbnails = true // load smaller preview images in feeds
    var subsCacheEnabled = true // cache subscription list in memory
    var subsCacheMinutes = 10 // how long to keep the subs cache
    var imageCacheMb = 512 // image disk cache; applies on the next start
    var videoCacheMb = 200 // played-video cache; applies on the next start
    var feedKeepMinutes = 30 // how long the frontpage keeps its posts before returning to it reloads
    var hiddenPostDays = 7 // how long Ilay keeps posts you hid out of every feed (Reddit hides them too)
    var textScale = 1.0 // global text size multiplier (0.8–1.4)
    // #234: on top of textScale, for post titles, post text (feed previews and the post's
    // body) and comment text; 1.0 = as before.
    var titleTextScale = 1.0
    var postTextScale = 1.0
    var commentTextScale = 1.0
    var autoplayMedia = true // autoplay videos/GIFs in feeds
    var autoplayWifiOnly = false // ...only on an unmetered network (Wi-Fi); see AutoplayMode
    var autoplaySound = false // feed videos start unmuted (#23)
    var viewerMuted = false // full-screen videos start muted (#51)
    var loopVideos = true // full-screen and Browse media videos start over at the end; off: they stop, with a replay button (#156). GIFs always loop
    var feedGalleryCarousel = true // galleries in feeds as a carousel (else one image at a time)
    var showApiUsage = false // show API usage instead of search on Posts screen
    var notifyInbox = false // background-poll the inbox + local notifications
    var inboxCheckMinutes = 15 // how often (#188); iOS treats it as "not before"
    var homeFab: HomeFab = .off // floating button on Home
    var subredditFab: HomeFab = .newPost // subreddits' floating button (#300): New post, as it always was
    var fabHideOnScroll = false // the feeds' floating button hides as you scroll down, not just folds (#301)
    var threadFabPosition: ThreadFabPosition = .right // where a thread's floating buttons sit (#126)
    var threadJumpOp: Bool = true // a thread's button for the original poster's comments (#126)
    var threadJumpMine: Bool = true // a thread's button for your own comments (#126)
    var threadJumpNext: Bool = true // a thread's next top-level comment button (#121)
    var threadButtonsHideOnScroll = false // the thread's buttons step aside while you scroll (#210)
    var resumeThreads = true // reopening a thread scrolls back to where you left off (#179); off: from the top (#269)
    var topBarMode: TopBarMode = .expandable // Posts-screen action layout
    var cornerRoundness: CornerRoundness = .round // feed posts' cards and media (#283)
    var navLabels = true // show text labels on the bottom nav bar
    var inboxInProfile = false // Inbox opens from Profile's top bar instead of being a tab
    var navStyle = 0 // 0 bottom bar, 1 side bar, 2 both (#25)
    var navOutline = true // thin outline around the floating bottom bar (#29)
    var backScrollsToTop = true // back on the Posts tab scrolls the feed to top
    var aiModel = "gpt-5.4-mini" // OpenAI(-compatible) model id for summaries
    var aiSummaryStyle = 1 // index into SummaryStyle (Key points)
    var aiSummaryLanguage = "" // English name of the language summaries are written in; "" = the thread's own
    var aiMaxChars = 100_000 // max thread text sent to the model
    var aiUseCustomUrl = false // use a custom API base URL
    var aiBaseUrl = "https://api.openai.com" // custom base URL (when enabled)
    var appIcon = "violet" // launcher icon colour (AppIcon key)

    /// Calm comment rows instead of cards.
    var calmComments: Bool {
        switch commentStyle {
        case .same: return postDisplay.isCalm
        case .cards: return false
        case .calm: return true
        }
    }
}

/// Settings → Dim read posts (#106). Stored as `dimRead` (off: nothing fades, history
/// is still kept) plus `dimReadTextOnly`, which keeps its meaning from before Off existed.
enum ReadDim: Hashable, Sendable { case off, card, text }

extension Settings {
    var readDim: ReadDim { !dimRead ? .off : dimReadTextOnly ? .text : .card }

    /// The Posts tab's feed key: the frontpage, or r/all with `postsTabAll`.
    var postsTabKey: String { postsTabAll ? "all" : "" }
}
