import SwiftUI

/// One titled group of the Explore list.
struct ExploreSection: Equatable {
    let key: String
    let title: String
    let subs: [Subreddit]
    /// Shown instead when `subs` is empty.
    var empty: String? = nil
}

/// What the Explore list shows. Filtered or sorted: one flat list. Otherwise: recently
/// visited, favorites, the users you follow, the rest.
func subscriptionSections(list: [Subreddit], query: String, favOnly: Bool, sort: String, visited: [RecentSubreddit]) -> [ExploreSection] {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if !q.isEmpty || favOnly || sort != "default" {
        // Filtered/sorted flat view.
        var working = list.filter { (q.isEmpty || $0.name.lowercased().contains(q)) && (!favOnly || $0.userHasFavorited) }
        if sort == "name" {
            working = working.sorted { $0.name.lowercased() < $1.name.lowercased() }
        } else if sort == "subscribers" {
            // Stable, as Kotlin's sortedByDescending: equal counts keep their order.
            working = working.enumerated().sorted { ($0.element.subscribers, $1.offset) > ($1.element.subscribers, $0.offset) }.map(\.element)
        }
        return [ExploreSection(key: "all", title: "\(working.count) communities", subs: working, empty: "No matches")]
    }

    // Default view: recently visited + favorites + the rest.
    let byName = Dictionary(list.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
    let recent = visited.map { byName[$0.name.lowercased()] ?? $0.asSubreddit() }
    let favs = list.filter(\.userHasFavorited)
    // The users you follow (their profiles, u_<name>) get their own section.
    let others = list.filter { !$0.userHasFavorited }
    let following = others.filter { $0.name.hasPrefix("u_") }
    let rest = others.filter { !$0.name.hasPrefix("u_") }
    var out: [ExploreSection] = []
    if !recent.isEmpty { out.append(ExploreSection(key: "recent", title: "Recently visited", subs: recent)) }
    if !favs.isEmpty { out.append(ExploreSection(key: "favs", title: "Favorites", subs: favs)) }
    if !following.isEmpty { out.append(ExploreSection(key: "following", title: "Following", subs: following)) }
    if rest.isEmpty && favs.isEmpty && following.isEmpty {
        out.append(ExploreSection(key: "subs", title: "Subscriptions", subs: [], empty: "You have no subscriptions yet"))
    } else if !rest.isEmpty {
        out.append(ExploreSection(key: "subs", title: favs.isEmpty && following.isEmpty ? "Subscriptions" : "Communities", subs: rest))
    }
    return out
}

/// The Explore tab: search, Popular and All, your custom feeds, then your communities
/// with a filter, a favorites-only switch and a sort.
struct ExploreTab: View {
    @State private var query = ""
    @State private var favOnly = false
    @State private var sort = "default" // default | name | subscribers
    /// "Recommended for you" (#157), and the ones joined from it since it loaded.
    @State private var recommended: [Subreddit] = []
    @State private var joinedNow: Set<String> = []

    var body: some View {
        let nav = app.navigator
        let vm = SubscriptionsViewModel.shared
        let anonymous = app.session.session?.anonymous == true
        // Custom feeds row (shared with the You tab), with "New feed" at the end (signed in).
        let multis = app.feed.multireddits.value ?? []
        let filtering = favOnly || sort != "default"

        ScrollViewReader { proxy in
            List {
                Section {
                    HStack(spacing: 10) {
                        destinationButton("Popular", "flame") { nav.openSubreddit("popular") }
                        // With the Posts tab on r/all (Settings), this one opens the frontpage instead.
                        if app.settings.value.postsTabAll {
                            destinationButton("Frontpage", "house") { nav.push(.frontpage) }
                        } else {
                            destinationButton("All", "globe") { nav.openSubreddit("all") }
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                .id("top")

                if !multis.isEmpty || !anonymous {
                    Section {
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(multis, id: \.path) { m in
                                    feedChip(m.displayName.nilIfEmpty ?? m.name, "rectangle.stack") {
                                        nav.push(.multireddit(username: m.owner(), name: m.name))
                                    }
                                }
                                if !anonymous {
                                    feedChip("New feed", "plus") {
                                        Task { _ = await createMulti(username: app.session.username) }
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 2)
                        }
                        .scrollIndicators(.hidden)
                        .scrollClipDisabled()
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    } header: {
                        HStack {
                            Text("Custom feeds")
                            Spacer()
                            if !anonymous {
                                Button("See all") { nav.push(.customFeeds) }
                                    .font(.subheadline)
                                    .textCase(nil)
                            }
                        }
                    }
                }

                switch vm.subs {
                case .loading:
                    Loading().frame(maxWidth: .infinity).padding(24).listRowBackground(Color.clear)
                case .error:
                    if anonymous {
                        SignInPrompt(message: "Sign in to see the communities you've joined. You can still search and open any subreddit.")
                    } else {
                        ContentUnavailableView {
                            Text("Couldn't load your communities.")
                        } actions: {
                            Button("Retry") { vm.load() }.buttonStyle(.glass)
                        }
                        .listRowBackground(Color.clear)
                    }
                case let .data(list):
                    let visits = Dictionary(app.recentSubreddits.state.map { ($0.name.lowercased(), $0.visits) }, uniquingKeysWith: { first, _ in first })
                    let joined = Set(list.map { $0.name.lowercased() })
                    let sections = subscriptionSections(list: list, query: query, favOnly: favOnly, sort: sort, visited: app.settings.value.showRecentlyVisited ? app.recentSubreddits.state : [])
                    // Right after Recently visited, in the default view only.
                    let shownRecs = sections.first?.key == "all" ? [] : recommended.filter { !joinedNow.contains($0.name.lowercased()) }
                    let recsAt = sections.firstIndex { $0.key != "recent" } ?? sections.count
                    ForEach(Array(sections.enumerated()), id: \.element.key) { i, section in
                        if i == recsAt { recommendedSection(shownRecs) }
                        Section {
                            if section.subs.isEmpty {
                                Text(section.empty ?? "").foregroundStyle(.secondary)
                            }
                            ForEach(section.subs, id: \.name) { sub in
                                // No star on ones you aren't subscribed to.
                                SubredditRow(sub: sub, starred: joined.contains(sub.name.lowercased()), visits: section.key == "recent" ? visits[sub.name.lowercased()] : nil) { toggleFavorite(sub) }
                                    .contextMenu {
                                        // Long-press: just this one out of Recently visited (#123).
                                        if section.key == "recent" {
                                            Button("Remove from Recently visited", systemImage: "minus.circle", role: .destructive) {
                                                app.recentSubreddits.remove(sub.name)
                                            }
                                        }
                                    }
                            }
                        } header: {
                            HStack {
                                Text(section.title)
                                if section.key == "recent" {
                                    Spacer()
                                    // Empties just this list; post history stays (History has its own clear).
                                    Button("Clear") { app.recentSubreddits.clear() }
                                        .font(.subheadline)
                                        .textCase(nil)
                                }
                            }
                        }
                    }
                    if recsAt == sections.count { recommendedSection(shownRecs) }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable { await vm.load(force: true).value }
            // Re-tapping the Explore tab scrolls back to top.
            .onChange(of: nav.tabReselect[1]) { withAnimation { proxy.scrollTo("top", anchor: .top) } }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Filter your communities")
        .navigationTitle("Explore")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { SideBarButton() }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Search communities & posts", systemImage: "magnifyingglass") { nav.push(.search()) }
                Menu("Filter and sort", systemImage: filtering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease") {
                    Toggle("Favorites only", systemImage: "star", isOn: $favOnly)
                    Picker("Sort", selection: $sort) {
                        Text("Default").tag("default")
                        Text("Name A–Z").tag("name")
                        Text("Most subscribers").tag("subscribers")
                    }
                    .pickerStyle(.inline)
                }
                SettingsButton()
            }
        }
        // After an account switch: that account's subscriptions and custom feeds.
        .task(id: app.feed.version) {
            vm.loadIfNeeded()
            app.feed.loadMultireddits()
        }
        // Picked on the phone from what For You learned, then each one's icon and members
        // (/api/info is refused); again whenever the subscriptions reload (a Join takes one off).
        .task(id: recommendKey) { await loadRecommended() }
    }

    private var recommendKey: String {
        if case let .data(list) = SubscriptionsViewModel.shared.subs { return "\(app.feed.version)|\(list.count)|\(app.contentFilters.value.hideNsfw)" }
        return ""
    }

    private func loadRecommended() async {
        guard case let .data(list) = SubscriptionsViewModel.shared.subs, app.session.session?.anonymous != true else { recommended = []; return }
        let names = app.forYou.recommendedCommunities(subscribed: Set(list.map { $0.name.lowercased() }))
        let hideNsfw = app.contentFilters.value.hideNsfw
        var found: [String: Subreddit] = [:]
        await withTaskGroup(of: Subreddit?.self) { group in
            for n in names { group.addTask { try? await app.repository.getSubredditAbout(n) } }
            for await s in group { if let s { found[s.name.lowercased()] = s } }
        }
        recommended = names.compactMap { found[$0] }.filter { $0.userIsSubscriber != true && !(hideNsfw && $0.over18) }
    }

    @ViewBuilder private func recommendedSection(_ subs: [Subreddit]) -> some View {
        if !subs.isEmpty {
            Section("Recommended for you") {
                ForEach(subs, id: \.name) { sub in
                    HStack(spacing: 12) {
                        NavigationLink(value: Route.subreddit(name: sub.name)) {
                            HStack(spacing: 12) {
                                LetterAvatar(name: sub.name, size: 40, imageUrl: sub.iconUrl)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(sub.namePrefixed).lineLimit(1)
                                    Text("\(compactNumber(sub.subscribers)) members").font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                        Button("Join") { join(sub) }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                    }
                }
            }
        }
    }

    private func join(_ sub: Subreddit) {
        let key = sub.name.lowercased()
        joinedNow.insert(key)
        Task {
            do {
                try await app.repository.setSubscribed(sub.name, subscribe: true)
                SubscriptionsViewModel.shared.load(force: true)
            } catch {
                joinedNow.remove(key)
                app.navigator.showActionError("join", error)
            }
        }
    }

    private func destinationButton(_ title: String, _ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage).frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 14))
    }

    private func feedChip(_ title: String, _ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage).font(.subheadline)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
    }

    /// The star toggle: favouriting reorders the list, so reload it after.
    private func toggleFavorite(_ s: Subreddit) {
        Task {
            do {
                try await app.repository.setSubredditFavorite(s.name, favorite: !s.userHasFavorited)
                SubscriptionsViewModel.shared.load()
            } catch {
                app.navigator.showActionError(s.userHasFavorited ? "unfavorite" : "favorite", error)
            }
        }
    }
}

/// A community in a list: tap to open it (a followed user is a subscription to their
/// profile, u_<name>), with the favorite star when `starred`.
private struct SubredditRow: View {
    let sub: Subreddit
    let starred: Bool
    let visits: Int?
    let onStar: () -> Void

    var body: some View {
        let isUser = sub.name.hasPrefix("u_")
        NavigationLink(value: isUser ? Route.user(username: String(sub.name.dropFirst(2))) : Route.subreddit(name: sub.name)) {
            HStack(spacing: 12) {
                LetterAvatar(name: sub.name, size: 40, imageUrl: sub.iconUrl)
                VStack(alignment: .leading, spacing: 2) {
                    Text(sub.namePrefixed).lineLimit(1)
                    // Recently visited: how often you opened it (#92).
                    Text("\(compactNumber(sub.subscribers)) \(isUser ? "followers" : "members")\(visits.map { " · \($0) \($0 == 1 ? "visit" : "visits")" } ?? "")")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if starred {
                    ToggleIcon(checked: sub.userHasFavorited, onCheckedChange: { _ in onStar() }, on: "star.fill", off: "star", description: "Favorite")
                        .buttonStyle(.borderless)
                }
            }
        }
    }
}
