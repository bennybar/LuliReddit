import SwiftUI

/// The Posts tab: the frontpage feed under its top bar. Full: a search field across the
/// top with new post and your avatar, the title scrolling with the feed. Expandable: a
/// native large title, with search and one button holding the rest.
struct FrontpageTab: View {
    @State private var fab = FabScroll()
    @State private var chips = FeedChipsState()
    /// The favorite shown in place of the feed (#311); nil: the feed itself.
    @State private var favKey: String?
    /// Home's namespace: the Search screen grows out of this tab's search button (#271).
    @Environment(\.searchZoom) private var homeZoom
    /// Outside Home (previews): one of its own, matching nothing.
    @Namespace private var ownZoom

    var body: some View {
        let zoom = homeZoom ?? ownZoom
        let settings = app.settings.value
        // Settings → "Posts tab shows r/all": plain r/all here, and Explore's All button opens the frontpage.
        let postsAll = settings.postsTabAll
        let engines = app.feed.engines
        let hasEngines = !postsAll && engines != nil
        let forYou = hasEngines && settings.forYouFeed
        let homeOn = hasEngines && settings.redditHomeAllowed && settings.redditHomeFeed
        let blend = forYou && settings.blendHome && settings.redditHomeAllowed
        let expandable = settings.topBarMode == .expandable
        let mainTitle = postsAll ? "r/all" : homeOn ? "Home" : blend ? "Blend" : forYou ? "For You" : "Frontpage"
        // Settings › Feed › Favorites on Home (#311): your favorite custom feeds and communities
        // as a second row of chips. One shows here in place of the feed, which keeps its place.
        let signedIn = app.session.session?.anonymous == false
        let favorites = settings.favoritesOnHome && signedIn
            ? homeFavorites(multis: app.feed.multireddits.value ?? [], subs: SubscriptionsViewModel.shared.subs.value ?? []) { $0.owner() }
            : []
        let fav = favorites.first { $0.key == favKey }
        let feedKey = fav?.key ?? settings.postsTabKey
        let title = fav.map(favoriteLabel) ?? mainTitle
        // "On your phone": short, so it fits beside the title (#176).
        let subtitle = fav == nil && !homeOn && forYou ? (blend ? blendSubtitle(engines?.blendState) : "On your phone") : ""
        let nav = app.navigator
        let row: FeedRow? = favorites.isEmpty ? nil : FeedRow(
            id: ([mainTitle, fav?.key ?? "", "\(settings.subredditPrefix)"] + favorites.map(\.key)).joined(separator: "|")
        ) { state in
            AnyView(FavoritesRow(mainTitle: mainTitle, favorites: favorites, selected: fav?.key, state: state) { favKey = $0 })
        }

        // The title (Full mode) and the Digest's one-time offer, above the chips.
        let offer = fav == nil && !postsAll && DigestOffer.shared.shown
        let header: (() -> FrontpageHeader)? = expandable && !offer ? nil : {
            FrontpageHeader(title: expandable ? nil : title, subtitle: subtitle, offer: offer)
        }
        // The Digest's chip (Settings › Digest › Show Digest in › Posts chip): the digest in place of the feed.
        let digestChip = hasEngines && settings.digestEnabled && settings.digestPlace == 0 && app.session.session?.anonymous == false
        Group {
            if digestChip && fav == nil && app.digest.onPosts {
                DigestList {
                    VStack(spacing: 0) {
                        if let header { header() }
                        FeedChips(controller: app.feed.controller(""), state: chips)
                        if let row { row.make(chips) }
                    }
                }
            } else {
                PostListView(feedKey: feedKey, postsTab: true, fabScroll: fab, feedRow: row, optionalHeader: header)
            }
        }
            .navigationTitle(expandable ? title : "")
            .navigationSubtitle(expandable ? subtitle : "")
            .navigationBarTitleDisplayMode(expandable ? .large : .inline)
            // What the Search screen grows out of (#271): its button in the bar.
            .barZoomSource(searchZoomSource, in: zoom, label: expandable ? "Search" : "Search Reddit")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { SideBarButton() }
                if expandable {
                    // Search on its own item, so it can be what the Search screen grows out of (#271).
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Search", systemImage: "magnifyingglass") { nav.push(.search(), zoom: true) }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu("Toolbar", systemImage: "ellipsis") { ToolbarPanel(compact: false) }
                            // Layout and autoplay apply at once and leave the menu open,
                            // so the change is visible behind it.
                            .menuActionDismissBehavior(.disabled)
                    }
                } else {
                    ToolbarItem(placement: .principal) {
                        if settings.showApiUsage {
                            ApiUsagePill()
                        } else {
                            Button { nav.push(.search(), zoom: true) } label: {
                                if settings.fullBarNewPost {
                                    Label("Search Reddit", systemImage: "magnifyingglass")
                                        .labelStyle(.titleAndIcon)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 190, alignment: .leading)
                                } else {
                                    // Without New post, Gmail's (#146): just the words, in the middle.
                                    Text("Search Reddit")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 220, alignment: .center)
                                }
                            }
                        }
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        if settings.fullBarNewPost {
                            Button("New post", systemImage: "square.and.pencil") { nav.push(.submit()) }
                        }
                        // The menu, without what's already in this bar (#78).
                        Menu { ToolbarPanel(compact: true) } label: { ProfileAvatar() }
                            .menuActionDismissBehavior(.disabled)
                    }
                }
            }
            // The Digest offer needs to know about favourites (Explore's list, usually loaded already).
            .task { if !DigestOffer.shared.done && !settings.digestEnabled { SubscriptionsViewModel.shared.loadIfNeeded() } }
            // Favorites on Home (#311): the lists Explore and the side bar load anyway, and the
            // account's own after a switch.
            .task(id: "\(settings.favoritesOnHome) \(app.feed.version)") {
                if settings.favoritesOnHome && signedIn {
                    SubscriptionsViewModel.shared.loadIfNeeded()
                    app.feed.loadMultireddits()
                }
            }
            .onChange(of: app.feed.version) { favKey = nil }
            .overlay(alignment: .bottomTrailing) {
                if settings.homeFab != .off {
                    let newPost = settings.homeFab == .newPost
                    CollapsingFab(
                        systemImage: newPost ? "square.and.pencil" : "magnifyingglass",
                        label: settings.homeFab.label,
                        expanded: fab.expanded,
                        hideOnScroll: settings.fabHideOnScroll
                    ) {
                        // In a favorite community, a new post goes there.
                        nav.push(newPost ? .submit(subreddit: fav.flatMap { $0.multi ? nil : $0.name }) : .search())
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 12) // a little clear of the tab bar, as every floating button over it
                }
            }
    }
}

/// What scrolls above the chips: Full mode's title, and the Digest's offer.
private struct FrontpageHeader: View {
    let title: String?
    let subtitle: String
    let offer: Bool

    var body: some View {
        VStack(spacing: 0) {
            if let title { FrontpageTitle(title: title, subtitle: subtitle) }
            if offer { DigestOfferCard() }
        }
    }
}

/// Full mode's title: it scrolls with the feed.
private struct FrontpageTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.title2.bold())
            if !subtitle.isEmpty {
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }
}

/// Your avatar in the top bar: one request, the first time something shows it.
private struct ProfileAvatar: View {
    var body: some View {
        let session = app.session.session
        LetterAvatar(name: session?.username ?? "", size: 32, imageUrl: app.feed.me?.iconUrl)
            .accessibilityLabel("Your profile")
            .task(id: session?.username) { app.feed.loadMe() }
    }
}

/// Live Reddit API rate-limit usage in place of the search bar (power-user setting).
/// Reddit allows ~100 requests/minute per OAuth client.
private struct ApiUsagePill: View {
    var body: some View {
        let label = if let r = app.rateLimit { "API \(r.used)/\(r.total) · resets \(r.secondsLeft())s" } else { "API usage · no calls yet" }
        Label(label, systemImage: "gauge.with.dots.needle.33percent")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

/// The toolbar's menu (Kotlin's floating panel): search with your profile, New post and
/// Settings, the feed layout, and the autoplay switch. `compact`: without what the Full
/// bar already has.
private struct ToolbarPanel: View {
    let compact: Bool

    var body: some View {
        let nav = app.navigator
        let settings = app.settings.value
        let username = app.session.session.flatMap { $0.anonymous ? nil : $0.username }
        Section {
            if !compact { Button("Search Reddit", systemImage: "magnifyingglass") { nav.push(.search()) } }
            if let username { Button("Your profile", systemImage: "person.crop.circle") { nav.openUser(username) } }
            if !compact { Button("New post", systemImage: "square.and.pencil") { nav.push(.submit()) } }
            Button("Settings", systemImage: "gearshape") { nav.push(.settings) }
            // Unlike the layout and autoplay below, this closes the menu: it opens a viewer.
            Button("Browse media", systemImage: "play.rectangle.on.rectangle") { app.feed.controller(settings.postsTabKey).browseMedia?() }
                .menuActionDismissBehavior(.enabled)
        }
        Picker("Layout", selection: Binding(get: { settings.postDisplay }, set: { app.settings.setPostDisplay($0) })) {
            ForEach(PostDisplay.allCases, id: \.self) { Label($0.label, systemImage: $0.icon).tag($0) }
        }
        .pickerStyle(.inline)
        Toggle("Autoplay media", systemImage: "play.circle", isOn: Binding(get: { settings.autoplayMedia }, set: { app.settings.setAutoplayMedia($0) }))
    }
}

/// Blend's header subtitle: what its Reddit Home source is contributing right now.
private func blendSubtitle(_ state: BlendState?) -> String {
    switch state {
    case let .included(count):
        count == 0 ? "Beta · no Reddit Home picks yet" : "Beta · \(count) Reddit Home pick\(count == 1 ? "" : "s")"
    case .loading: "Beta · Reddit Home loading…"
    case let .unavailable(signedOut):
        signedOut ? "Beta · Reddit Home signed out: showing For You" : "Beta · Reddit Home unavailable: showing For You"
    case nil: "Your Reddit Home + For You · Beta"
    }
}

/// The frontpage as a pushed page: Explore's All button opens it when the Posts tab
/// shows r/all (Settings). Plain, like r/all itself: no For You / Blend / Home.
struct FrontpageScreen: View {
    @State private var fab = FabScroll()

    var body: some View {
        let nav = app.navigator
        PostListView(feedKey: "", fabScroll: fab)
            .navigationTitle("Frontpage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Search", systemImage: "magnifyingglass") { nav.push(.search()) }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                CollapsingFab(
                    systemImage: "square.and.pencil", label: "New post", expanded: fab.expanded,
                    hideOnScroll: app.settings.value.fabHideOnScroll
                ) {
                    nav.push(.submit())
                }
                .padding(.trailing, 16)
                .padding(.bottom, 12) // a little clear of the tab bar, as every floating button over it
            }
    }
}

/// One of Home's favorites (#311): a custom feed or a community, and its feed key.
struct HomeFavorite: Equatable {
    let key: String
    let name: String
    let multi: Bool
}

/// Your favorite custom feeds, then your favorite communities (not profiles), for Home's row (#311).
func homeFavorites(multis: [Multireddit], subs: [Subreddit], owner: (Multireddit) -> String) -> [HomeFavorite] {
    multis.filter(\.isFavorited).map { HomeFavorite(key: "m::\(owner($0))::\($0.name)", name: $0.displayName, multi: true) }
        + subs.filter { $0.userHasFavorited && !$0.name.hasPrefix("u_") }.map { HomeFavorite(key: $0.name, name: $0.name, multi: false) }
}

@MainActor private func favoriteLabel(_ f: HomeFavorite) -> String { f.multi ? f.name : subredditName(f.name) }

/// Home's second row (#311): the feed itself, then each favorite, as glass capsules like the sort's.
private struct FavoritesRow: View {
    let mainTitle: String
    let favorites: [HomeFavorite]
    let selected: String?
    let state: FeedChipsState
    let pick: (String?) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip(mainTitle, on: selected == nil) { pick(nil) }
                ForEach(favorites, id: \.key) { f in
                    chip(favoriteLabel(f), on: f.key == selected) { pick(f.key) }
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        // The same 12 as between two cards.
        .padding(.bottom, 12)
        .sensoryFeedback(.selection, trigger: selected)
    }

    private func chip(_ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(on ? .semibold : .medium))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(on ? Color.white : Color.primary)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .glassEffect(on ? .regular.tint(.accentColor).interactive() : .regular.interactive(), in: .capsule)
                // Over the list, an outline keeps it apart from what passes beneath (#80).
                .overlay { Capsule().strokeBorder(Color(.separator), lineWidth: 1).opacity(state.floating && !on ? 1 : 0).allowsHitTesting(false) }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
