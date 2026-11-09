import Foundation
import Observation

/// The app's singletons (manual DI). Reach it with the global [app].
///
/// Module constructors must take this container as a parameter rather than use
/// `app` (the global is being created while they run); `app` is fine inside methods.
@MainActor @Observable
final class AppContainer {
    let prefs: Prefs
    let secureStore: SecureStore
    let settings: SettingsStore
    let authRepository: AuthRepository
    let session: SessionManager

    /// Latest Reddit API rate-limit snapshot.
    var rateLimit: RateLimit?

    let client: RedditClient
    let repository: RedditRepository

    // Shared, per-account local state.
    let postOverrides: PostOverrides
    let commentVotes: CommentVotes
    let authorAvatars: AuthorAvatars
    /// Posts hidden with Hide (also hidden on Reddit). Kept on the device too —
    /// Home's id-fetched posts and saved first pages don't honour Reddit's
    /// hidden flag, so a session-only set let them reappear after a restart.
    let hiddenPosts: ExpiringIds
    /// Posts swiped away from Home / For You ("Dismiss"), for a day.
    let dismissedPosts: ExpiringIds
    /// Subreddits hidden from Home / For You for a week (lowercase names).
    let hiddenHomeSubs: ExpiringIds
    let summaries: SummaryStore
    let history: HistoryStore
    let recentSubreddits: RecentSubreddits
    let threadVisits: ThreadVisits
    let contentFilters: ContentFiltersStore
    let offline: OfflineStore
    let drafts: Drafts
    let savedSearches: SavedSearches

    // LATER: per-feature singletons, as `@ObservationIgnored lazy var`s; a module
    // that is UserScoped also joins [userScoped] below.
    @ObservationIgnored lazy var feed = FeedModule(self)
    @ObservationIgnored lazy var forYou = ForYouModule(self)
    @ObservationIgnored lazy var inbox = InboxModule(self)
    @ObservationIgnored lazy var redditNotifications = RedditNotifications(self)
    @ObservationIgnored lazy var notificationLog = NotificationLog(prefs: prefs)
    @ObservationIgnored lazy var media = MediaModule()
    @ObservationIgnored lazy var post = PostModule(self)

    /// The identity whose per-account stores are loaded (after a login/switch settles).
    var loadedIdentity: String?

    @ObservationIgnored private var previousIdentity: String?
    /// Whether the logged-out identity's stores were loaded before the session settled.
    @ObservationIgnored private var loadedLoggedOutEarly = false

    private var userScoped: [UserScoped] {
        [postOverrides, commentVotes, hiddenPosts, dismissedPosts, hiddenHomeSubs, summaries, history, recentSubreddits, threadVisits, contentFilters, offline, feed, forYou, inbox, redditNotifications]
    }

    init() {
        let prefs = Prefs()
        let secureStore = SecureStore()
        let settings = SettingsStore(prefs: prefs)
        let authRepository = AuthRepository(store: secureStore)
        let session = SessionManager(store: secureStore, repo: authRepository, prefs: prefs)
        let client = RedditClient(
            store: secureStore,
            auth: authRepository,
            cache: ResponseCache(cacheDir: FileLocations.caches),
            onRateLimit: { r in Task { @MainActor in app.rateLimit = r } }
        )
        let repository = RedditRepository(client: client)
        self.prefs = prefs
        self.secureStore = secureStore
        self.settings = settings
        self.authRepository = authRepository
        self.session = session
        self.client = client
        self.repository = repository
        postOverrides = PostOverrides()
        commentVotes = CommentVotes()
        authorAvatars = AuthorAvatars()
        hiddenPosts = ExpiringIds(prefs: prefs, baseKey: "hiddenPostIds") { settings.value.hiddenPostDays * 24 * 60 * 60_000 }
        dismissedPosts = ExpiringIds(prefs: prefs, baseKey: "dismissedPosts") { 24 * 60 * 60_000 }
        hiddenHomeSubs = ExpiringIds(prefs: prefs, baseKey: "hiddenHomeSubs") { 7 * 24 * 60 * 60_000 }
        summaries = SummaryStore()
        history = HistoryStore(prefs: prefs)
        recentSubreddits = RecentSubreddits(prefs: prefs) { settings.value.recentSubsByVisits }
        threadVisits = ThreadVisits(prefs: prefs, settings: settings)
        contentFilters = ContentFiltersStore(prefs: prefs)
        offline = OfflineStore(prefs: prefs, repo: repository)
        drafts = Drafts(prefs: prefs) { session.username }
        savedSearches = SavedSearches(prefs: prefs) { session.username }
    }

    /// Called once at launch, after [app] exists (modules may use it).
    func start() {
        feed.engines = forYou
        // Load per-account stores for the logged-out identity right away, so
        // they're usable before the session finishes loading. Not with an account
        // on the device: the session settles on it moments later and loads its own,
        // and parsing the logged-out history, visits and filters first, here before
        // the first frame, was wasted launch time.
        if !session.hasAccount {
            userScoped.forEach { $0.onUserChanged("") }
            loadedLoggedOutEarly = true
        }
        apply(settings.value)
        settings.onChange = { [unowned self] old, new in
            if old.subsCacheEnabled != new.subsCacheEnabled || old.subsCacheMinutes != new.subsCacheMinutes || old.offlineCache != new.offlineCache {
                apply(new)
            }
            // A new "Hide posts for" time applies at once (a shorter one un-hides now).
            if old.hiddenPostDays != new.hiddenPostDays { hiddenPosts.refresh() }
            // Recently visited takes a new order at once.
            if old.recentSubsByVisits != new.recentSubsByVisits { recentSubreddits.refresh() }
        }
        session.onStateChanged = { [unowned self] in sessionChanged($0) }
    }

    private func apply(_ s: Settings) {
        repository.setSubsCache(enabled: s.subsCacheEnabled, ttlMillis: s.subsCacheMinutes * 60_000)
        client.setCacheEnabled(s.offlineCache)
    }

    // On any account change (switch, or logout then login as someone else):
    // re-read auth config and reload everything that belongs to an account.
    private func sessionChanged(_ s: SessionState) {
        client.invalidateAuthConfig()
        // A full logout drops back to the logged-out identity (bare keys),
        // so the previous account's stores don't stay loaded.
        let identity: String
        switch s {
        case .loggedIn(let session): identity = session.identity
        // Only a real logout (has_account cleared) — not a transient
        // keychain read failure, which must keep everything loaded.
        case .loggedOut:
            if session.hasAccount {
                // start() skipped the logged-out load, expecting the account: give
                // the stores the logged-out identity, as they had before that skip.
                if previousIdentity == nil, !loadedLoggedOutEarly {
                    userScoped.forEach { $0.onUserChanged("") }
                    loadedLoggedOutEarly = true
                }
                return
            }
            identity = ""
        case .loading: return
        }
        if identity != previousIdentity {
            if previousIdentity != nil { repository.clearSubsCache() }
            let first = previousIdentity == nil
            previousIdentity = identity
            // start() (or a transient logout above) already loaded the logged-out identity.
            if !(first && identity.isEmpty && loadedLoggedOutEarly) {
                var username = ""
                if case .loggedIn(let session) = s { username = session.username }
                userScoped.forEach { $0.onUserChanged(username) }
            }
        }
        loadedIdentity = identity
    }
}

/// The app's singletons. Created on first use, which is on the main thread:
/// `IlayApp.init` touches it before anything else can.
let app: AppContainer = MainActor.assumeIsolated { AppContainer() }
