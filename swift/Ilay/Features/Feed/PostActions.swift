import UIKit

/// The actions behind a card. Network calls run in their own task, so a vote still
/// completes (or rolls back) if the card scrolls away mid-request.
@MainActor struct PostActions {
    let post: Post

    private var nav: AppNavigator { app.navigator }
    private var learner: FeedLearner? { app.feed.engines?.learner }
    // Vote / score / saved / comment-count live in the shared post-overrides store
    // (keyed by post id) so the card stays in sync with the post-detail screen and
    // survives scrolling.
    private var ov: PostOverride { app.postOverrides.effective(post) }

    func vote(_ dir: Int) {
        let (post, nav, learner) = (post, nav, learner)
        let overrides = app.postOverrides
        let current = PostOverrides.dirOf(ov.likes)
        let target = current == dir ? 0 : dir
        overrides.setVote(post, targetDir: target)
        learner?.vote(post, from: current, to: target)
        Task {
            do {
                try await app.repository.vote(post.fullname, dir: target)
            } catch {
                overrides.setVote(post, targetDir: current) // revert
                learner?.vote(post, from: target, to: current)
                nav.showActionError("vote", error)
            }
        }
    }

    func toggleSave() {
        let (post, nav, learner) = (post, nav, learner)
        let overrides = app.postOverrides
        let next = !ov.saved
        overrides.setSaved(post, saved: next)
        learner?.save(post, saved: next)
        if next { PostReminders.offer(post) } else { PostReminders.cancel(post.id) }
        Task {
            do {
                try await app.repository.setSaved(post.fullname, saved: next)
            } catch {
                overrides.setSaved(post, saved: !next)
                learner?.save(post, saved: !next)
                nav.showActionError(next ? "save" : "unsave", error)
            }
        }
    }

    func openDetail() {
        Analytics.postOpened()
        if app.settings.value.trackHistory { app.history.markViewed(post) }
        learner?.open(post)
        nav.openPost(post)
    }

    func openMedia() {
        let p = post
        // Viewing media is engagement too (slightly stronger than a plain open).
        if p.type != .selfPost { learner?.viewMedia(p) }
        switch p.type {
        case .image: nav.openImage(p.previewUrl ?? p.url, title: p.title)
        // Play reddit's mp4 variant (small, loops); else the animated .gif.
        case .gif:
            if let mp4 = p.gifMp4Url {
                nav.openVideo(mp4, title: p.title, downloadUrl: mp4, externalUrl: p.url, gif: true)
            } else {
                nav.openImage(p.url, title: p.title)
            }
        case .gallery: nav.openGallery(p.gallery, title: p.title)
        case .video: nav.openPostVideo(p)
        // A link to a Reddit post (e.g. a crosspost whose original didn't load) opens in Ilay.
        // A share link (`Post.shareLink`) whose original didn't load is resolved on tap.
        case .link:
            if p.shareLink { nav.openLink(p.url) } else if let route = redditPostRoute(p.url) { nav.push(route) } else { nav.openInBrowser(p.url) }
        case .selfPost: openDetail()
        }
    }

    func openSubreddit() { nav.openSubreddit(post.subreddit) }

    func openAuthor() {
        let a = post.author
        if !a.isEmpty && a != "[deleted]" { nav.openUser(a) }
    }

    /// Long-press → "Tune For You": why it's here, and explicit More/Less.
    func tune() { app.feed.engines?.showTuneSheet(post) }

    func more() { showPostActionsSheet(post) }

    func toggleRead(seen: Bool) {
        if seen { app.history.removeViewed(post.id) } else { app.history.markViewed(post) }
    }

    func reply() {
        let post = post
        Task {
            if await showReplySheet(post.fullname, parentDepth: -1, post: post) != nil {
                app.postOverrides.bumpComments(post, delta: 1)
            }
        }
    }

    func hide() {
        let post = post
        Task { await hidePost(post) }
    }

    func share() {
        // Sharing is a strong interest signal (as in the ⋮ sheet).
        learner?.share(post)
        nav.share("https://reddit.com\(post.permalink)", subject: post.title)
    }

    /// The image(s) / video themselves, downloaded, rather than a link.
    func shareMedia() {
        learner?.share(post)
        shareAsMedia(post)
    }

    /// Removes the post from Home / For You for a day (local only), with Undo.
    func dismiss() {
        let (post, learner) = (post, learner)
        app.dismissedPosts.add(post.id)
        learner?.dismiss(post, undo: false)
        nav.showSnackbar("Dismissed for today", actionLabel: "Undo") {
            app.dismissedPosts.remove(post.id)
            learner?.dismiss(post, undo: true)
        }
    }

    /// Hides the post's subreddit from the front page for 7 days (local only), with Undo.
    func hideSubFromHome() {
        let (post, learner) = (post, learner)
        let sub = post.subreddit.lowercased()
        if sub.isEmpty { return }
        app.hiddenHomeSubs.add(sub)
        learner?.hideSubreddit(post, undo: false)
        nav.showSnackbar("r/\(post.subreddit) hidden from your front page for 7 days", actionLabel: "Undo") {
            app.hiddenHomeSubs.remove(sub)
            learner?.hideSubreddit(post, undo: true)
        }
    }

    /// Adds the post's subreddit to the content filters: hidden from every feed but its own, for good, with Undo.
    func filterOutSub() {
        let (post, learner) = (post, learner)
        let sub = post.subreddit.lowercased()
        if sub.isEmpty { return }
        app.contentFilters.add("subreddit", sub)
        learner?.filterOutSubreddit(post, undo: false)
        nav.showSnackbar("r/\(post.subreddit) filtered out of your feeds", actionLabel: "Undo") {
            app.contentFilters.remove("subreddit", sub)
            learner?.filterOutSubreddit(post, undo: true)
        }
    }
}

/// A list row's swipe action (Settings → Swipe actions), as Mail's: a colored button
/// uncovered beside the row, a full swipe firing it. UIKit mirrors the sides in
/// right-to-left languages, and tells the haptic.
struct PostSwipe {
    let systemImage: String
    let color: UIColor
    let label: String
    let handler: @MainActor () -> Void

    /// What a side's setting means here, or nil if it does nothing on this feed.
    static func effective(_ action: SwipeAction, dismissible: Bool, frontpage: Bool) -> SwipeAction? {
        switch action {
        // Only Home / For You can dismiss; elsewhere this side does nothing.
        case .dismiss: dismissible ? action : nil
        case .hideSub: frontpage ? action : nil
        case .collapse, .none: nil
        default: action
        }
    }

    @MainActor static func make(_ action: SwipeAction, post: Post, dismissible: Bool, frontpage: Bool, dark: Bool) -> PostSwipe? {
        guard let action = effective(action, dismissible: dismissible, frontpage: frontpage) else { return nil }
        let a = PostActions(post: post)
        let votes = IlayTheme.voteColors(dark: dark)
        let accent = UIColor(IlayTheme.accent)
        let swipe: PostSwipe? = switch action {
        case .upvote: PostSwipe(systemImage: action.icon, color: UIColor(votes.up), label: "Upvote") { a.vote(1) }
        case .downvote: PostSwipe(systemImage: action.icon, color: UIColor(votes.down), label: "Downvote") { a.vote(-1) }
        case .save: PostSwipe(systemImage: action.icon, color: accent, label: "Save") { a.toggleSave() }
        case .reply: PostSwipe(systemImage: action.icon, color: .systemTeal, label: "Reply") { a.reply() }
        case .hide: PostSwipe(systemImage: action.icon, color: .systemRed, label: "Hide") { a.hide() }
        case .dismiss: PostSwipe(systemImage: action.icon, color: .systemGray, label: "Dismiss") { a.dismiss() }
        case .hideSub: PostSwipe(systemImage: action.icon, color: .systemOrange, label: "Hide sub") { a.hideSubFromHome() }
        case .collapse, .none: nil
        }
        return swipe
    }

    var configuration: UISwipeActionsConfiguration {
        let action = UIContextualAction(style: .normal, title: label) { _, _, done in
            MainActor.assumeIsolated { handler() }
            done(true)
        }
        action.image = UIImage(systemName: systemImage)
        action.backgroundColor = color
        return UISwipeActionsConfiguration(actions: [action])
    }
}

/// The native long-press menu of a post: the things a card and its swipes can do, in
/// addition to the ⋮ sheet (which it opens as its last row).
@MainActor func postContextMenu(_ post: Post, dismissible: Bool, frontpage: Bool) -> UIMenu {
    let a = PostActions(post: post)
    let ov = app.postOverrides.effective(post)
    let seen = app.history.contains(post.id)
    func item(_ title: String, _ symbol: String, destructive: Bool = false, _ run: @escaping @MainActor () -> Void) -> UIAction {
        UIAction(title: title, image: UIImage(systemName: symbol), attributes: destructive ? .destructive : []) { _ in
            MainActor.assumeIsolated { run() }
        }
    }
    let engage = [
        item(ov.likes == true ? "Remove upvote" : "Upvote", "arrow.up") { a.vote(1) },
        item(ov.likes == false ? "Remove downvote" : "Downvote", "arrow.down") { a.vote(-1) },
        item(ov.saved ? "Unsave" : "Save", ov.saved ? "bookmark.fill" : "bookmark") { a.toggleSave() },
        item("Reply", "arrowshape.turn.up.left") { a.reply() },
    ]

    var share = [item("Share", "square.and.arrow.up") { a.share() }]
    if canShareAsMedia(post) { share.append(item("Share as media", post.type == .video || post.type == .gif ? "film" : "photo") { a.shareMedia() }) }

    var go = [item(seen ? "Mark as unread" : "Mark as read", seen ? "circle" : "checkmark.circle") { a.toggleRead(seen: seen) }]
    go.append(item("Open \(post.subredditPrefixed.isEmpty ? "r/\(post.subreddit)" : post.subredditPrefixed)", "text.bubble") { a.openSubreddit() })
    if !post.author.isEmpty && post.author != "[deleted]" { go.append(item("Open u/\(post.author)", "person") { a.openAuthor() }) }
    if post.feedReason != nil, app.feed.engines != nil { go.append(item("Tune For You", "slider.horizontal.3") { a.tune() }) }

    var away = [item("Hide", "eye.slash", destructive: true) { a.hide() }]
    if dismissible { away.append(item("Dismiss for today", "xmark") { a.dismiss() }) }
    if frontpage { away.append(item("Hide subreddit for 7 days", "minus.circle") { a.hideSubFromHome() }) }
    away.append(item("Filter out r/\(post.subreddit)", "line.3.horizontal.decrease.circle") { a.filterOutSub() })

    var sections = [engage, share, go, away].map { UIMenu(options: .displayInline, children: $0) as UIMenuElement }
    sections.append(item("More…", "ellipsis") { a.more() })
    return UIMenu(children: sections)
}
