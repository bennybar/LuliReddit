import SwiftUI

let SEARCH_SORTS: [(key: String, label: String)] = [
    ("relevance", "Relevance"), ("hot", "Hot"), ("top", "Top"), ("new", "New"), ("comments", "Comments"),
]
let SEARCH_TIMES: [(key: String, label: String)] = [
    ("hour", "Hour"), ("day", "Day"), ("week", "Week"), ("month", "Month"), ("year", "Year"), ("all", "All time"),
]

/// Where results come from: Reddit, or a test's stand-in.
struct SearchFetcher {
    let posts: (_ query: String, _ subreddit: String?, _ after: String?, _ sort: String, _ time: String) async throws -> Listing<Post>
    let subreddits: (String) async throws -> [Subreddit]
    let users: (String) async throws -> [RedditUser]

    @MainActor static var reddit: SearchFetcher {
        let repo = app.repository
        return SearchFetcher(
            posts: {
                var page = try await repo.searchPosts($0, subreddit: $1, after: $2, sort: $3, time: $4)
                // "Hide NSFW posts" (Content filters) applies to results too (#94).
                if await MainActor.run(body: { app.contentFilters.value.hideNsfw }) { page.items = page.items.filter { !$0.over18 } }
                return page
            },
            subreddits: { try await repo.searchSubreddits($0) },
            users: { try await repo.searchUsers($0) }
        )
    }
}

@MainActor @Observable final class SearchViewModel {
    private static let legacyRecentKey = "recent_searches"

    private(set) var query = ""
    private(set) var sort = "relevance"
    private(set) var time = "all"
    /// The search on screen's posts, a new list per search: nothing of an old search's
    /// requests (first page or "more") can land on it, nor its paging state block it.
    private(set) var posts: PagedSource<Post>?
    private(set) var subs: [Subreddit] = []
    private(set) var users: [RedditUser] = []
    private(set) var recent: [String]
    // The Subreddits / Users tabs fail on their own (Reddit refuses some of
    // these searches with a 403); the other tabs keep their results.
    private(set) var subsError: Error?
    private(set) var usersError: Error?

    /// Shown instead of a misleading "No results".
    var error: Error? { posts?.state.error }
    var loading: Bool { posts?.state.loading == true }

    @ObservationIgnored private let subreddit: String?
    @ObservationIgnored private let prefs: Prefs
    @ObservationIgnored private let fetcher: SearchFetcher
    @ObservationIgnored private let trackHistory: () -> Bool
    // Bumped per search: a slow earlier search (e.g. before a sort change) must
    // not overwrite the results of a newer one.
    @ObservationIgnored private var request = 0
    // Per account, like the rest of the on-device history.
    @ObservationIgnored private let recentKey: String

    init(
        subreddit: String?,
        prefs: Prefs? = nil,
        username: String? = nil,
        fetcher: SearchFetcher? = nil,
        trackHistory: (() -> Bool)? = nil
    ) {
        let prefs = prefs ?? app.prefs
        self.subreddit = subreddit
        self.prefs = prefs
        self.fetcher = fetcher ?? .reddit
        self.trackHistory = trackHistory ?? { app.settings.value.trackHistory }
        let user = (username ?? app.session.username).lowercased()
        let legacy = SearchViewModel.legacyRecentKey
        let key = user.isEmpty ? legacy : "\(legacy)_\(user)"
        if key != legacy && !prefs.contains(key) && prefs.contains(legacy) {
            prefs.setStringList(key, prefs.getStringList(legacy) ?? [])
            prefs.remove(legacy)
        }
        recentKey = key
        recent = prefs.getStringList(key) ?? []
    }

    private func saveRecent(_ q: String) {
        // Recent searches are history: none kept while tracking is off.
        if !trackHistory() { return }
        let list = Array(([q] + recent.filter { $0 != q }).prefix(12))
        prefs.setStringList(recentKey, list)
        recent = list
    }

    func removeRecent(_ entry: String) {
        recent.removeAll { $0 == entry }
        prefs.setStringList(recentKey, recent)
    }

    /// A community or user opened from the results (#149): it takes the place of the
    /// search that found it in Recent, with its picture.
    func rememberOpened(kind: String, name: String, icon: String?) {
        if !trackHistory() { return }
        let rest = recent.filter { e in
            let r = RecentSearch(e)
            return e != query && (r.kind != kind || r.name.lowercased() != name.lowercased())
        }
        let list = Array(([RecentSearch.result(kind: kind, name: name, icon: icon)] + rest).prefix(12))
        prefs.setStringList(recentKey, list)
        recent = list
    }

    func clearRecent() {
        prefs.remove(recentKey)
        recent = []
    }

    func clear() {
        request += 1
        query = ""
        posts = nil
        subs = []
        users = []
        subsError = nil
        usersError = nil
    }

    /// Sort and time for the next search, without running one (a saved search sets both).
    func setFilters(sort: String, time: String) {
        self.sort = sort
        self.time = time
    }

    func setSort(_ sort: String) {
        self.sort = sort
        search(query, saveRecent: false)
    }

    func setTime(_ time: String) {
        self.time = time
        search(query, saveRecent: false)
    }

    func search(_ raw: String, saveRecent save: Bool = true) {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return }
        if save { saveRecent(q) }
        request += 1
        let req = request
        query = q
        subsError = nil
        usersError = nil
        let (sort, time, subreddit, fetcher) = (sort, time, subreddit, fetcher)
        let source = PagedSource<Post> { [weak self] after in
            if let after { return try await fetcher.posts(q, subreddit, after, sort, time) }
            // The first page (and each pull to refresh) brings all three tabs. A failed
            // Subreddits or Users request stays on its tab; a failed posts one is the screen's.
            async let first = fetcher.posts(q, subreddit, nil, sort, time)
            async let foundSubs = attempt(restricted: subreddit != nil) { try await fetcher.subreddits(q) }
            async let foundUsers = attempt(restricted: subreddit != nil) { try await fetcher.users(q) }
            let (page, sr, us) = try await (first, foundSubs, foundUsers)
            if let self, req == self.request {
                self.subs = (try? sr.get()) ?? []
                self.subsError = sr.failure
                self.users = (try? us.get()) ?? []
                self.usersError = us.failure
            }
            return page
        }
        posts = source
        source.start()
    }

    /// Runs the current search again; returns when it's done.
    func refresh() async {
        await posts?.load().value
    }
}

private func attempt<T>(restricted: Bool, _ f: () async throws -> [T]) async -> Result<[T], Error> {
    if restricted { return .success([]) }
    do { return .success(try await f()) } catch { return .failure(error) }
}

private extension Result {
    var failure: Failure? {
        if case let .failure(e) = self { e } else { nil }
    }
}

/// Search: posts, subreddits and users, or (`subreddit`) one subreddit's posts.
struct SearchScreen: View {
    let subreddit: String?
    let initialQuery: String
    let initialSort: String?
    let initialTime: String?

    @State private var vm: SearchViewModel
    @State private var text: String
    @State private var tab = "Posts"
    @FocusState private var focused: Bool

    init(subreddit: String?, query: String?, sort: String? = nil, time: String? = nil) {
        self.subreddit = subreddit
        let initial = (query ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        initialQuery = initial
        initialSort = sort
        initialTime = time
        _vm = State(initialValue: SearchViewModel(subreddit: subreddit))
        _text = State(initialValue: initial)
    }

    private var restricted: Bool { subreddit != nil }

    private func doSearch(_ q: String, save: Bool = true) {
        let t = q.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return }
        if text != t { text = t }
        focused = false
        vm.search(t, saveRecent: save)
    }

    /// A saved search here (same scope) runs in place; another subreddit's opens its own search.
    private func runSaved(_ s: SavedSearch) {
        if s.subreddit?.lowercased() == subreddit?.lowercased() {
            vm.setFilters(sort: s.sort, time: s.time)
            doSearch(s.query, save: false)
        } else {
            app.navigator.push(.search(subreddit: s.subreddit, query: s.query, sort: s.sort, time: s.time))
        }
    }

    var body: some View {
        let current = SavedSearch(query: vm.query, subreddit: subreddit, sort: vm.sort, time: vm.time)
        let isSaved = !vm.query.isEmpty && app.savedSearches.contains(current)

        Group {
            if let error = vm.error {
                ErrorView(message: error, onRetry: { vm.search(vm.query, saveRecent: false) })
            } else if vm.query.isEmpty {
                EmptySearch(vm: vm, onPick: { doSearch($0) }, onRerun: { doSearch($0, save: false) }, onSaved: runSaved)
            } else {
                results
            }
        }
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: restricted ? "Search in r/\(subreddit ?? "")" : "Search Reddit")
        .searchFocused($focused)
        .onSubmit(of: .search) { doSearch(text) }
        // The field's ✕ (and Cancel): back to saved and recent searches.
        .onChange(of: text) { _, new in
            if new.isEmpty && !vm.query.isEmpty { vm.clear() }
        }
        .toolbar {
            // Save this search (with its sort and time) to run again from here.
            if !vm.query.isEmpty && vm.query == text.trimmingCharacters(in: .whitespacesAndNewlines) {
                ToolbarItem(placement: .topBarTrailing) {
                    ToggleIcon(
                        checked: isSaved,
                        onCheckedChange: { _ in
                            if isSaved {
                                app.savedSearches.remove(current)
                            } else {
                                app.savedSearches.add(current)
                                app.navigator.showSnackbar("Search saved: it's listed here before you type")
                            }
                        },
                        on: "bookmark.fill", off: "bookmark", description: isSaved ? "Remove saved search" : "Save search"
                    )
                }
            }
        }
        .task {
            app.savedSearches.refresh()
            if vm.query.isEmpty {
                if initialSort != nil || initialTime != nil {
                    vm.setFilters(sort: initialSort ?? vm.sort, time: initialTime ?? vm.time)
                }
                if initialQuery.isEmpty { focused = true } else { doSearch(initialQuery) }
            }
        }
    }

    private var results: some View {
        VStack(spacing: 0) {
            if !restricted {
                ConnectedChoice(options: ["Posts", "Subreddits", "Users"].map { (key: $0, label: $0) }, selected: tab, onSelect: { tab = $0 })
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }
            switch tab {
            case "Posts":
                // The chips stay through a search (#58), so the new pick can be seen landing.
                filterBar
                if let source = vm.posts {
                    PagedList(
                        source: source,
                        itemKey: { AnyHashable($0.id) },
                        emptyLabel: "No Results for “\(vm.query)”",
                        emptySymbol: "magnifyingglass",
                        contentType: pagedPostKind,
                        staleAfterMillis: .max, // Only a pull reloads a search.
                        posts: PagedPostRows(post: { $0 })
                    ) { PagedPostRow(post: $0) }
                    .background(PagedListHook(generation: source.state.items.count))
                }
            case "Subreddits":
                // "Hide NSFW posts" (Content filters) keeps NSFW communities out too (#94).
                let subs = app.contentFilters.value.hideNsfw ? vm.subs.filter { !$0.over18 } : vm.subs
                tabResults(error: vm.subsError, empty: subs.isEmpty) {
                    ForEach(subs, id: \.name) { s in
                        ResultRow(name: s.name, iconUrl: s.iconUrl, title: s.namePrefixed, subtitle: "\(compactNumber(s.subscribers)) members", route: .subreddit(name: s.name)) {
                            vm.rememberOpened(kind: "r", name: s.name, icon: s.iconUrl)
                        }
                    }
                }
            default:
                tabResults(error: vm.usersError, empty: vm.users.isEmpty) {
                    ForEach(vm.users, id: \.name) { u in
                        ResultRow(name: u.name, iconUrl: u.iconUrl, title: "u/\(u.name)", subtitle: "\(compactNumber(u.linkKarma + u.commentKarma)) karma", route: .user(username: u.name)) {
                            vm.rememberOpened(kind: "u", name: u.name, icon: u.iconUrl)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func tabResults(error: Error?, empty: Bool, @ViewBuilder rows: () -> some View) -> some View {
        if vm.loading {
            Loading().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error {
            ErrorView(message: error, onRetry: { vm.search(vm.query, saveRecent: false) })
        } else {
            List { rows() }
                .listStyle(.plain)
                .refreshable { await vm.refresh() }
                .overlay {
                    if empty { ContentUnavailableView.search(text: vm.query) }
                }
        }
    }

    /// The sort as one button that opens the list, Top with its time range, like the feed's.
    private var filterBar: some View {
        let label = SEARCH_SORTS.first { $0.key == vm.sort }?.label ?? vm.sort
        let name = vm.sort == "top" ? "\(label) · \(SEARCH_TIMES.first { $0.key == vm.time }?.label ?? "All time")" : label
        return Menu {
            ForEach(SEARCH_SORTS, id: \.key) { sort in
                let on = sort.key == vm.sort
                if sort.key == "top" {
                    Menu {
                        ForEach(SEARCH_TIMES, id: \.key) { t in
                            Button {
                                // One search for the pair, not one per setter.
                                vm.setFilters(sort: "top", time: t.key)
                                vm.search(vm.query, saveRecent: false)
                            } label: {
                                if on && t.key == vm.time { Label(t.label, systemImage: "checkmark") } else { Text(t.label) }
                            }
                        }
                    } label: {
                        if on { Label(sort.label, systemImage: "checkmark") } else { Text(sort.label) }
                    }
                } else {
                    Button {
                        if !on { vm.setSort(sort.key) }
                    } label: {
                        if on { Label(sort.label, systemImage: "checkmark") } else { Text(sort.label) }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.arrow.down")
                Text(name).lineLimit(1).fixedSize()
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        // A menu's label takes the app tint; the sort stays in the label colour.
        .tint(.primary)
        .accessibilityLabel("Sort")
        .accessibilityValue(name)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

/// A Recent entry: what you searched for (`kind` nil), or a community ("r") or user
/// ("u") you opened from the results (#149), stored as a little JSON object in the
/// same list (the same as Android).
struct RecentSearch {
    let kind: String?
    let name: String
    let icon: String?

    init(_ raw: String) {
        if raw.hasPrefix("{"), let j = parseJsonOrNull(raw), let kind = j["t"].str(), let name = j["n"].str() {
            self.kind = kind
            self.name = name
            icon = j["i"].str()
        } else {
            kind = nil
            name = raw
            icon = nil
        }
    }

    var label: String { kind == "u" ? "u/\(name)" : "r/\(name)" }
    var route: Route { kind == "u" ? .user(username: name) : .subreddit(name: name) }

    static func result(kind: String, name: String, icon: String?) -> String {
        var o: JsonObject = ["t": .string(kind), "n": .string(name)]
        if let icon { o["i"] = .string(icon) }
        return JsonElement.object(o).encoded()
    }
}

private struct ResultRow: View {
    let name: String
    let iconUrl: String?
    let title: String
    let subtitle: String
    let route: Route
    let onOpen: () -> Void

    var body: some View {
        Button {
            onOpen()
            app.navigator.push(route)
        } label: {
            HStack(spacing: 12) {
                LetterAvatar(name: name, size: 40, imageUrl: iconUrl)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).lineLimit(1).foregroundStyle(.primary)
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// Before a search: your saved searches and recent ones.
private struct EmptySearch: View {
    let vm: SearchViewModel
    let onPick: (String) -> Void
    let onRerun: (String) -> Void
    let onSaved: (SavedSearch) -> Void

    var body: some View {
        let saved = app.savedSearches.items
        if vm.recent.isEmpty && saved.isEmpty {
            ContentUnavailableView("Search posts, subreddits and users", systemImage: "magnifyingglass")
        } else {
            List {
                if !saved.isEmpty {
                    Section("Saved") {
                        ForEach(saved, id: \.key) { s in
                            HStack(spacing: 12) {
                                Button { onSaved(s) } label: {
                                    Label {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(s.query).foregroundStyle(.primary)
                                            Text(savedSubtitle(s)).font(.footnote).foregroundStyle(.secondary)
                                        }
                                    } icon: {
                                        Image(systemName: "bookmark.fill").foregroundStyle(.tint)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                                Button("Remove saved search", systemImage: "xmark") { app.savedSearches.remove(s) }
                                    .labelStyle(.iconOnly)
                                    .buttonStyle(.borderless)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if !vm.recent.isEmpty {
                    Section {
                        // Swipe or long-press one to remove it (#149).
                        ForEach(vm.recent, id: \.self) { e in
                            let r = RecentSearch(e)
                            Group {
                                if r.kind == nil {
                                    HStack(spacing: 12) {
                                        Button { onPick(r.name) } label: {
                                            Label(r.name, systemImage: "clock.arrow.circlepath")
                                                .foregroundStyle(.primary)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .contentShape(.rect)
                                        }
                                        .buttonStyle(.plain)
                                        Button("Search again", systemImage: "arrow.up.left") { onRerun(r.name) }
                                            .labelStyle(.iconOnly)
                                            .buttonStyle(.borderless)
                                            .foregroundStyle(.secondary)
                                    }
                                } else {
                                    Button {
                                        vm.rememberOpened(kind: r.kind!, name: r.name, icon: r.icon)
                                        app.navigator.push(r.route)
                                    } label: {
                                        HStack(spacing: 12) {
                                            LetterAvatar(name: r.name, size: 28, imageUrl: r.icon)
                                            Text(r.label).foregroundStyle(.primary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(.rect)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .swipeActions { Button("Remove", systemImage: "trash", role: .destructive) { vm.removeRecent(e) } }
                            .contextMenu { Button("Remove", systemImage: "trash", role: .destructive) { vm.removeRecent(e) } }
                        }
                    } header: {
                        HStack {
                            Text("Recent")
                            Spacer()
                            Button("Clear", action: vm.clearRecent).font(.subheadline).textCase(nil)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.immediately)
        }
    }

    private func savedSubtitle(_ s: SavedSearch) -> String {
        [
            s.subreddit.map { "in r/\($0)" } ?? "all of Reddit",
            SEARCH_SORTS.first { $0.key == s.sort }?.label ?? s.sort,
            s.sort == "top" ? (SEARCH_TIMES.first { $0.key == s.time }?.label ?? s.time) : nil,
        ].compactMap { $0 }.joined(separator: " · ")
    }
}
