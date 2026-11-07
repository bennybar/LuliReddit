import SwiftUI

/// The Posts tab: the frontpage feed under its top bar. Full: a search field across the
/// top with new post and your avatar, the title scrolling with the feed. Expandable: a
/// native large title, with search and one button holding the rest.
struct FrontpageTab: View {
    @State private var fab = FabScroll()

    var body: some View {
        let settings = app.settings.value
        // Settings → "Posts tab shows r/all": plain r/all here, and Explore's All button opens the frontpage.
        let postsAll = settings.postsTabAll
        let engines = app.feed.engines
        let hasEngines = !postsAll && engines != nil
        let forYou = hasEngines && settings.forYouFeed
        let homeOn = hasEngines && settings.redditHomeAllowed && settings.redditHomeFeed
        let blend = forYou && settings.blendHome && settings.redditHomeAllowed
        let expandable = settings.topBarMode == .expandable
        let title = postsAll ? "r/all" : homeOn ? "Home" : blend ? "Blend" : forYou ? "For You" : "Frontpage"
        let subtitle = !homeOn && forYou ? (blend ? blendSubtitle(engines?.blendState) : "Personalized on your phone") : ""
        let nav = app.navigator

        let header: (() -> FrontpageTitle)? = expandable ? nil : { FrontpageTitle(title: title, subtitle: subtitle) }
        PostListView(feedKey: settings.postsTabKey, postsTab: true, fabScroll: fab, optionalHeader: header)
            .navigationTitle(expandable ? title : "")
            .navigationSubtitle(expandable ? subtitle : "")
            .navigationBarTitleDisplayMode(expandable ? .large : .inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { SideBarButton() }
                if expandable {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button("Search", systemImage: "magnifyingglass") { nav.push(.search()) }
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
                            Button { nav.push(.search()) } label: {
                                Label("Search Reddit", systemImage: "magnifyingglass")
                                    .labelStyle(.titleAndIcon)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 190, alignment: .leading)
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
            .overlay(alignment: .bottomTrailing) {
                if settings.homeFab != .off {
                    let newPost = settings.homeFab == .newPost
                    CollapsingFab(
                        systemImage: newPost ? "square.and.pencil" : "magnifyingglass",
                        label: settings.homeFab.label,
                        expanded: fab.expanded
                    ) { nav.push(newPost ? .submit() : .search()) }
                    .padding(.trailing, 16)
                    .padding(.bottom, 12) // a little clear of the tab bar, as every floating button over it
                }
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
                CollapsingFab(systemImage: "square.and.pencil", label: "New post", expanded: fab.expanded) {
                    nav.push(.submit())
                }
                .padding(.trailing, 16)
                .padding(.bottom, 12) // a little clear of the tab bar, as every floating button over it
            }
    }
}
