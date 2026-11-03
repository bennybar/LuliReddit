import PhotosUI
import SwiftUI

// ---------------------------------------------------------------------------
// Shared sheet helpers
// ---------------------------------------------------------------------------

@MainActor func snack(_ msg: String) { app.navigator.showSnackbar(msg.removePrefix("Exception: ")) }

/// Copies [text] to the clipboard and confirms.
@MainActor func copyToClipboard(_ text: String) {
    UIPasteboard.general.string = text
    app.navigator.showSnackbar("Copied")
}

/// An error for display, as the Flutter build showed it: a Reddit API error
/// reads "HTTP 403 (reason)", followed by Reddit's own message when it sent one.
func errorText(_ e: Error) -> String {
    if let e = e as? RedditApiException {
        let head = e.errorDescription ?? ""
        guard let msg = e.message, !msg.isBlank else { return head }
        return msg.contains("HTTP \(e.statusCode)") ? msg : "\(head): \(msg)"
    }
    return e.localizedDescription.removePrefix("Exception: ")
}

/// A comment's raw text, selectable a word at a time, as in Mail's "Select text".
@MainActor func showSelectText(_ text: String) {
    Overlays.launch(detents: [.medium, .large]) { done in
        NavigationStack {
            SelectableText(text: text)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Select text")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", systemImage: "checkmark", action: done)
                    }
                }
        }
    }
}

private struct SelectableText: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.backgroundColor = .clear
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        view.textAlignment = .natural
        view.text = text
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {}
}

// ---------------------------------------------------------------------------
// Reply / edit composer
// ---------------------------------------------------------------------------

/// Reply composer (sheet) for a post (t3_) or comment (t1_). Supports image (inline
/// via Reddit richtext) / video (Catbox) attachments, GIFs, drafts. Returns the
/// created comment (at depth parentDepth + 1), or nil if dismissed.
///
/// `showReplySheet(parent.fullname, parentDepth: parent.depth, replyingTo: parent.author, post: post)`,
/// or for a top-level comment `showReplySheet(post.fullname, parentDepth: -1, post: post)`.
@MainActor func showReplySheet(_ parentFullname: String, parentDepth: Int, replyingTo: String? = nil, post: Post? = nil) async -> Comment? {
    // For You → Drafts: the thread it belongs to.
    var info: JsonObject?
    if let post {
        var o = JsonObject()
        o["kind"] = .string("reply")
        o["sub"] = .string(post.subreddit)
        o["post"] = .string(post.id)
        o["title"] = .string(post.title)
        if parentFullname.hasPrefix("t1_") { o["comment"] = .string(parentFullname.removePrefix("t1_")) }
        if let replyingTo { o["to"] = .string(replyingTo) }
        info = o
    }
    return await presentComposer(
        title: replyingTo.map { "Reply to u/\($0)" } ?? "Reply",
        submitLabel: "Reply",
        allowAttachments: true,
        limit: TextLimit.comment,
        draftKey: "reply_\(parentFullname)",
        draftInfo: info,
        initialText: nil
    ) { text, media in
        let repo = app.repository
        guard let media else { return try await repo.reply(parentFullname, text: text, depth: parentDepth + 1) }
        if media.isVideo {
            let url = try await uploadToCatbox(media.bytes, filename: media.filename)
            return try await repo.reply(parentFullname, text: text.isEmpty ? url : "\(text)\n\n\(url)", depth: parentDepth + 1)
        }
        return try await repo.replyWithImage(parentFullname, text: text, bytes: media.bytes, filename: media.filename, mimeType: media.mimeType, depth: parentDepth + 1)
    }
}

/// Editor for your own post/comment body. Returns the new text, or nil.
@MainActor func showEditSheet(_ thingFullname: String, initialText: String) async -> String? {
    await presentComposer(
        title: "Edit", submitLabel: "Save", allowAttachments: false,
        limit: thingFullname.hasPrefix("t3_") ? TextLimit.postBody : TextLimit.comment,
        draftKey: nil, draftInfo: nil, initialText: initialText
    ) { text, _ in
        _ = try await app.repository.editText(thingFullname, text: text)
        return text
    }
}

/// Dismissed while sending: the send still completes (as in Flutter) and its result
/// is still delivered; only the sheet goes away. So the sheet's result comes from
/// here, not from the sheet's own closing.
@MainActor private final class ComposerResult<T> {
    private var continuation: CheckedContinuation<T?, Never>?
    var sending = false
    /// Swiped away while sending.
    var dismissed = false

    init(_ continuation: CheckedContinuation<T?, Never>) { self.continuation = continuation }

    func finish(_ value: T?) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}

@MainActor private func presentComposer<T>(
    title: String,
    submitLabel: String,
    allowAttachments: Bool,
    limit: Int,
    draftKey: String?,
    draftInfo: JsonObject?,
    initialText: String?,
    onSubmit: @escaping (String, MediaAttachment?) async throws -> T
) async -> T? {
    await withCheckedContinuation { continuation in
        let result = ComposerResult<T>(continuation)
        Overlays.launch(detents: [.large]) { done in
            ComposeSheet(
                title: title, submitLabel: submitLabel, allowAttachments: allowAttachments, limit: limit,
                draftKey: draftKey, draftInfo: draftInfo, initialText: initialText,
                onSubmit: onSubmit, result: result, close: done
            )
        }
    }
}

private struct ComposeSheet<T>: View {
    let title: String
    let submitLabel: String
    let allowAttachments: Bool
    /// Reddit's length limit for this text.
    let limit: Int
    /// When set, the in-progress text is autosaved/restored under this key.
    let draftKey: String?
    let draftInfo: JsonObject?
    let initialText: String?
    let onSubmit: (String, MediaAttachment?) async throws -> T
    let result: ComposerResult<T>
    let close: () -> Void

    @State private var text = ""
    @State private var selection: TextSelection?
    @State private var busy = false
    @State private var error: String?
    @State private var media: MediaAttachment?
    // A picked file still being read: sending now would go without it.
    @State private var attaching = false
    // Preview: the text rendered as the comment will show.
    @State private var previewing = false
    @State private var loaded = false
    @State private var confirmingCancel = false

    /// Something would be lost by closing: an edit's changes, or a reply's text or
    /// attachment (the text is kept as a draft, but closing asks what to do with it).
    private var dirty: Bool {
        draftKey == nil ? text != (initialText ?? "") : !text.isBlank || media != nil
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                if previewing {
                    ScrollView {
                        RedditMarkdown(text: text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                    }
                } else {
                    // Takes pasted images and keyboard GIFs as the attachment, where attachments are allowed.
                    MediaTextEditor(
                        text: $text, selection: $selection, placeholder: "Markdown supported",
                        minLines: 3, maxLines: 10,
                        onMedia: allowAttachments ? { media = $0; error = nil } : nil,
                        focusOnAppear: true
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    Spacer(minLength: 0)
                }
                LengthCounter(text: text, limit: limit).padding(.horizontal, 16)
                if let error {
                    Text(error).font(.footnote).foregroundStyle(.red).padding(.horizontal, 16).padding(.vertical, 6)
                }
                if allowAttachments {
                    AttachmentControls(
                        media: Binding(get: { media }, set: { media = $0; error = nil }),
                        loading: $attaching,
                        onError: { error = $0 }
                    ) { gifButton }
                        .padding(.horizontal, 12)
                } else {
                    gifButton.padding(.horizontal, 12)
                }
                if !previewing {
                    Divider()
                    MarkdownToolbar(text: $text, selection: $selection).padding(.horizontal, 8)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) {
                        // While sending, closing only hides the sheet: the send still completes.
                        if dirty, !busy { confirmingCancel = true } else { close() }
                    }
                    .confirmationDialog(draftKey == nil ? "Discard your changes?" : "Keep this reply as a draft?", isPresented: $confirmingCancel, titleVisibility: .visible) {
                        Button("Discard", role: .destructive) {
                            if let draftKey { app.drafts.clear(draftKey) }
                            close()
                        }
                        // The text is already saved as you type; an attachment isn't kept.
                        if draftKey != nil { Button("Save Draft") { close() } }
                        Button("Keep Editing", role: .cancel) {}
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(previewing ? "Edit" : "Preview") { previewing.toggle() }
                        .disabled(text.isBlank && !previewing)
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: submit) {
                        if busy {
                            ProgressView()
                        } else {
                            Label(submitLabel, systemImage: "arrow.up")
                        }
                    }
                    .disabled(busy || attaching || (text.isBlank && media == nil) || redditLength(text) > limit)
                    .buttonStyle(.glassProminent)
                }
            }
        }
        // Swiping down would lose it silently: Cancel asks first. Still allowed while
        // sending (the send completes and its result is delivered).
        .interactiveDismissDisabled(dirty && !busy)
        .onChange(of: text) { old, new in
            if loaded, old != new, let draftKey { app.drafts.save(draftKey, new, info: draftInfo) }
        }
        .onAppear {
            if !loaded {
                text = initialText ?? draftKey.flatMap { app.drafts.get($0) } ?? ""
                loaded = true
            }
        }
        .onDisappear {
            // Swiped away with nothing being sent: that's the answer.
            if result.sending { result.dismissed = true } else { result.finish(nil) }
        }
    }

    private var gifButton: some View {
        Button {
            Task {
                guard let url = await showGiphyPicker() else { return }
                text = text.isEmpty ? url : "\(text)\n\(url)"
            }
        } label: {
            Label("GIF", systemImage: "photo.stack")
                .font(.subheadline)
                .frame(height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
    }

    private func submit() {
        let trimmed = text.trimmed
        if trimmed.isEmpty, media == nil { return }
        busy = true
        error = nil
        result.sending = true
        let (draftKey, media, onSubmit, result, close) = (draftKey, media, onSubmit, result, close)
        // Unstructured: closing the sheet mustn't cancel the request.
        Task { @MainActor in
            do {
                let value = try await onSubmit(trimmed, media)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                if let draftKey { app.drafts.clear(draftKey) }
                result.finish(value)
                close()
            } catch {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                if result.dismissed {
                    // Nowhere left to show it in the sheet.
                    snack(errorText(error))
                    result.finish(nil)
                } else {
                    busy = false
                    result.sending = false
                    self.error = errorText(error)
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Post overflow sheet
// ---------------------------------------------------------------------------

private struct SheetPick {
    let run: @MainActor () async -> Void
}

/// The post overflow sheet: share, save offline, hide, copy, report, block, crosspost,
/// open in browser, mod actions.
@MainActor func showPostActionsSheet(_ post: Post) {
    Task {
        // After the sheet has gone: an action may open a sheet of its own.
        let pick: SheetPick? = await Overlays.show(detents: [.medium, .large]) { done in
            PostActionsSheet(post: post) { run in done(SheetPick(run: run)) }
        }
        await pick?.run()
    }
}

private struct PostActionsSheet: View {
    let post: Post
    let pick: (@escaping @MainActor () async -> Void) -> Void

    private var link: String { "https://reddit.com\(post.permalink)" }

    var body: some View {
        let savedOffline = app.offline.contains(post.id)
        NavigationStack {
            List {
                Section {
                    item("square.and.arrow.up", "Share link") {
                        // Sharing is a strong interest signal.
                        app.forYou.forYouLearner.share(post)
                        app.navigator.share(link, subject: post.title)
                    }
                    item("text.below.photo", "Share with title", "Includes the post title above the link") {
                        app.forYou.forYouLearner.share(post)
                        app.navigator.shareWithTitle(link, post.title)
                    }
                    if canShareAsMedia(post) {
                        item("photo.on.rectangle", "Share as media", "The image or video itself, not a link") {
                            app.forYou.forYouLearner.share(post)
                            shareAsMedia(post)
                        }
                    }
                    item("doc.on.doc", "Copy text") {
                        copyToClipboard(post.isSelf && !post.selftext.isEmpty ? post.selftext : post.title)
                    }
                    item("safari", "Open in browser") { app.navigator.openInBrowser(link) }
                }
                Section {
                    item("eye.slash", "Hide") { await hidePost(post) }
                    item("checkmark.circle.badge.xmark", "Already seen elsewhere", "Mark as read and drop it from your feeds (e.g. read in the Reddit app)") {
                        alreadySeen(post)
                    }
                    if !post.subreddit.isEmpty {
                        item("minus.circle", "Hide r/\(post.subreddit) for 7 days", "From your front page: Home, For You, Best / Hot / New") {
                            hideFromHome(post)
                        }
                        item("line.3.horizontal.decrease.circle", "Filter out r/\(post.subreddit)", "From every feed, for good (Settings → Content filters)") {
                            filterOut(post)
                        }
                    }
                    // Reddit Home's own "Show fewer posts like this" (recommended posts only).
                    if app.forYou.redditHome.showFewerIds.contains(post.id) {
                        item("hand.thumbsdown", "Show fewer posts like this", "Tells Reddit, like on reddit.com") {
                            if await app.forYou.redditHome.showFewer(post) {
                                app.dismissedPosts.add(post.id)
                                snack("Reddit will show fewer posts like this")
                            } else {
                                snack("Couldn't reach Reddit Home, try again after a refresh")
                            }
                        }
                    }
                    // The Calm card has no read toggle of its own: it lives here.
                    if app.settings.value.postDisplay.isCalm {
                        let seen = app.history.contains(post.id)
                        item(seen ? "checkmark.circle.fill" : "checkmark.circle", seen ? "Mark as unread" : "Mark as read") {
                            if seen { app.history.removeViewed(post.id) } else { app.history.markViewed(post) }
                        }
                    }
                    item(
                        savedOffline ? "arrow.down.circle.fill" : "arrow.down.circle",
                        savedOffline ? "Remove offline copy" : "Save for offline",
                        savedOffline ? nil : "Keep it with its comments in Read later"
                    ) {
                        if savedOffline {
                            await app.offline.remove(post.id)
                            snack("Removed from Read later")
                        } else {
                            snack("Saving for offline…")
                            do {
                                try await app.offline.save(post)
                                snack("Saved to Read later")
                            } catch {
                                snack("Couldn't save: \(friendlyError(error))")
                            }
                        }
                    }
                }
                Section {
                    item("repeat", "Crosspost") { await showCrosspostDialog(post) }
                    if app.session.session?.anonymous == false {
                        item("text.badge.plus", "Add r/\(post.subreddit) to a custom feed") { await showAddToCustomFeed(post.subreddit) }
                    }
                    item("flag", "Report") { await showReportDialog(post.fullname) }
                    item("hand.raised", "Block u/\(post.author)", role: .destructive) { await confirmBlockUser(post.author) }
                }
                if post.canModPost {
                    Section("Moderate") {
                        item("checkmark.circle", "Approve") { _ = await modAction("Approved") { try await $0.modApprove(post.fullname) } }
                        item("nosign", "Remove") { _ = await modAction("Removed") { try await $0.modRemove(post.fullname) } }
                        item("exclamationmark.octagon", "Remove as spam") {
                            _ = await modAction("Removed as spam") { try await $0.modRemove(post.fullname, spam: true) }
                        }
                        item(post.locked ? "lock.open" : "lock", post.locked ? "Unlock" : "Lock") {
                            _ = await modAction(post.locked ? "Unlocked" : "Locked") { try await $0.modLock(post.fullname, lock: !post.locked) }
                        }
                    }
                }
                Section {
                    item("slider.horizontal.3", "Tune For You", "Why it's here · more or less like it · mute r/\(post.subreddit)") {
                        showTuneSheet(post)
                    }
                }
            }
            .navigationTitle("Post")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func item(_ symbol: String, _ title: String, _ subtitle: String? = nil, role: ButtonRole? = nil, action: @escaping @MainActor () async -> Void) -> some View {
        Button(role: role) {
            pick(action)
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: title)
                    if let subtitle { Text(verbatim: subtitle).font(.caption).foregroundStyle(.secondary) }
                }
            } icon: {
                Image(systemName: symbol)
            }
        }
        .foregroundStyle(role == .destructive ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
    }
}

/// Hides [post]'s subreddit from the front page for 7 days (local only), with Undo.
@MainActor private func hideFromHome(_ post: Post) {
    let sub = post.subreddit.lowercased()
    if sub.isEmpty { return }
    app.hiddenHomeSubs.add(sub)
    app.forYou.forYouLearner.hideSubreddit(post, undo: false)
    app.navigator.showSnackbar("r/\(post.subreddit) hidden from your front page for 7 days", actionLabel: "Undo") {
        app.hiddenHomeSubs.remove(sub)
        app.forYou.forYouLearner.hideSubreddit(post, undo: true)
    }
}

/// Adds [post]'s subreddit to the content filters: hidden from every feed but its own, for good, with Undo.
@MainActor private func filterOut(_ post: Post) {
    let sub = post.subreddit.lowercased()
    if sub.isEmpty { return }
    app.contentFilters.add("subreddit", sub)
    app.forYou.forYouLearner.filterOutSubreddit(post, undo: false)
    app.navigator.showSnackbar("r/\(post.subreddit) filtered out of your feeds", actionLabel: "Undo") {
        app.contentFilters.remove("subreddit", sub)
        app.forYou.forYouLearner.filterOutSubreddit(post, undo: true)
    }
}

/// Runs a moderator action and reports the outcome. True when it went through.
@MainActor func modAction(_ doneMsg: String, _ action: (RedditRepository) async throws -> Void) async -> Bool {
    do {
        try await action(app.repository)
        snack(doneMsg)
        return true
    } catch let e as RedditApiException {
        snack(e.statusCode == 403
            ? "Reddit refused that. If you moderate this community, sign out and back in so Ilay can request moderator permission."
            : friendlyError(e))
    } catch {
        snack(friendlyError(error))
    }
    return false
}

/// "Already seen elsewhere" (read in the official app, on the web…): marks it read, so
/// For You / Blend treat it as opened and won't bring it back, and drops it from the
/// feeds on screen. Local only: Reddit isn't told.
@MainActor func alreadySeen(_ post: Post) {
    let wasRead = app.history.contains(post.id)
    app.history.markViewed(post)
    app.hiddenPosts.add(post.id)
    app.navigator.showSnackbar("Marked as seen", actionLabel: "Undo") {
        app.hiddenPosts.remove(post.id)
        if !wasRead { app.history.removeViewed(post.id) }
    }
}

/// Hides [post] on Reddit and in open feeds (app.hiddenPosts), with Undo.
@MainActor func hidePost(_ post: Post) async {
    let repo = app.repository
    app.hiddenPosts.add(post.id)
    do {
        try await repo.setHidden(post.fullname, hidden: true)
        app.forYou.forYouLearner.hidePost(post) // a clear "not for me"
        app.navigator.showSnackbar("Post hidden", actionLabel: "Undo") {
            app.hiddenPosts.remove(post.id)
            app.forYou.forYouLearner.hidePost(post, undo: true)
            Task { try? await repo.setHidden(post.fullname, hidden: false) } // best effort
        }
    } catch {
        app.hiddenPosts.remove(post.id)
        snack("Couldn't hide: \(friendlyError(error))")
    }
}

private let reportReasons = [
    "Spam",
    "Harassment or bullying",
    "Hate speech",
    "Violence or threats",
    "Misinformation",
    "Breaks subreddit rules",
]

/// Report: preset reasons or a custom one. Works for posts and comments.
@MainActor func showReportDialog(_ fullname: String) async {
    let picked: String? = await Overlays.show(detents: [.medium, .large]) { done in ReportSheet(done: done) }
    guard let reason = picked else { return }
    do {
        try await app.repository.report(fullname, reason: reason)
        snack("Reported. Thanks.")
    } catch {
        snack("Could not report: \(errorText(error))")
    }
}

private struct ReportSheet: View {
    let done: (String?) -> Void
    @State private var selected: String?
    @State private var custom = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(reportReasons, id: \.self) { r in
                        Button {
                            selected = r
                            custom = ""
                        } label: {
                            HStack {
                                Text(r).foregroundStyle(.primary)
                                Spacer()
                                if selected == r { Image(systemName: "checkmark").foregroundStyle(.tint).fontWeight(.semibold) }
                            }
                        }
                    }
                }
                Section {
                    TextField("Other reason (optional)", text: $custom)
                        .onChange(of: custom) { _, v in if !v.isEmpty { selected = nil } }
                }
            }
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) { done(nil) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Report") { done(custom.trimmed.nilIfEmpty ?? selected) }
                        .disabled(custom.isBlank && selected == nil)
                        .buttonStyle(.glassProminent)
                }
            }
        }
    }
}

private struct CrosspostTarget {
    let subreddit: String
    let title: String
}

@MainActor private func showCrosspostDialog(_ post: Post) async {
    let target: CrosspostTarget? = await Overlays.show(detents: [.medium]) { done in CrosspostSheet(post: post, done: done) }
    guard let target else { return }
    do {
        let id = try await app.repository.submitCrosspost(target.subreddit, title: target.title, crosspostFullname: post.fullname)
        app.navigator.push(.post(subreddit: target.subreddit, postId: id))
    } catch {
        snack("Crosspost failed: \(errorText(error))")
    }
}

private struct CrosspostSheet: View {
    let post: Post
    let done: (CrosspostTarget?) -> Void
    @State private var subreddit = ""
    @State private var title: String

    init(post: Post, done: @escaping (CrosspostTarget?) -> Void) {
        self.post = post
        self.done = done
        _title = State(initialValue: post.title)
    }

    private var cleanSub: String { subreddit.trimmed.removePrefix("r/") }

    var body: some View {
        NavigationStack {
            Form {
                HStack(spacing: 2) {
                    Text(verbatim: "r/").foregroundStyle(.secondary)
                    TextField("Subreddit", text: $subreddit)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                TextField("Title", text: $title, axis: .vertical).lineLimit(1...2)
            }
            .navigationTitle("Crosspost")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) { done(nil) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") { done(CrosspostTarget(subreddit: cleanSub, title: title.trimmed)) }
                        .disabled(cleanSub.isEmpty || title.isBlank)
                        .buttonStyle(.glassProminent)
                }
            }
        }
    }
}

/// Confirms and blocks a user. Reusable from posts, comments and profiles.
@MainActor func confirmBlockUser(_ username: String) async {
    if username.isEmpty || username == "[deleted]" { return }
    let ok = await Overlays.alert(
        "Block u/\(username)?",
        message: "You won't see their posts, comments, or messages anymore. You can unblock them later in Reddit settings.",
        buttons: [(title: "Block", role: ButtonRole?.some(.destructive), value: true), (title: "Cancel", role: ButtonRole?.some(.cancel), value: false)]
    )
    guard ok == true else { return }
    do {
        try await app.repository.blockUser(username)
        snack("Blocked u/\(username)")
    } catch {
        snack("Could not block: \(errorText(error))")
    }
}

/// "Delete [what]? This cannot be undone."
@MainActor func confirmDelete(_ what: String) async -> Bool {
    await Overlays.alert(
        "Delete \(what)?",
        message: "This cannot be undone.",
        buttons: [(title: "Delete", role: ButtonRole?.some(.destructive), value: true), (title: "Cancel", role: ButtonRole?.some(.cancel), value: false)]
    ) == true
}
