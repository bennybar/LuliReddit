import SwiftUI

/// One titled group of the Explore list.
struct ExploreGroup: Equatable {
    let key: String
    let title: String
    let subs: [Subreddit]
    /// Shown instead when `subs` is empty.
    var empty: String? = nil
}

/// What the Explore list shows. Filtered or sorted: one flat list. Otherwise: recently
/// visited, favorites, the users you follow, the rest. A section that's `shown` off (#161)
/// leaves its communities in the rest, so none goes missing.
func subscriptionSections(list: [Subreddit], query: String, favOnly: Bool, sort: String, visited: [RecentSubreddit],
                          shown: Set<ExploreSection> = Set(ExploreSection.allCases)) -> [ExploreGroup] {
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
        return [ExploreGroup(key: "all", title: "\(working.count) communities", subs: working, empty: "No matches")]
    }

    // Default view: recently visited + favorites + the rest.
    let byName = Dictionary(list.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
    let recent = visited.map { byName[$0.name.lowercased()] ?? $0.asSubreddit() }
    let showFavs = shown.contains(.favorites), showFollowing = shown.contains(.following)
    let favs = showFavs ? list.filter(\.userHasFavorited) : []
    // The users you follow (their profiles, u_<name>) get their own section.
    let others = list.filter { !(showFavs && $0.userHasFavorited) }
    let following = showFollowing ? others.filter { $0.name.hasPrefix("u_") } : []
    let rest = others.filter { !(showFollowing && $0.name.hasPrefix("u_")) }
    var out: [ExploreGroup] = []
    if !recent.isEmpty { out.append(ExploreGroup(key: "recent", title: "Recently visited", subs: recent)) }
    if !favs.isEmpty { out.append(ExploreGroup(key: "favs", title: "Favorites", subs: favs)) }
    if !following.isEmpty { out.append(ExploreGroup(key: "following", title: "Following", subs: following)) }
    if rest.isEmpty && favs.isEmpty && following.isEmpty {
        out.append(ExploreGroup(key: "subs", title: "Subscriptions", subs: [], empty: "You have no subscriptions yet"))
    } else if !rest.isEmpty {
        out.append(ExploreGroup(key: "subs", title: favs.isEmpty && following.isEmpty ? "Subscriptions" : "Communities", subs: rest))
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
    /// "Popular communities": Reddit's list, loaded at most once a day.
    @State private var popularSubs: [Subreddit] = []
    /// Recently visited: all of it, not the first few (#162).
    @State private var recentAll = false
    /// Recommended communities' details, looked up once a session (#161).
    @MainActor private static var recommendedInfo: [String: Subreddit] = [:]

    var body: some View {
        let nav = app.navigator
        let vm = SubscriptionsViewModel.shared
        let anonymous = app.session.session?.anonymous == true
        // Custom feeds row (shared with the You tab), with "New feed" at the end (signed in).
        let multis = app.feed.multireddits.value ?? []
        let filtering = favOnly || sort != "default"
        // Settings › Appearance › Top bar, like Home's (#162): Expandable, the large title;
        // Full, a search button across the bar with the title in the list.
        let expandable = app.settings.value.topBarMode == .expandable

        ScrollViewReader { proxy in
            List {
                // The sections in Settings' order (#161); your communities stay last.
                let order = app.settings.value.exploreSections.filter(\.shown).map(\.section)
                if !expandable {
                    Text("Explore").font(.title2.bold())
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                        .id("title")
                }
                ForEach(order, id: \.self) { section in
                    switch section {
                    case .popular: popularSection
                    case .customFeeds: customFeedsSection(multis: multis, anonymous: anonymous)
                    // The ones you haven't joined, up to 10; signed out too (without Join).
                    // It steps aside while filtering, like the lists of your communities.
                    case .popularCommunities:
                        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !filtering {
                            communityCarousel("Popular communities", notJoined(popularSubs).prefix(10).map { $0 }, canJoin: !anonymous)
                                .id(section.rawValue)
                        }
                    default: communitySection(section, order: order)
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
                case .data:
                    // Your communities; while filtering, the results (unless a list section showed them).
                    if let g = groups(order).first(where: { $0.key == "subs" || ($0.key == "all" && !order.contains(where: \.isCommunityList)) }) {
                        groupSection(g).id("subs")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable { await vm.load(force: true).value }
            // Re-tapping the Explore tab scrolls back to top.
            .onChange(of: nav.tabReselect[1]) { withAnimation { proxy.scrollTo(firstRowId, anchor: .top) } }
        }
        // Hides as you scroll, not a search bar there all the time (#162).
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Filter your communities")
        .navigationTitle(expandable ? "Explore" : "")
        .navigationBarTitleDisplayMode(expandable ? .large : .inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { SideBarButton() }
            if !expandable {
                ToolbarItem(placement: .principal) {
                    Button { nav.push(.search()) } label: {
                        Label("Search communities & posts", systemImage: "magnifyingglass")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.secondary)
                            .frame(width: 220)
                    }
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if expandable { Button("Search communities & posts", systemImage: "magnifyingglass") { nav.push(.search()) } }
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
        .task(id: showPopularSubs) { popularSubs = showPopularSubs ? await app.repository.getPopularSubreddits() : [] }
    }

    /// The groups of your communities for the current list, filter and sort.
    private func groups(_ order: [ExploreSection]) -> [ExploreGroup] {
        guard case let .data(list) = SubscriptionsViewModel.shared.subs else { return [] }
        return subscriptionSections(list: list, query: query, favOnly: favOnly, sort: sort,
                                    visited: app.settings.value.showRecentlyVisited ? app.recentSubreddits.state : [], shown: Set(order))
    }

    /// The list's first section, where re-tapping the tab scrolls to (each section's id is its
    /// setting's; your communities' is "subs"; the Full top bar's title comes first).
    private var firstRowId: String {
        if app.settings.value.topBarMode != .expandable { return "title" }
        return app.settings.value.exploreSections.first(where: \.shown)?.section.rawValue ?? "subs"
    }

    private var popularSection: some View {
        Section {
            HStack(spacing: 10) {
                destinationButton("Popular", "flame") { app.navigator.openSubreddit("popular") }
                // With the Posts tab on r/all (Settings), this one opens the frontpage instead.
                if app.settings.value.postsTabAll {
                    destinationButton("Frontpage", "house") { app.navigator.push(.frontpage) }
                } else {
                    destinationButton("All", "globe") { app.navigator.openSubreddit("all") }
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
        .id(ExploreSection.popular.rawValue)
    }

    @ViewBuilder private func customFeedsSection(multis: [Multireddit], anonymous: Bool) -> some View {
        if !multis.isEmpty || !anonymous {
            Section {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(multis, id: \.path) { m in
                            feedChip(m.displayName.nilIfEmpty ?? m.name, "rectangle.stack") {
                                app.navigator.push(.multireddit(username: m.owner(), name: m.name))
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
                        Button("See all") { app.navigator.push(.customFeeds) }
                            .font(.subheadline)
                            .textCase(nil)
                    }
                }
            }
            .id(ExploreSection.customFeeds.rawValue)
        }
    }

    /// A list of your communities. While filtering, the first one in the order shows the
    /// results instead and the rest step aside.
    @ViewBuilder private func communitySection(_ section: ExploreSection, order: [ExploreSection]) -> some View {
        let all = groups(order)
        if all.first?.key == "all" {
            if order.first(where: \.isCommunityList) == section, let g = all.first { groupSection(g).id(section.rawValue) }
        } else {
            switch section {
            case .recommended:
                communityCarousel("Recommended for you", recommended.filter { !joinedNow.contains($0.name.lowercased()) }, canJoin: true).id(section.rawValue)
            case .recentlyVisited:
                if let g = all.first(where: { $0.key == "recent" }) { groupSection(g).id(section.rawValue) }
            case .favorites:
                if let g = all.first(where: { $0.key == "favs" }) { favoritesSection(g.subs).id(section.rawValue) }
            case .following:
                if let g = all.first(where: { $0.key == "following" }) { groupSection(g).id(section.rawValue) }
            default:
                EmptyView()
            }
        }
    }

    /// Your favorites as a row of their pictures (#162); a long press offers to unfavorite.
    private func favoritesSection(_ subs: [Subreddit]) -> some View {
        Section("Favorites") {
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(subs, id: \.name) { sub in
                        let isUser = sub.name.hasPrefix("u_")
                        let name = isUser ? String(sub.name.dropFirst(2)) : sub.name
                        NavigationLink(value: isUser ? Route.user(username: name) : Route.subreddit(name: sub.name)) {
                            VStack(spacing: 6) {
                                LetterAvatar(name: name, size: 56, imageUrl: sub.iconUrl)
                                Text(name).font(.caption).lineLimit(1)
                            }
                            .frame(width: 76)
                            .padding(.vertical, 8)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Remove from Favorites", systemImage: "star.slash", role: .destructive) { toggleFavorite(sub) }
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
            .scrollIndicators(.hidden)
            .listRowInsets(EdgeInsets())
        }
    }

    private func groupSection(_ section: ExploreGroup) -> some View {
        let visits = Dictionary(app.recentSubreddits.state.map { ($0.name.lowercased(), $0.visits) }, uniquingKeysWith: { first, _ in first })
        var joined = Set<String>()
        if case let .data(list) = SubscriptionsViewModel.shared.subs { joined = Set(list.map { $0.name.lowercased() }) }
        // Recently visited: the first few, and Show all (#162); short lists show whole.
        let folds = section.key == "recent" && section.subs.count > 4
        let shown = folds && !recentAll ? Array(section.subs.prefix(3)) : section.subs
        return Section {
            if section.subs.isEmpty {
                Text(section.empty ?? "").foregroundStyle(.secondary)
            }
            ForEach(shown, id: \.name) { sub in
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
            if folds {
                Button(recentAll ? "Show less" : "Show all \(section.subs.count)") { withAnimation { recentAll.toggle() } }
                    .frame(maxWidth: .infinity)
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

    private var recommendKey: String {
        if case let .data(list) = SubscriptionsViewModel.shared.subs { return "\(app.feed.version)|\(list.count)|\(app.contentFilters.value.hideNsfw)" }
        return ""
    }

    private func loadRecommended() async {
        guard case let .data(list) = SubscriptionsViewModel.shared.subs, app.session.session?.anonymous != true else { recommended = []; return }
        // Up to 10, as a carousel (#161); each looked up once a session, so coming back to
        // Explore costs no requests.
        let names = app.forYou.recommendedCommunities(subscribed: Set(list.map { $0.name.lowercased() }), limit: 10)
        let hideNsfw = app.contentFilters.value.hideNsfw
        var found: [String: Subreddit] = [:]
        for n in names { if let hit = Self.recommendedInfo[n] { found[n] = hit } }
        await withTaskGroup(of: Subreddit?.self) { group in
            for n in names where found[n] == nil { group.addTask { try? await app.repository.getSubredditAbout(n) } }
            for await s in group { if let s { found[s.name.lowercased()] = s; Self.recommendedInfo[s.name.lowercased()] = s } }
        }
        recommended = names.compactMap { found[$0] }.filter { $0.userIsSubscriber != true && !(hideNsfw && $0.over18) }
    }

    private var showPopularSubs: Bool { app.settings.value.exploreSections.contains { $0.section == .popularCommunities && $0.shown } }

    /// Popular communities you haven't joined (nor hidden as NSFW).
    private func notJoined(_ subs: [Subreddit]) -> [Subreddit] {
        var mine = joinedNow
        if case let .data(list) = SubscriptionsViewModel.shared.subs { mine.formUnion(list.map { $0.name.lowercased() }) }
        let hideNsfw = app.contentFilters.value.hideNsfw
        return subs.filter { !mine.contains($0.name.lowercased()) && !(hideNsfw && $0.over18) }
    }

    /// Community cards in a sideways row (#161: Recommended for you; Popular communities):
    /// each with its picture, name, members and Join (not when signed out).
    @ViewBuilder private func communityCarousel(_ title: String, _ subs: [Subreddit], canJoin: Bool) -> some View {
        if !subs.isEmpty {
            Section(title) {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(subs, id: \.name) { sub in
                            // Its banner (#162; a tint when it has none) with its picture over it.
                            VStack(spacing: 4) {
                                NavigationLink(value: Route.subreddit(name: sub.name)) {
                                    VStack(spacing: 4) {
                                        LetterAvatar(name: sub.name, size: 60, imageUrl: sub.iconUrl)
                                            .overlay { Circle().strokeBorder(Color(.secondarySystemGroupedBackground), lineWidth: 3) }
                                            .padding(.bottom, 6)
                                        Text(sub.namePrefixed).font(.subheadline.weight(.semibold)).lineLimit(1)
                                        Text("\(compactNumber(sub.subscribers)) members").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.plain)
                                if canJoin {
                                    Button("Join") { join(sub) }
                                        .buttonStyle(.borderedProminent)
                                        .buttonBorderShape(.capsule)
                                        .padding(.top, 6)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.top, 26)
                            .padding(.bottom, 12)
                            .frame(width: 156)
                            .background(alignment: .top) {
                                ZStack {
                                    Color.accentColor.opacity(0.25)
                                    if let banner = sub.bannerUrl.flatMap(URL.init(string:)) { RemoteImage(url: banner) }
                                }
                                .frame(height: 56)
                                .clipped()
                            }
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(.rect(cornerRadius: 22))
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
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
