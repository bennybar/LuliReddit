import Foundation
import Observation

/// A loaded thread: the post, its comment tree and per-view state.
struct PostThread: Equatable, Sendable, Copyable {
    var post: Post
    var comments: [Comment]
    var collapsed: Set<String> // collapsed comment ids
    var loadingMore: Set<String> // "more" node fullnames being fetched
    /// Visible rows, depth-first (recomputed whenever the tree or collapse set changes).
    var flat: [Comment]

    init(post: Post, comments: [Comment], collapsed: Set<String> = [], loadingMore: Set<String> = []) {
        self.post = post
        self.comments = comments
        self.collapsed = collapsed
        self.loadingMore = loadingMore
        flat = CommentTree.flatten(comments, collapsed)
    }

    /// This thread with [texts] (ThreadUiState.translation) in place of the original post and comment texts.
    func translated(_ texts: [String: String]?) -> PostThread {
        guard let texts else { return self }
        func tr(_ c: Comment) -> Comment {
            if c.isMore { return c }
            return c.with {
                $0.body = texts[c.fullname] ?? c.body
                $0.replies = c.replies.map(tr)
            }
        }
        let comments = comments.map(tr)
        return with {
            $0.post = post.with {
                $0.title = texts["title"] ?? post.title
                $0.selftext = texts["body"] ?? post.selftext
            }
            $0.comments = comments
            $0.flat = CommentTree.flatten(comments, collapsed)
        }
    }
}

struct ThreadUiState {
    var thread: PostThread? = nil
    var loading = true
    var refreshing = false
    var error: Error? = nil
    var sort = ""
    /// The languages Translate offers for this thread (the phone's and the second one, minus the thread's).
    var translateTargets: [String] = []
    /// Shown translated into [translatedTo]: post ("title", "body") and comment (fullname) texts. Nil: the original.
    var translation: [String: String]? = nil
    var translatedTo: String? = nil
    var translating = false
    /// Comments translated one by one (their ⋯ menu): fullname → text, over the thread's translation.
    var commentTranslations: [String: String] = [:]

    /// The texts shown in place of the originals: the thread's translation and single comments'.
    var shownTexts: [String: String]? {
        if translation == nil, commentTranslations.isEmpty { return nil }
        return (translation ?? [:]).merging(commentTranslations) { _, single in single }
    }
}

/// Comments in the first request. Reddit answers 30 in about half the time of
/// 100 (~0.5s vs ~1s, a third of the bytes), so the thread paints with these
/// and the full [fullPage] follows in the background.
private let firstPage = 30
private let fullPage = 100

/// The thread screen's state (the Flutter CommentsController): loads the post +
/// comments (following a suggested sort, falling back to an offline copy),
/// and owns collapse / reply / edit / vote / delete / load-more on the tree.
@MainActor @Observable
final class CommentsViewModel {
    @ObservationIgnored private let subreddit: String
    @ObservationIgnored private let postId: String
    /// Set when viewing a single comment thread.
    @ObservationIgnored let focusCommentId: String?

    var ui = ThreadUiState() {
        didSet {
            revision += 1
            // Translated: Translate in the top bar, or Settings → Auto-translate.
            shown = ui.thread?.translated(ui.shownTexts)
        }
    }
    /// The thread as shown: [ui]'s, translated when that's on.
    private(set) var shown: PostThread?
    /// Bumped on every change of [ui]: lets the comment list skip work for anything else that redraws the screen.
    private(set) var revision = 0

    // Empty until the first load seeds it from the user's default comment sort.
    @ObservationIgnored private var sort = ""
    @ObservationIgnored private var sortChosen = false // the user picked a sort for this thread
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    // The tree changed locally (vote, reply, edit, load more…) since the first
    // page: the full page then must not replace it.
    @ObservationIgnored private var touched = false
    // The thread's language and every text translated so far, per target
    // language, kept while the original is shown.
    @ObservationIgnored private var language: String?
    @ObservationIgnored private var translations: [String: [String: String]] = [:]
    @ObservationIgnored private var started = false

    /// Cheap and without side effects: SwiftUI can call it many times for one screen. [start] loads.
    init(subreddit: String, postId: String, focusCommentId: String?) {
        self.subreddit = subreddit
        self.postId = postId
        self.focusCommentId = focusCommentId
    }

    func start() {
        if started { return }
        started = true
        load(showLoading: true)
    }

    /// The first load, and whether the full page should follow (not for an offline copy or a focused thread).
    private func build() async throws -> (PostThread, Bool) {
        // Seed from the user's default comment sort (changeSort overrides it).
        if sort.isEmpty {
            sort = app.settings.value.defaultCommentSort
            // The feed's post knows the mods' suggested sort (AMAs: Q&A):
            // start with it rather than fetching twice.
            let cached: Post? = NavCache.get(postId)
            if !sortChosen, let suggested = cached?.suggestedSort, COMMENT_SORTS.contains(where: { $0.id == suggested }) { sort = suggested }
        }
        let repo = app.repository
        // A focused (single-comment) thread is small: one full request.
        let paged = focusCommentId == nil
        let limit = paged ? firstPage : fullPage
        var t: RedditThread
        do {
            t = try await repo.getComments(subreddit: subreddit, postId: postId, sort: sort, focusCommentId: focusCommentId, limit: limit)
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
            // Saved for offline (Read later)? Show that copy instead of an error.
            guard focusCommentId == nil, let saved = await app.offline.read(postId) else { throw error }
            let th = try await Task.detached { try repo.parseThread(saved) }.value
            return (PostThread(post: th.post, comments: app.commentVotes.apply(th.comments)), false)
        }
        // Threads like AMAs set a suggested sort (Q&A, New). Follow it unless the
        // user picked a sort for this thread; it's only known once fetched.
        if !sortChosen, let suggested = t.suggestedSort, suggested != sort, COMMENT_SORTS.contains(where: { $0.id == suggested }) {
            sort = suggested
            ui.sort = sort
            t = try await repo.getComments(subreddit: subreddit, postId: postId, sort: sort, focusCommentId: focusCommentId, limit: limit)
        }
        // Commenters' pictures come after, on their own request (#133).
        let (avatarPost, avatarSort) = (postId, sort)
        Task { await app.authorAvatars.loadFor(postId: avatarPost, sort: avatarSort) }
        let comments = app.commentVotes.apply(t.comments)
        let collapsed = startCollapsed(t.comments)
        let (post, raw) = (t.post, t.comments)
        // Fetch the full page only when the first one was cut short (it ends in
        // "load more" rows); a small thread is already complete.
        return await Task.detached {
            (PostThread(post: post, comments: comments, collapsed: collapsed), paged && CommentTree.flatten(raw, []).contains { $0.isMore })
        }.value
    }

    /// Swaps in the full page under the first one. Same sort, so the comments
    /// already on screen keep their place (rows are keyed by fullname) and the
    /// rest appear below; collapse state carries over. Skipped once the user has
    /// changed the tree, or if the request fails (the first page's "more"
    /// rows still load the rest).
    private func loadFullPage() async {
        guard let full = try? await app.repository.getComments(subreddit: subreddit, postId: postId, sort: sort, limit: fullPage),
              !Task.isCancelled, let cur = ui.thread, !touched else { return }
        // New comments start collapsed by the same rules as on first load.
        let rules = collapseRules
        let (shownComments, fullComments) = (cur.comments, full.comments)
        let autoMod = await Task.detached {
            let known = Set(CommentTree.flatten(shownComments, []).map(\.id))
            return CommentsViewModel.startCollapsed(fullComments, rules: rules, skip: known)
        }.value
        guard !touched, !Task.isCancelled, let latest = ui.thread else { return }
        // Collapse state from the latest thread: a toggle made while the full
        // page was being prepared must survive the swap.
        let comments = app.commentVotes.apply(full.comments)
        ui.thread = PostThread(post: full.post, comments: comments, collapsed: latest.collapsed.union(autoMod))
        app.postOverrides.syncFromServer(full.post)
        prewarm(comments, post: full.post)
    }

    private func load(showLoading: Bool) {
        loadTask?.cancel()
        if showLoading {
            ui.loading = true
            ui.error = nil
            ui.thread = nil
            ui.sort = sort
        } else {
            ui.refreshing = true
            ui.sort = sort
        }
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                touched = false
                let (t, more) = try await build()
                if Task.isCancelled { return }
                let shown = ui
                ui = ThreadUiState(
                    thread: t, loading: false, sort: sort,
                    translateTargets: shown.translateTargets, translation: shown.translation, translatedTo: shown.translatedTo
                )
                app.postOverrides.syncFromServer(t.post)
                prewarm(t.comments, post: t.post)
                if language == nil { await detectLanguage(t) } else if let to = shown.translatedTo { translate(to) }
                if more, !Task.isCancelled {
                    await loadFullPage()
                    if let to = ui.translatedTo { translate(to) }
                }
            } catch {
                if Task.isCancelled || error is CancellationError { return }
                if !showLoading, ui.thread != nil {
                    // A failed refresh keeps the thread (and its collapsed
                    // comments) readable; the error screen is for nothing loaded.
                    ui.refreshing = false
                    app.navigator.showSnackbar("Couldn't refresh: \(friendlyError(error))", actionLabel: "Retry") { [weak self] in self?.refresh() }
                } else {
                    ui = ThreadUiState(thread: nil, loading: false, error: error, sort: sort)
                }
            }
        }
    }

    /// Parses every body off the main actor, before the cells that show them ask:
    /// what makes a thread of thousands of rows bind without parsing mid-scroll.
    private func prewarm(_ comments: [Comment], post: Post) {
        Task.detached(priority: .utility) {
            var texts: [String] = []
            func walk(_ c: Comment) {
                if !c.isMore {
                    for case let .text(t) in CommentBody.segments(c) { texts.append(t) }
                    c.replies.forEach(walk)
                }
            }
            comments.forEach(walk)
            for case let .text(t) in bodySegments(post.selftext, post.bodyMedia, CommentBody.maxPostMedia) { texts.append(t) }
            await RedditMarkdownParser.prewarm(texts)
        }
    }

    /// Offers Translate into the phone's language and the second one (Settings
    /// → Translation), less the thread's own. With Settings → Auto-translate, a
    /// thread in neither opens translated into the phone's.
    private func detectLanguage(_ t: PostThread) async {
        // The post and its first comments: a title alone is too short to be sure.
        let sample = [t.post.title, t.post.selftext] + t.comments.filter { !$0.isMore }.prefix(5).map(\.body)
        guard let lang = Translate.detect(sample.joined(separator: "\n")) else { return }
        let targets = await Translate.targets(from: lang)
        if targets.isEmpty { return }
        language = lang
        ui.translateTargets = targets
        let s = app.settings.value
        if s.autoTranslate, lang != s.translateSecondLanguage, targets.contains(Translate.primary) { translate(Translate.primary) }
    }

    /// Shows the thread in [to], or the original when nil.
    func translateTo(_ to: String?) {
        if let to {
            translate(to)
        } else {
            ui.translation = nil
            ui.translatedTo = nil
        }
    }

    /// Shows the thread translated into [to], translating what isn't yet (the post, comments loaded since).
    private func translate(_ to: String) {
        guard let from = language, let t = ui.thread else { return }
        let done = translations[to] ?? [:]
        var keys: [String] = []
        var texts: [String] = []
        func want(_ k: String, _ v: String) {
            keys.append(k)
            texts.append(v)
        }
        if done["title"] == nil { want("title", t.post.title) }
        if done["body"] == nil, !t.post.selftext.isEmpty { want("body", t.post.selftext) }
        for c in CommentTree.flatten(t.comments, []) where !c.isMore && done[c.fullname] == nil && !c.body.isEmpty {
            want(c.fullname, c.body)
        }
        if keys.isEmpty {
            ui.translation = done
            ui.translatedTo = to
            return
        }
        ui.translating = true
        Task { [weak self] in
            let out: [String]?
            do {
                out = try await Translate.translate(texts, from: from, to: to)
            } catch {
                self?.ui.translating = false
                app.navigator.showSnackbar("Couldn't translate: \(error.localizedDescription)")
                return
            }
            guard let self else { return }
            guard let out else {
                ui.translating = false
                app.navigator.showSnackbar("Couldn't translate this post")
                return
            }
            var all = translations[to] ?? [:]
            for (k, v) in zip(keys, out) { all[k] = v }
            translations[to] = all
            ui.translating = false
            ui.translation = all
            ui.translatedTo = to
        }
    }

    /// One comment's ⋯ → Translate: in its own language's terms (a thread can
    /// mix them); [pick] chooses when there are two languages to offer.
    func translateComment(_ fullname: String, pick: @escaping ([String]) async -> String?) {
        if ui.commentTranslations[fullname] != nil {
            ui.commentTranslations[fullname] = nil
            return
        }
        guard let t = ui.thread, let c = CommentTree.flatten(t.comments, []).first(where: { $0.fullname == fullname }) else { return }
        Task { [weak self] in
            guard let self else { return }
            guard let from = Translate.detect(c.body) ?? language else {
                return app.navigator.showSnackbar("Couldn't tell which language this comment is in")
            }
            let targets = await Translate.targets(from: from)
            let to: String
            switch targets.count {
            case 0: return app.navigator.showSnackbar("Nothing to translate it into: it's in your phone's language. Add a second language in Settings → Translation.")
            case 1: to = targets[0]
            default:
                guard let picked = await pick(targets) else { return }
                to = picked
            }
            do {
                guard let out = try await Translate.translate([c.body], from: from, to: to)?.first else {
                    return app.navigator.showSnackbar("Couldn't translate this comment")
                }
                ui.commentTranslations[fullname] = out
            } catch {
                app.navigator.showSnackbar("Couldn't translate: \(error.localizedDescription)")
            }
        }
    }

    var currentSort: String { sort.isEmpty ? app.settings.value.defaultCommentSort : sort }

    func changeSort(_ s: String) {
        sort = s
        sortChosen = true
        load(showLoading: true)
    }

    /// Pull-to-refresh: keeps the current thread on screen until the new one is in.
    func refresh() { load(showLoading: ui.thread == nil) }

    private func edit(_ block: (PostThread) -> PostThread) {
        if let t = ui.thread { ui.thread = block(t) }
    }

    private func withTree(_ t: PostThread, _ comments: [Comment]) -> PostThread {
        touched = true
        return t.with {
            $0.comments = comments
            $0.flat = CommentTree.flatten(comments, t.collapsed)
        }
    }

    func toggleCollapse(_ commentId: String) {
        edit { t in
            let next = CommentsViewModel.toggled(t.collapsed, commentId, in: t.flat, repliesOnly: app.settings.value.collapseRepliesOnly)
            return t.with {
                $0.collapsed = next
                $0.flat = CommentTree.flatten(t.comments, next)
            }
        }
    }

    /// The collapse set after a toggle of [commentId]. Pure, for the tests.
    nonisolated static func toggled(_ collapsed: Set<String>, _ commentId: String, in flat: [Comment], repliesOnly: Bool) -> Set<String> {
        let folded = CommentTree.folded(commentId)
        // Expanding a comment also shows its folded replies.
        if collapsed.contains(commentId) { return collapsed.subtracting([commentId, folded]) }
        if collapsed.contains(folded) { return collapsed.subtracting([folded]) }
        // "Collapse only the replies": its own text stays (when it has replies to hide).
        if repliesOnly, flat.first(where: { $0.id == commentId })?.replies.contains(where: { !$0.isMore }) == true {
            return collapsed.union([folded])
        }
        return collapsed.union([commentId])
    }

    /// "Show N replies" under a folded comment.
    func unfold(_ commentId: String) {
        edit { t in
            let next = t.collapsed.subtracting([CommentTree.folded(commentId)])
            return t.with {
                $0.collapsed = next
                $0.flat = CommentTree.flatten(t.comments, next)
            }
        }
    }

    /// The settings [startCollapsed] follows, as a value that can leave the main actor.
    struct CollapseRules: Sendable {
        var collapseAutoMod = false
        var below: Int? = nil
        var topLevel = false
        var me = ""
    }

    private var collapseRules: CollapseRules {
        let s = app.settings.value
        return CollapseRules(collapseAutoMod: app.contentFilters.value.collapseAutoMod, below: s.collapseBelowScore, topLevel: s.collapseTopLevel, me: app.session.username)
    }

    private func startCollapsed(_ comments: [Comment]) -> Set<String> {
        CommentsViewModel.startCollapsed(comments, rules: collapseRules)
    }

    /// The comments a thread opens with collapsed: AutoModerator's (content
    /// filter), ones scoring below the "Collapse low-scoring comments" setting
    /// (not your own), and with "Open threads collapsed" every top-level
    /// comment's replies (folded: its own text stays). [skip]: ones already
    /// shown, left as they are.
    nonisolated static func startCollapsed(_ comments: [Comment], rules: CollapseRules, skip: Set<String> = []) -> Set<String> {
        var out = Set<String>()
        for c in CommentTree.flatten(comments, []) where !c.isMore && !skip.contains(c.id) {
            if rules.collapseAutoMod, c.author == "AutoModerator" {
                out.insert(c.id)
            } else if let below = rules.below, c.score < below, !c.scoreHidden, c.author.lowercased() != rules.me.lowercased() {
                out.insert(c.id)
            } else if rules.topLevel, c.depth == 0, c.replies.contains(where: { !$0.isMore }) {
                out.insert(CommentTree.folded(c.id))
            }
        }
        return out
    }

    /// Splices a freshly-created reply into the tree under [parentFullname]
    /// (the post's fullname → new top-level comment; else under that comment).
    func insertReply(_ parentFullname: String, _ reply: Comment) {
        edit { t in
            parentFullname == t.post.fullname
                ? withTree(t, [reply] + t.comments)
                : withTree(t, CommentTree.insertReply(t.comments, parentFullname, reply))
        }
    }

    func applyEdit(_ fullname: String, _ newBody: String) {
        edit { t in
            if fullname == t.post.fullname {
                touched = true
                return t.with { $0.post = t.post.with { $0.selftext = newBody } }
            }
            return withTree(t, CommentTree.update(t.comments, fullname) { $0.with { $0.body = newBody } })
        }
    }

    /// The post's new flair (`flair` nil: none), in the header without a refresh.
    func applyFlair(_ flair: Flair?) {
        edit { t in
            touched = true
            return t.with { $0.post = t.post.with { $0.linkFlairText = flair?.text; $0.linkFlair = flair?.label } }
        }
    }

    func updateComment(_ fullname: String, _ change: (Comment) -> Comment) {
        edit { t in withTree(t, CommentTree.update(t.comments, fullname, change)) }
    }

    func removeComment(_ fullname: String) {
        edit { t in withTree(t, CommentTree.remove(t.comments, fullname)) }
    }

    func loadMore(_ moreNode: Comment) {
        guard let s = ui.thread, !moreNode.moreChildren.isEmpty, !s.loadingMore.contains(moreNode.fullname) else { return }
        touched = true // the full page would drop this "more" row mid-load
        edit { $0.with { $0.loadingMore.insert(moreNode.fullname) } }
        let sort = currentSort // expanded replies follow the thread's sort
        Task { [weak self] in
            do {
                let flat = try await app.repository.getMoreComments(linkFullname: s.post.fullname, moreNode: moreNode, sort: sort)
                guard let self else { return }
                let current = ui.thread?.comments ?? s.comments
                let voted = app.commentVotes.apply(flat)
                let tree = await Task.detached { CommentTree.replaceMore(current, moreNode, voted) }.value
                prewarm(voted, post: s.post)
                edit { t in withTree(t, tree).with { $0.loadingMore.remove(moreNode.fullname) } }
                if let to = ui.translatedTo { translate(to) }
            } catch {
                self?.edit { $0.with { $0.loadingMore.remove(moreNode.fullname) } }
                if error is CancellationError { return }
                app.navigator.showSnackbar("Couldn't load more replies: \(friendlyError(error))")
            }
        }
    }
}

/// Reading time in a thread, counted only while it's on screen and the app is
/// in the foreground: the strongest cheap signal there is. A post read for
/// two minutes is a far stronger "more like this" than one backed out of at
/// once. Each tier is awarded at most once per visit. Also remembers the
/// previous visit (for "new comments") and records this one.
@MainActor @Observable
final class ThreadDwell {
    @ObservationIgnored private let postId: String
    /// Previous visit to this thread (millis); nil on the first.
    private(set) var since: Int?
    @ObservationIgnored var post: Post?
    @ObservationIgnored private var startedAt: Int?
    @ObservationIgnored private var accumulated = 0
    @ObservationIgnored private var awarded = Set<String>()
    @ObservationIgnored private var started = false

    init(postId: String) { self.postId = postId }

    func start() {
        if started { return }
        started = true
        // Remember the previous visit before recording this one: comments
        // posted since then are marked new.
        since = app.threadVisits.lastVisit(postId)
        app.threadVisits.record(postId)
        startedAt = nowMillis()
    }

    func resume() {
        if started, startedAt == nil { startedAt = nowMillis() }
    }

    func pause() {
        if let startedAt { accumulated += nowMillis() - startedAt }
        startedAt = nil
    }

    func learn() {
        guard let p = post else { return }
        let running = startedAt.map { nowMillis() - $0 } ?? 0
        let seconds = min(max((accumulated + running) / 1000, 0), 600)
        if seconds < 3 {
            if awarded.isEmpty, awarded.insert("bounce").inserted { app.forYou.forYouLearner.bounce(p) }
            return
        }
        // 3s+ is real engagement (opening alone isn't: it may be a bounce).
        if awarded.insert("dwell").inserted { app.forYou.forYouLearner.dwell(p) }
        if seconds >= 30, awarded.insert("read").inserted { app.forYou.forYouLearner.read(p) }
        if seconds >= 120, awarded.insert("longRead").inserted { app.forYou.forYouLearner.read(p, long: true) }
    }
}
