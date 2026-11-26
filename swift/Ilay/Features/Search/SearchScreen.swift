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
        // A bare "author:name" (opening search from a profile) was saved before #281: not a search.
        recent = (prefs.getStringList(key) ?? []).filter { e in !splitAuthorQuery(e).1.isEmpty || !e.trimmingCharacters(in: .whitespaces).hasPrefix("author:") }
    }

    private func saveRecent(_ q: String) {
        // Recent searches are history: none kept while tracking is off.
        if !trackHistory() { return }
        // Only "From u/name" with no words of your own isn't a search to keep (#281).
        let (author, words) = splitAuthorQuery(q)
        if author != nil && words.isEmpty { return }
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
    /// A search in someone's posts ("author:name", from Profile): a "From u/name" token in
    /// the field, which holds only your own words (#271).
    @State private var authorTokens: [AuthorToken]
    @State private var tab = "Posts"
    /// Communities named like what's being typed (#190), asked once typing pauses.
    @State private var suggestions: [Subreddit] = []
    /// The page's width: the bar's field spans it (a bar item only takes what it asks for).
    @State private var width: CGFloat = 0
    /// The search button the field grows out of as the page zooms out of it (#285), on
    /// screen; nil when opened from anywhere else. `grown`: it has.
    @State private var growFrom: CGRect?
    @State private var grown: Bool
    /// On the Posts tab's Full bar the words follow a 🔍; elsewhere they're the button's middle.
    private let wordsAfterIcon: Bool

    init(subreddit: String?, query: String?, sort: String? = nil, time: String? = nil) {
        self.subreddit = subreddit
        let initial = (query ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        initialQuery = initial
        initialSort = sort
        initialTime = time
        _vm = State(initialValue: SearchViewModel(subreddit: subreddit))
        let (author, words) = splitAuthorQuery(initial)
        _text = State(initialValue: words)
        _authorTokens = State(initialValue: author.map { [AuthorToken(name: $0)] } ?? [])
        // Read as it's pushed, like `SearchZoom`: the Posts tab's or a community's button.
        let from = app.navigator.zoomsNextSearch ? app.navigator.nextSearchFrame : nil
        _growFrom = State(initialValue: from)
        _grown = State(initialValue: from == nil)
        wordsAfterIcon = subreddit == nil && app.settings.value.fullBarNewPost
    }

    private var prompt: String { restricted ? "Search in r/\(subreddit ?? "")" : "Search Reddit" }

    /// The field's width: the page's, less 16 a side.
    private var fieldWidth: CGFloat { max(0, width - 32) }

    /// The pill, in the field's space: the button it grows from, or all of it.
    private var pill: CGRect {
        guard !grown, let from = growFrom else { return CGRect(x: 0, y: 0, width: fieldWidth, height: 44) }
        return CGRect(x: from.minX - 16, y: 0, width: from.width, height: 44)
    }

    /// The 🔍 alone (Expandable) has no words: the field's fade in as it grows.
    private var fromIcon: Bool { (growFrom?.width ?? 100) < 60 }

    /// From the round search bar, the words start where they were on it and travel to the
    /// field's start (after the ←), as on Android (#285): how far right of there they start.
    private var travel: CGFloat {
        guard !grown, let from = growFrom, !fromIcon else { return 0 }
        let words = (prompt as NSString).size(withAttributes: [.font: UIFont.preferredFont(forTextStyle: .body)]).width
        let start = wordsAfterIcon ? from.minX + 34 : from.midX - words / 2
        return start - 16 - 44
    }

    private func withAuthor(_ words: String) -> String {
        let w = words.trimmingCharacters(in: .whitespacesAndNewlines)
        return [authorTokens.first.map { "author:\($0.name)" }, w.isEmpty ? nil : w].compactMap { $0 }.joined(separator: " ")
    }

    private var restricted: Bool { subreddit != nil }

    /// Runs `q`, the whole query (a recent or saved one may carry "author:").
    private func doSearch(_ q: String, save: Bool = true) {
        let t = q.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return }
        let (author, words) = splitAuthorQuery(t)
        let tokens = author.map { [AuthorToken(name: $0)] } ?? []
        if authorTokens != tokens { authorTokens = tokens }
        if text != words { text = words }
        endEditing()
        suggestions = []
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

    /// The bar's field: ←, the "From u/" tag (tap to remove), your words, ✕ and, once
    /// searched, the bookmark to save the search.
    private func field(isSaved: Bool, current: SavedSearch) -> some View {
        HStack(spacing: 4) {
            Button("Back", systemImage: "chevron.backward") {
                endEditing()
                // Back into the button as the page shrinks into it.
                if growFrom != nil { withAnimation(.snappy(duration: 0.25)) { grown = false } }
                app.navigator.pop()
            }
                .labelStyle(.iconOnly)
                .frame(width: 36, height: 36)
                .opacity(grown ? 1 : 0)
            if let token = authorTokens.first {
                Button { authorTokens = [] } label: {
                    Label("From u/\(token.name)", systemImage: "person")
                        .font(.subheadline)
                        // Its words too (a bar shows a label's icon alone).
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.secondarySystemFill), in: .capsule)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Removes it")
            }
            BarTextField(prompt: prompt, text: $text, autofocus: initialQuery.isEmpty) { doSearch(withAuthor(text)) }
            if !text.isEmpty || !authorTokens.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") {
                    text = ""
                    authorTokens = []
                    // Typing again, as the system field's ✕ did.
                    focusBarField(placeholder: prompt)
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
            }
            // Save this search (with its sort and time) to run again from here.
            if !vm.query.isEmpty && vm.query == withAuthor(text) {
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
        .padding(.leading, 4)
        .padding(.trailing, 12)
        .offset(x: travel)
        .opacity(grown || !fromIcon ? 1 : 0)
        .frame(width: fieldWidth, height: 44)
        .background(alignment: .topLeading) {
            let r = pill
            Capsule()
                .fill(Color(.tertiarySystemFill))
                .frame(width: r.width, height: r.height)
                .offset(x: r.minX, y: r.minY)
        }
        .onAppear {
            // After its first frame, at the button's size.
            if !grown { Task { withAnimation(.snappy(duration: 0.35)) { grown = true } } }
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
        // The suggestions show over the page while typing, as the system search's did.
        .overlay {
            // (Cleared once searched: the words are then the search's.)
            if !suggestions.isEmpty {
                List {
                    ForEach(suggestions, id: \.name) { s in
                        ResultRow(name: s.name, iconUrl: s.iconUrl, title: subredditName(s.namePrefixed), subtitle: "\(compactNumber(s.subscribers)) members", route: .subreddit(name: s.name)) {
                            vm.rememberOpened(kind: "r", name: s.name, icon: s.iconUrl)
                        }
                    }
                }
                // Grouped, as Recent below it is (#290).
                .listStyle(.insetGrouped)
                .background(Color(.systemGroupedBackground))
            }
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = $0 }
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        // The field spans the bar with its ← inside, as on Android (#285).
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .principal) { field(isSaved: isSaved, current: current) }
        }
        .task(id: text) {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !restricted, authorTokens.isEmpty, t.count >= 2, t != vm.query else { suggestions = []; return }
            try? await Task.sleep(for: .milliseconds(350))
            if Task.isCancelled { return }
            let hideNsfw = app.contentFilters.value.hideNsfw
            // Not once these words were searched while it was asked.
            if let found = try? await app.repository.subredditSuggestions(t), t != vm.query {
                suggestions = found.filter { !(hideNsfw && $0.over18) }
            }
        }
        // The field's ✕ (and Cancel): back to saved and recent searches.
        .onChange(of: text) { _, new in
            if new.isEmpty && authorTokens.isEmpty && !vm.query.isEmpty { vm.clear() }
        }
        // The "From u/" token removed: everyone's posts with your words, or back to the start.
        .onChange(of: authorTokens) { _, new in
            guard new.isEmpty, !vm.query.isEmpty, splitAuthorQuery(vm.query).0 != nil else { return }
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { vm.clear() } else { doSearch(text) }
        }
        .task {
            app.savedSearches.refresh()
            if vm.query.isEmpty {
                if initialSort != nil || initialTime != nil {
                    vm.setFilters(sort: initialSort ?? vm.sort, time: initialTime ?? vm.time)
                }
                if !initialQuery.isEmpty { doSearch(initialQuery) }
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
                        ResultRow(name: s.name, iconUrl: s.iconUrl, title: subredditName(s.namePrefixed), subtitle: "\(compactNumber(s.subscribers)) members", route: .subreddit(name: s.name)) {
                            vm.rememberOpened(kind: "r", name: s.name, icon: s.iconUrl)
                        }
                    }
                }
            default:
                tabResults(error: vm.usersError, empty: vm.users.isEmpty) {
                    ForEach(vm.users, id: \.name) { u in
                        ResultRow(name: u.name, iconUrl: u.iconUrl, title: userName(u.name), subtitle: "\(compactNumber(u.linkKarma + u.commentKarma)) karma", route: .user(username: u.name)) {
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

    /// The sort and, beside it, the time range: Reddit's search filters any sort by
    /// time, not only Top (#255).
    private var filterBar: some View {
        let sortName = SEARCH_SORTS.first { $0.key == vm.sort }?.label ?? vm.sort
        let timeName = SEARCH_TIMES.first { $0.key == vm.time }?.label ?? "All time"
        return HStack(spacing: 8) {
            Menu {
                ForEach(SEARCH_SORTS, id: \.key) { sort in
                    let on = sort.key == vm.sort
                    Button {
                        if !on { vm.setSort(sort.key) }
                    } label: {
                        if on { Label(sort.label, systemImage: "checkmark") } else { Text(sort.label) }
                    }
                }
            } label: {
                filterCapsule(sortName, icon: "arrow.up.arrow.down")
            }
            .accessibilityLabel("Sort")
            .accessibilityValue(sortName)
            Menu {
                ForEach(SEARCH_TIMES, id: \.key) { t in
                    let on = t.key == vm.time
                    Button {
                        if !on { vm.setTime(t.key) }
                    } label: {
                        if on { Label(t.label, systemImage: "checkmark") } else { Text(t.label) }
                    }
                }
            } label: {
                filterCapsule(timeName, icon: "clock")
            }
            .accessibilityLabel("Time")
            .accessibilityValue(timeName)
        }
        // A menu's label takes the app tint; the filters stay in the label colour.
        .tint(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private func filterCapsule(_ text: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text).lineLimit(1).fixedSize()
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .frame(minHeight: 36)
        .glassEffect(.regular.interactive(), in: .capsule)
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

    @MainActor var label: String { kind == "u" ? userName(name) : subredditName(name) }
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
                                        // A search in someone's posts: your words, and their "u/name" tag at the end (#281).
                                        let (author, words) = splitAuthorQuery(r.name)
                                        Button { onPick(r.name) } label: {
                                            HStack(spacing: 8) {
                                                Label(words, systemImage: "clock.arrow.circlepath").lineLimit(1)
                                                if let author {
                                                    Text("u/\(author)")
                                                        .font(.caption)
                                                        .lineLimit(1)
                                                        .padding(.horizontal, 10)
                                                        .padding(.vertical, 3)
                                                        .background(.tint.opacity(0.15), in: .capsule)
                                                }
                                            }
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
            s.time != "all" ? (SEARCH_TIMES.first { $0.key == s.time }?.label ?? s.time) : nil,
        ].compactMap { $0 }.joined(separator: " · ")
    }
}

/// The bar's text field. `autofocus`: the keyboard opens once it's there. A focus state
/// can't reach a field in the bar, so it's focused as UIKit's own text field.
private struct BarTextField: View {
    let prompt: String
    @Binding var text: String
    let autofocus: Bool
    let onSubmit: () -> Void

    var body: some View {
        TextField(prompt, text: $text)
            .submitLabel(.search)
            .onSubmit(onSubmit)
            .onAppear {
                guard autofocus else { return }
                Task {
                    try? await Task.sleep(for: .milliseconds(150))
                    focusBarField(placeholder: prompt)
                }
            }
    }
}

/// The "From u/name" token of a search in someone's posts (#271).
struct AuthorToken: Identifiable, Equatable {
    let name: String
    var id: String { name }
}

/// "author:name rest" → ("name", "rest"): a search in someone's posts, and your own words (#271).
func splitAuthorQuery(_ q: String) -> (String?, String) {
    guard let m = q.range(of: #"(?i)(^|\s)author:\S+"#, options: .regularExpression) else {
        return (nil, q.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    let token = q[m].trimmingCharacters(in: .whitespaces)
    let name = String(token.dropFirst("author:".count))
    let rest = (q[..<m.lowerBound] + " " + q[m.upperBound...])
        .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    return (name, rest)
}
