import SwiftUI

/// A post + threaded comments. The already-loaded Post, if any, is in NavCache under postId.
struct PostDetailScreen: View {
    let subreddit: String
    let postId: String
    let focusCommentId: String?

    @State private var vm: CommentsViewModel
    @State private var dwell: ThreadDwell
    @State private var actions: ThreadActions
    @State private var handle = ThreadListHandle()
    @State private var toolbarScroll = FabScroll()
    @State private var headerModel = PostHeaderModel()
    @State private var initialPost: Post?

    // In-post comment search. Matches by fullname, not list position:
    // collapsing or loading more replies shifts positions.
    @State private var searchOpen = false
    @State private var query = ""
    @State private var matchIds: [String] = []
    @State private var matchPos = 0
    @State private var currentMatchId: String?
    @FocusState private var searchFocused: Bool
    // A reply just posted: once it's in the list, scroll to it and highlight it for a moment.
    @State private var revealId: String?
    // Your own post's sub's post flairs: "Edit flair" only shows where there are some (#88).
    @State private var ownPostFlairs: [Flair] = []

    @Environment(\.scenePhase) private var scenePhase

    init(subreddit: String, postId: String, focusCommentId: String?) {
        self.subreddit = subreddit
        self.postId = postId
        self.focusCommentId = focusCommentId
        let vm = CommentsViewModel(subreddit: subreddit, postId: postId, focusCommentId: focusCommentId)
        _vm = State(initialValue: vm)
        _dwell = State(initialValue: ThreadDwell(postId: postId))
        _actions = State(initialValue: ThreadActions(vm: vm))
    }

    private var ui: ThreadUiState { vm.ui }
    private var thread: PostThread? { vm.shown }
    private var flat: [Comment] { thread?.flat ?? [] }
    private var username: String { app.session.username }
    private var aiKey: String? { app.post.aiKey?.nilIfEmpty }

    var body: some View {
        content
            .navigationTitle(thread?.post.subredditPrefixed ?? (subreddit == "_" ? "Post" : "r/\(subreddit)"))
            .navigationBarTitleDisplayMode(.inline)
            // The thread takes the whole screen; its floating buttons sit where the tab bar was.
            .toolbar(.hidden, for: .tabBar)
            .toolbar { toolbarItems }
            .task {
                vm.start()
                dwell.start()
                syncActions()
                await app.post.refreshAiKey()
            }
            .onAppear {
                dwell.resume()
                // Back from voting in this post's poll on Reddit: load the results.
                if app.post.pollVoteOpened == postId {
                    app.post.pollVoteOpened = nil
                    vm.refresh()
                }
                if initialPost == nil { initialPost = NavCache.get(postId) }
                dwell.post = thread?.post ?? initialPost
            }
            .onDisappear {
                // A pushed profile or subreddit covers the thread: learn from what was read so far.
                dwell.pause()
                dwell.learn()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { dwell.resume() } else { dwell.pause() }
            }
            .onChange(of: vm.revision) { _, _ in syncActions() }
            .onChange(of: revealId) { _, id in if let id { reveal(id) } }
            .task(id: thread.flatMap { !username.isEmpty && $0.post.author == username ? $0.post.subreddit : nil }) {
                if let post = thread?.post, !username.isEmpty, post.author == username {
                    ownPostFlairs = await app.repository.getLinkFlairs(post.subreddit)
                }
            }
    }

    private func syncActions() {
        actions.post = thread?.post
        actions.flat = flat
        actions.translatedComments = Set(ui.commentTranslations.keys)
        actions.reveal = { revealId = $0 }
        dwell.post = thread?.post ?? initialPost
        // A post shared to "Summarize with Ilay": its summary opens once the thread loads.
        if summarizeOnOpen == postId, let thread {
            summarizeOnOpen = nil
            Task {
                await app.post.refreshAiKey()
                showSummarySheet(thread.post, thread.flat)
            }
        }
    }

    @ViewBuilder private var content: some View {
        if let error = ui.error, !ui.loading, thread == nil {
            ErrorView(message: "Could not load this post.\n\(friendlyError(error))") { vm.refresh() }
        } else {
            let position = app.settings.value.threadFabPosition
            ZStack(alignment: position == .left ? .bottomLeading : position == .middle ? .bottom : .bottomTrailing) {
                list.ignoresSafeArea()
                    if !searchOpen, let thread {
                        let settings = app.settings.value
                        let opAuthor = thread.post.author
                        let hasOp = settings.threadJumpOp && !opAuthor.isEmpty && opAuthor != "[deleted]" && flat.contains { !$0.isMore && $0.author == opAuthor }
                        ThreadToolbar(
                            expanded: toolbarScroll.expanded,
                            position: position,
                            newCount: flat.lazy.filter { isNew($0) }.count,
                            hasOp: hasOp,
                            hasMine: settings.threadJumpMine && !username.isEmpty && flat.contains { !$0.isMore && $0.author == username },
                            hasNext: settings.threadJumpNext && !thread.comments.isEmpty,
                            hasAi: aiKey != nil,
                            onPrevNew: { jumpNext(backwards: true, match: isNew) },
                            onNextNew: { jumpNext(match: isNew) },
                            onOp: { jumpNext { $0.author == opAuthor } },
                            onPrevOp: { jumpNext(backwards: true) { $0.author == opAuthor } },
                            onMine: { jumpNext { $0.author == username } },
                            onPrevMine: { jumpNext(backwards: true) { $0.author == username } },
                            onComment: { actions.replyToPost() },
                            onSummarize: { showSummarySheet(thread.post, flat) },
                            onAsk: { showAskSheet(thread.post, flat) { revealId = $0 } },
                            onNext: { jumpNext { $0.depth == 0 } },
                            onPrev: { jumpNext(backwards: true) { $0.depth == 0 } }
                        )
                    }
                if searchOpen, thread != nil { searchBar }
                if focusCommentId != nil {
                    focusBanner.frame(maxHeight: .infinity, alignment: .top)
                }
            }
        }
    }

    private var list: some View {
        CommentListView(
            content: ThreadListContent(
                revision: vm.revision,
                post: thread?.post ?? initialPost,
                fresh: thread != nil,
                thread: thread,
                loading: ui.loading,
                since: dwell.since,
                me: username,
                currentMatchId: currentMatchId,
                translation: PostHeaderTranslate(
                    targets: ui.translateTargets, shownIn: ui.translatedTo, busy: ui.translating,
                    onPick: { [vm] in vm.translateTo($0) }
                ),
                settings: app.settings.value
            ),
            handle: handle,
            actions: actions,
            header: headerModel,
            onRefresh: { [vm] in vm.refresh() },
            refreshing: ui.refreshing,
            extraTopInset: focusCommentId != nil ? 56 : 0,
            fabScroll: toolbarScroll
        )
    }

    @ToolbarContentBuilder private var toolbarItems: some ToolbarContent {
        if let thread {
            ToolbarItem(placement: .topBarTrailing) {
                PickOneMenu(options: COMMENT_SORTS.map { (key: $0.id, label: $0.label) }, selected: vm.currentSort, onPick: { vm.changeSort($0) }) {
                    Label("Sort comments", systemImage: "arrow.up.arrow.down")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    toggleSearch()
                } label: {
                    Label("Search comments", systemImage: "magnifyingglass")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showPostActionsSheet(thread.post)
                    } label: {
                        Label("Post actions", systemImage: "ellipsis.circle")
                    }
                    if !username.isEmpty, thread.post.author == username { ownPostItems(thread.post) }
                } label: {
                    Label("More", systemImage: "ellipsis")
                } primaryAction: {
                    showPostActionsSheet(thread.post)
                }
            }
        }
    }

    /// Edit (posts with body text: self posts, and image or gallery posts that carry
    /// text too, #88), edit flair (where the sub has post flair) / delete for your own post.
    @ViewBuilder private func ownPostItems(_ post: Post) -> some View {
        if post.isSelf || !post.selftext.trimmed.isEmpty {
            Button {
                Task {
                    if let text = await showEditSheet(post.fullname, initialText: post.selftext) { vm.applyEdit(post.fullname, text) }
                }
            } label: {
                Label("Edit", systemImage: "pencil")
            }
        }
        if !ownPostFlairs.isEmpty {
            Button {
                Task {
                    let flairs = ownPostFlairs
                    // Its template by text; one with your own words, or set by a mod, matches none (no check, not "No flair").
                    let current = post.linkFlairText.map { t in flairs.first { $0.text == t } ?? Flair(id: "", text: t) }
                    guard let pick = await pickLinkFlair(post.subreddit, flairs: flairs, current: current) else { return }
                    do {
                        try await app.repository.setPostFlair(post.subreddit, postFullname: post.fullname, flair: pick.flair)
                        vm.applyFlair(pick.flair)
                        app.navigator.showSnackbar(pick.flair == nil ? "Flair removed" : "Flair set")
                    } catch {
                        app.navigator.showActionError("change the flair", error)
                    }
                }
            } label: {
                Label("Edit flair", systemImage: "tag")
            }
        }
        Button(role: .destructive) {
            Task {
                guard await confirmDelete("post") else { return }
                do {
                    try await app.repository.deleteThing(post.fullname)
                    app.navigator.pop()
                } catch {
                    app.navigator.showActionError("delete", error)
                }
            }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    /// Single-comment view (from an inbox reply / permalink): "Show all" opens the whole thread.
    private var focusBanner: some View {
        Button {
            let nav = app.navigator
            nav.pop()
            nav.push(.post(subreddit: subreddit, postId: postId))
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.turn.down.right")
                Text("Viewing a single comment thread").lineLimit(1)
                Spacer(minLength: 0)
                Text("Show all").bold().foregroundStyle(.tint)
            }
            .font(.footnote)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    /// Find in this thread, like Safari's find on page: over the keyboard.
    private var searchBar: some View {
        GlassEffectContainer {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search comments", text: $query)
                        .focused($searchFocused)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                        .onSubmit { stepMatch(1) }
                        .onChange(of: query) { _, q in runSearch(q) }
                    if !query.isBlank {
                        Text(verbatim: matchIds.isEmpty ? "0/0" : "\(matchPos + 1)/\(matchIds.count)")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .glassEffect(.regular.interactive(), in: .capsule)
                HStack(spacing: 0) {
                    Button { stepMatch(-1) } label: {
                        Image(systemName: "chevron.up").frame(width: 40, height: 44).contentShape(.rect)
                    }
                    .accessibilityLabel("Previous")
                    Button { stepMatch(1) } label: {
                        Image(systemName: "chevron.down").frame(width: 40, height: 44).contentShape(.rect)
                    }
                    .accessibilityLabel("Next")
                }
                .buttonStyle(.plain)
                .disabled(matchIds.isEmpty)
                .glassEffect(.regular.interactive(), in: .capsule)
                Button { toggleSearch() } label: {
                    Image(systemName: "xmark").frame(width: 44, height: 44).contentShape(.circle)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Close")
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .onAppear { searchFocused = true }
    }

    private func isNew(_ c: Comment) -> Bool { isNewComment(c, since: dwell.since, me: username) }

    private func scrollToMatch() {
        if matchIds.isEmpty { return }
        currentMatchId = matchIds[matchPos]
        // Resolve against the list as it is now; a match hidden inside a
        // collapsed thread has no row to scroll to.
        if let id = currentMatchId, flat.contains(where: { $0.fullname == id }) {
            // After the list has taken the highlight.
            Task { handle.scroll(to: id, fraction: 0.12) }
        }
    }

    private func runSearch(_ raw: String) {
        let q = raw.trimmed.lowercased()
        let m = q.isEmpty ? [] : flat.filter { !$0.isMore && $0.body.lowercased().contains(q) }.map(\.fullname)
        matchIds = m
        matchPos = 0
        currentMatchId = m.first
        if !m.isEmpty { scrollToMatch() }
    }

    private func stepMatch(_ delta: Int) {
        if matchIds.isEmpty { return }
        matchPos = (matchPos + delta + matchIds.count) % matchIds.count
        scrollToMatch()
    }

    private func toggleSearch() {
        searchOpen.toggle()
        if !searchOpen {
            query = ""
            matchIds = []
            currentMatchId = nil
        }
    }

    /// Scrolls to the next comment below the current top that passes [match],
    /// wrapping to the first (backwards: the one above, no wrap). False when there's none.
    @discardableResult private func jumpNext(backwards: Bool = false, match: (Comment) -> Bool) -> Bool {
        guard let target = jumpTarget(flat, topIndex: handle.topIndex, backwards: backwards, match: match), target - 1 < flat.count else { return false }
        handle.scroll(to: flat[target - 1].fullname)
        return true
    }

    private func reveal(_ id: String) {
        Task {
            // Wait for the row to appear in the list.
            for _ in 0..<20 where !flat.contains(where: { $0.fullname == id }) {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard flat.contains(where: { $0.fullname == id }) else {
                revealId = nil
                return
            }
            currentMatchId = id
            try? await Task.sleep(for: .milliseconds(50))
            handle.scroll(to: id, fraction: 0.25)
            try? await Task.sleep(for: .milliseconds(1800))
            if currentMatchId == id, !searchOpen { currentMatchId = nil }
            revealId = nil
        }
    }
}

/// One row: [↑ N new ↓] [OP] [your comment] [summarize] [ask] [next top-level] [new comment].
/// The OP and your-comments buttons step forward on a tap and back on a long-press, as
/// does the next button (#126). When the row doesn't fit (the stepper showing), they
/// drop out first. Scrolling down folds it to the new-comment button, out of the way of
/// what you're reading; scrolling up brings the rest back. Settings place it left,
/// middle or right and turn the jump buttons off.
private struct ThreadToolbar: View {
    let expanded: Bool
    let position: ThreadFabPosition
    let newCount: Int
    let hasOp: Bool
    let hasMine: Bool
    let hasNext: Bool
    let hasAi: Bool
    let onPrevNew: () -> Void
    let onNextNew: () -> Void
    let onOp: () -> Void
    let onPrevOp: () -> Void
    let onMine: () -> Void
    let onPrevMine: () -> Void
    let onComment: () -> Void
    let onSummarize: () -> Void
    let onAsk: () -> Void
    let onNext: () -> Void
    let onPrev: () -> Void

    private let size: CGFloat = 48

    var body: some View {
        let anchor: UnitPoint = position == .left ? .leading : position == .middle ? .center : .trailing
        GlassEffectContainer(spacing: 10) {
            ViewThatFits(in: .horizontal) {
                row(jumps: true, anchor: anchor)
                row(jumps: false, anchor: anchor)
            }
        }
        .animation(.smooth(duration: 0.25), value: expanded)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func row(jumps: Bool, anchor: UnitPoint) -> some View {
        HStack(spacing: 8) {
            if expanded {
                Group {
                    if newCount > 0 { stepper }
                    if jumps || newCount == 0 {
                        if hasOp { stepButton("person.wave.2.fill", "OP's comments", onOp, back: onPrevOp) }
                        if hasMine { stepButton("person.fill", "Your comments", onMine, back: onPrevMine) }
                    }
                    if hasAi {
                        secondary("sparkles", "Summarize thread", onSummarize)
                        secondary("bubble.left.and.text.bubble.right", "Ask about this thread", onAsk)
                    }
                    if hasNext { nextButton }
                }
                .transition(.scale(scale: 0.6, anchor: anchor).combined(with: .opacity))
            }
            newComment
        }
        .fixedSize()
    }

    private func secondary(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(label)
    }

    /// Tap: the next one; long-press: the previous one.
    private func stepButton(_ symbol: String, _ label: String, _ forward: @escaping () -> Void, back: @escaping () -> Void) -> some View {
        Image(systemName: symbol)
            .frame(width: size, height: size)
            .contentShape(.circle)
            .onTapGesture(perform: forward)
            .onLongPressGesture {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                back()
            }
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { forward() }
            .accessibilityAction(named: "Previous") { back() }
    }

    /// The new-comments stepper, on its own segment.
    private var stepper: some View {
        HStack(spacing: 0) {
            Button(action: onPrevNew) {
                Image(systemName: "chevron.up").frame(width: 36, height: size).contentShape(.rect)
            }
            .accessibilityLabel("Previous new comment")
            Text(verbatim: "\(newCount) new").font(.caption.bold()).lineLimit(1).fixedSize()
            Button(action: onNextNew) {
                Image(systemName: "chevron.down").frame(width: 36, height: size).contentShape(.rect)
            }
            .accessibilityLabel("Next new comment")
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    /// Next top-level comment; long-press for the previous one.
    private var nextButton: some View {
        Image(systemName: "chevron.down")
            .fontWeight(.semibold)
            .frame(width: size, height: size)
            .contentShape(.circle)
            .onTapGesture(perform: onNext)
            .onLongPressGesture {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onPrev()
            }
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityElement()
            .accessibilityLabel("Next top-level comment")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onNext() }
            .accessibilityAction(named: "Previous top-level comment") { onPrev() }
    }

    private var newComment: some View {
        Button(action: onComment) {
            Image(systemName: "plus.bubble.fill").frame(width: 34, height: 34)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .accessibilityLabel("New comment")
    }
}
