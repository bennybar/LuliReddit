import Foundation

// Left out of [Settings] as Android / Material only (PORTING.md), their keys
// stay reserved and untouched in the prefs, never reuse them: `useDynamicColor`,
// `appFont`, `jakartaFont`, `volumeKeyNavigation`, `redditAppNotifications`.

/// Order matters: persisted by index (`themeMode`), same as Flutter's ThemeMode.
enum ThemeMode: Int, CaseIterable, Sendable { case system, light, dark }

/// Where the Posts-screen actions (search, new post, profile) live. Persisted by index.
enum TopBarMode: Int, CaseIterable, Sendable {
    case full, expandable

    var label: String { self == .full ? "Full top bar" : "Expandable" }
    var description: String {
        self == .full
            ? "Search, new post and profile across the top (current)"
            : "Just a title with one button that floats the full top bar in on demand"
    }
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
    case large, card, mini, calm, calmCards

    var label: String {
        switch self {
        case .large: return "Default"
        case .card: return "Cards"
        case .mini: return "Mini cards"
        case .calm: return "Calm"
        case .calmCards: return "Calm cards"
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
        }
    }

    /// Both Calm layouts share the Calm post view and the ⋮-sheet read toggle.
    var isCalm: Bool { self == .calm || self == .calmCards }
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
    var voteEdge = true // comments you voted on get an edge in the vote's color
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
    var commentStyle: CommentStyle = .same
    var swipeActions = true
    var floatingChips = true // Home: filter chips float under the top bar past the list's own
    var fullBarNewPost = true // Full top bar: a New post button beside your avatar
    var trackHistory = true
    var showRecentlyVisited = true // Explore and the side bar list the subreddits you opened last
    var offlineCache = true
    var checkUpdates = true
    var safariAsk = false // the Safari extension asks: Ilay or the Reddit app
    var analytics = true // anonymous usage stats (Aptabase)
    var forYouFeed = false // frontpage uses the "For You" feed
    var postsTabAll = false // the Posts tab shows r/all instead of the frontpage, which Explore's All button opens then
    var blendHome = false // with forYouFeed + Reddit Home allowed: "Blend (Beta)", For You ranking over your Reddit Home too
    var blendReddit = 1 // Blend: Reddit ↔ Ilay — 0 mostly Ilay, 1 balanced, 2 mostly Reddit
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
    var autoplayMedia = true // autoplay videos/GIFs in feeds
    var autoplaySound = false // feed videos start unmuted (#23)
    var viewerMuted = false // full-screen videos start muted (#51)
    var feedGalleryCarousel = true // galleries in feeds as a carousel (else one image at a time)
    var showApiUsage = false // show API usage instead of search on Posts screen
    var notifyInbox = false // background-poll the inbox + local notifications
    var homeFab: HomeFab = .off // floating button on Home
    var topBarMode: TopBarMode = .expandable // Posts-screen action layout
    var navLabels = true // show text labels on the bottom nav bar
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
