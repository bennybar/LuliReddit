import SwiftUI

/// Row actions for the comment list, in one object every cell shares.
@MainActor final class ThreadActions {
    let vm: CommentsViewModel
    var post: Post?
    var flat: [Comment] = []
    /// Comments translated one by one (set by the screen).
    var translatedComments: Set<String> = []
    /// Set by the screen: scroll to and briefly highlight a comment (a reply just posted).
    var reveal: (String) -> Void = { _ in }

    private var nav: AppNavigator { app.navigator }

    init(vm: CommentsViewModel) { self.vm = vm }

    func toggle(_ c: Comment) { vm.toggleCollapse(c.id) }
    func unfold(_ c: Comment) { vm.unfold(c.id) }

    func loadMore(_ c: Comment) {
        guard let p = post else { return }
        // A "more" stub with no children ids is Reddit's "continue this
        // thread": the replies are too deep to fetch here, so open that
        // branch in single-comment focus mode.
        if c.moreChildren.isEmpty, c.parentId.hasPrefix("t1_") {
            nav.openPost(p, focusCommentId: c.parentId.removePrefix("t1_"))
        } else {
            vm.loadMore(c)
        }
    }

    private func onReplied(_ parent: String, _ reply: Comment) {
        guard let p = post else { return }
        vm.insertReply(parent, reply)
        // The new comment lands at the top of the thread or under its parent:
        // often off-screen, so it looked like nothing happened. Bring it in.
        reveal(reply.fullname)
        app.postOverrides.bumpComments(p, delta: 1)
        // Commenting is the strongest engagement signal we have.
        app.forYou.forYouLearner.comment(p)
    }

    func replyToPost() {
        guard let p = post else { return }
        Task {
            if let reply = await showReplySheet(p.fullname, parentDepth: -1, post: p) { onReplied(p.fullname, reply) }
        }
    }

    func reply(_ c: Comment) {
        Task {
            if let reply = await showReplySheet(c.fullname, parentDepth: c.depth, replyingTo: c.author, post: post) { onReplied(c.fullname, reply) }
        }
    }

    func edit(_ c: Comment) {
        Task {
            if let text = await showEditSheet(c.fullname, initialText: c.body) { vm.applyEdit(c.fullname, text) }
        }
    }

    func delete(_ c: Comment) {
        Task {
            guard await confirmDelete("comment") else { return }
            do {
                try await app.repository.deleteThing(c.fullname)
                vm.removeComment(c.fullname)
            } catch {
                nav.showActionError("delete", error)
            }
        }
    }

    func vote(_ c: Comment, _ dir: Int) {
        let current = PostOverrides.dirOf(c.likes)
        let target = current == dir ? 0 : dir
        // Upvoting comments says you're into this thread's subreddit.
        if target == 1, let post { app.forYou.forYouLearner.commentUpvote(post) }
        vm.updateComment(c.fullname) { x in
            x.with {
                $0.score = x.score + target - current
                $0.likes = LocalVotes.likesOf(target)
            }
        }
        app.commentVotes.setVote(c, target: target)
        Task {
            do {
                try await app.repository.vote(c.fullname, dir: target)
            } catch {
                vm.updateComment(c.fullname) { x in
                    x.with {
                        $0.score = c.score
                        $0.likes = c.likes
                    }
                }
                app.commentVotes.setVote(c, target: current)
                nav.showActionError("vote", error)
            }
        }
    }

    func toggleSave(_ c: Comment) {
        let next = !c.saved
        vm.updateComment(c.fullname) { $0.with { $0.saved = next } }
        Task {
            do {
                try await app.repository.setSaved(c.fullname, saved: next)
            } catch {
                vm.updateComment(c.fullname) { $0.with { $0.saved = !next } }
                nav.showActionError(next ? "save" : "unsave", error)
            }
        }
    }

    func shareImage(_ c: Comment) {
        guard let p = post else { return }
        showShareCommentImage(p, CommentTree.chainTo(flat, c))
    }

    func share(_ c: Comment) { nav.share("https://reddit.com\(c.permalink)") }

    /// ⋯ → Translate / Show original on one comment.
    func translate(_ c: Comment) {
        vm.translateComment(c.fullname) { targets in
            await Overlays.alert("Translate", buttons: targets.map { (title: "Translate to \(Translate.languageName($0))", role: ButtonRole?.none, value: $0) }
                + [(title: "Cancel", role: ButtonRole?.some(.cancel), value: "")]).flatMap(\.nilIfEmpty)
        }
    }

    func block(_ c: Comment) {
        Task { await confirmBlockUser(c.author) }
    }

    func report(_ c: Comment) {
        Task { await showReportDialog(c.fullname) }
    }

    func mod(_ c: Comment, _ doneMsg: String, _ action: @escaping (RedditRepository) async throws -> Void) {
        Task {
            guard await modAction(doneMsg, action) else { return }
            if doneMsg.hasPrefix("Distinguished") {
                vm.updateComment(c.fullname) { $0.with { $0.distinguished = "moderator" } }
            } else if doneMsg.hasPrefix("Undistinguished") {
                vm.updateComment(c.fullname) { $0.with { $0.distinguished = nil } }
            }
        }
    }

    /// What a swipe on this comment does, per Settings → Swipe actions. Nil: nothing.
    func swipe(_ a: SwipeAction, _ c: Comment, _ colors: VoteColors) -> (color: UIColor, run: () -> Void)? {
        switch a {
        case .upvote: return (UIColor(colors.up), { [self] in vote(c, 1) })
        case .downvote: return (UIColor(colors.down), { [self] in vote(c, -1) })
        case .save: return (.systemBlue, { [self] in toggleSave(c) })
        case .reply: return (.systemTeal, { [self] in reply(c) })
        case .collapse: return (.systemGray, { [self] in toggle(c) })
        case .hide, .dismiss, .hideSub, .none: return nil
        }
    }

    /// The comment's menu (long press and ⋯): share-ish actions, then yours (or
    /// block), then moderator actions.
    func menu(_ c: Comment, isOwn: Bool) -> [UIMenuElement] {
        func item(_ title: String, _ image: String, destructive: Bool = false, _ run: @escaping () -> Void) -> UIAction {
            UIAction(title: title, image: UIImage(systemName: image), attributes: destructive ? .destructive : []) { _ in run() }
        }
        func group(_ children: [UIMenuElement]) -> UIMenu { UIMenu(options: .displayInline, children: children) }

        var share: [UIMenuElement] = [
            item("Reply", "arrowshape.turn.up.left") { [self] in reply(c) },
            item(c.saved ? "Unsave" : "Save", c.saved ? "bookmark.fill" : "bookmark") { [self] in toggleSave(c) },
            item("Collapse", "chevron.up.chevron.down") { [self] in toggle(c) },
        ]
        share.append(item(translatedComments.contains(c.fullname) ? "Show original" : "Translate", "translate") { [self] in translate(c) })
        var text: [UIMenuElement] = [
            item("Copy text", "doc.on.doc") { copyToClipboard(c.body) },
            // Rows aren't selectable while scrolling (a selectable paragraph is far
            // heavier to build, and swallows taps): like Mail, it opens on its own.
            item("Select text", "selection.pin.in.out") { showSelectText(c.body) },
        ]
        if !c.permalink.isEmpty { text.append(item("Share", "square.and.arrow.up") { [self] in self.share(c) }) }
        text.append(item("Share as image", "photo") { [self] in shareImage(c) })

        var groups: [UIMenuElement] = [group(share), group(text)]
        if isOwn {
            groups.append(group([
                item("Edit", "pencil") { [self] in edit(c) },
                item("Delete", "trash", destructive: true) { [self] in delete(c) },
            ]))
        } else if c.author != "[deleted]" {
            groups.append(group([
                item("Report", "flag") { [self] in report(c) },
                item("Block u/\(c.author)", "hand.raised", destructive: true) { [self] in block(c) },
            ]))
        }
        // Moderators of this community (the post says so) can act on comments too.
        if post?.canModPost == true {
            var mods: [UIMenuElement] = [
                item("Approve", "checkmark.circle") { [self] in mod(c, "Approved") { try await $0.modApprove(c.fullname) } },
                item("Remove", "nosign") { [self] in mod(c, "Removed") { try await $0.modRemove(c.fullname) } },
                item("Remove as spam", "exclamationmark.octagon") { [self] in mod(c, "Removed as spam") { try await $0.modRemove(c.fullname, spam: true) } },
            ]
            if isOwn {
                let distinguished = c.distinguished == "moderator"
                mods.append(item(distinguished ? "Undistinguish" : "Distinguish as mod", "shield") { [self] in
                    mod(c, distinguished ? "Undistinguished" : "Distinguished") { try await $0.modDistinguish(c.fullname, how: distinguished ? "no" : "yes") }
                })
            }
            groups.append(UIMenu(title: "Moderate", image: UIImage(systemName: "shield"), children: mods))
        }
        return groups
    }
}
