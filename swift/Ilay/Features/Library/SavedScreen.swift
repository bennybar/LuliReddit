import SwiftUI

/// The Saved hub's list: everything loaded so far, narrowed by the type, the search and
/// what was just unsaved. The `PagedList` shows `source`, whose rows are that narrowed
/// list; changing the filter re-applies it to what's loaded, without asking Reddit.
@MainActor @Observable final class SavedModel {
    private(set) var query = ""
    private(set) var type = "all" // all | posts | comments
    private(set) var removed: Set<String> = []

    /// What's shown.
    @ObservationIgnored private(set) lazy var source = PagedSource<SavedItem> { [unowned self] after in
        if after == nil && reapplying {
            reapplying = false
            return Listing(items: SavedModel.visible(loaded, query: query, type: type, removed: removed), after: loadedAfter)
        }
        let page = try await fetch(after)
        try Task.checkCancellation()
        loaded = after == nil ? page.items : loaded + page.items
        loadedAfter = page.after
        hasLoaded = true
        return Listing(items: SavedModel.visible(page.items, query: query, type: type, removed: removed), after: page.after)
    }

    @ObservationIgnored private let fetch: (String?) async throws -> Listing<SavedItem>
    @ObservationIgnored private var loaded: [SavedItem] = []
    @ObservationIgnored private var loadedAfter: String?
    @ObservationIgnored private var hasLoaded = false
    @ObservationIgnored private var reapplying = false

    init(fetch: @escaping (String?) async throws -> Listing<SavedItem>) { self.fetch = fetch }

    nonisolated static func visible(_ items: [SavedItem], query: String, type: String, removed: Set<String>) -> [SavedItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return items.filter { item in
            if removed.contains(item.fullname) { return false }
            switch item {
            case let .post(p): return (type == "all" || type == "posts") && (q.isEmpty || p.title.lowercased().contains(q))
            case let .comment(c): return (type == "all" || type == "comments") && (q.isEmpty || c.body.lowercased().contains(q))
            }
        }
    }

    func setQuery(_ q: String) {
        query = q
        reapply()
    }

    func setType(_ t: String) {
        type = t
        reapply()
    }

    func setRemoved(_ fullname: String, _ gone: Bool) {
        if gone { removed.insert(fullname) } else { removed.remove(fullname) }
        reapply()
    }

    /// Before the first page there's nothing to narrow: it arrives narrowed.
    private func reapply() {
        guard hasLoaded else { return }
        reapplying = true
        source.load(silent: true)
    }

    /// A type filter or unsaving can leave too few rows to scroll (or none):
    /// keep fetching, within a bound, until there's a screenful.
    func fillIfShort() {
        let s = source.state
        if s.items.count < 10 && s.hasMore && !s.loading && !s.loadingMore && loaded.count < 500 {
            source.loadMore()
        }
    }

    /// Unsaved here (swipe either way): gone from the list at once, Undo restores.
    func unsave(_ fullname: String, post: Post?) {
        setRemoved(fullname, true)
        if let post { app.postOverrides.setSaved(post, saved: false) }
        Task {
            do {
                try await app.repository.setSaved(fullname, saved: false)
                app.navigator.showSnackbar("Removed from Saved", actionLabel: "Undo") { [self] in
                    setRemoved(fullname, false)
                    if let post { app.postOverrides.setSaved(post, saved: true) }
                    Task { try? await app.repository.setSaved(fullname, saved: true) }
                }
            } catch {
                setRemoved(fullname, false)
                if let post { app.postOverrides.setSaved(post, saved: true) }
                app.navigator.showActionError("unsave", error)
            }
        }
    }
}

/// A dedicated, searchable hub for the user's Saved items, with a type filter
/// (all / posts / comments) and live text search over what's loaded.
struct SavedScreen: View {
    @State private var model: SavedModel
    @State private var query = ""

    init() {
        let username = app.session.username
        let repo = app.repository
        _model = State(initialValue: SavedModel { try await repo.getUserSaved(username, after: $0) })
    }

    var body: some View {
        let source = model.source
        let state = source.state
        let unfiltered = model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && model.type == "all"

        VStack(spacing: 0) {
            ConnectedChoice(options: [(key: "all", label: "All"), (key: "posts", label: "Posts"), (key: "comments", label: "Comments")], selected: model.type, onSelect: model.setType)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            PagedList(
                source: source,
                itemKey: { AnyHashable($0.fullname) },
                emptyLabel: unfiltered ? "Nothing saved" : "No matches",
                contentType: { $0.post.map(pagedPostKind) ?? 6 },
                staleAfterMillis: .max,
                posts: PagedPostRows(post: \.post, swipes: { [model] post in
                    let swipe = PostSwipe(systemImage: "bookmark.slash", color: UIColor(IlayTheme.accent), label: "Unsave") {
                        model.unsave(post.fullname, post: post)
                    }
                    return (swipe, swipe)
                })
            ) { item in
                switch item {
                case let .post(post): PagedPostRow(post: post)
                case let .comment(comment): SavedComment(comment: comment) { model.unsave(comment.fullname, post: nil) }
                }
            }
            .background(PagedListHook(generation: state.items.count))
        }
        .navigationTitle("Saved")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search saved")
        .onChange(of: query) { _, new in model.setQuery(new) }
        .onChange(of: "\(state.items.count)|\(state.after ?? "")|\(state.loading)|\(state.loadingMore)", initial: true) { model.fillIfShort() }
    }
}

private struct SavedComment: View {
    let comment: Comment
    let onUnsave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "text.bubble").font(.caption).foregroundStyle(.tint)
                Text("r/\(comment.subreddit) · u/\(comment.author) · \(compactNumber(comment.score))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                // A comment row has no swipe in a PagedList: this, and the long press, unsave it.
                Button("Unsave", systemImage: "bookmark.slash", action: onUnsave)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .font(.footnote)
            }
            RedditMarkdown(text: comment.body, onLinkClick: { app.navigator.openLink($0) })
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.pagedCard, in: .rect(cornerRadius: 16))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .contentShape(.rect)
        .onTapGesture { openPermalink(comment.permalink) }
        .contextMenu { Button("Unsave", systemImage: "bookmark.slash", action: onUnsave) }
    }
}
