import SwiftUI

/// A subreddit's about info (header + about sheet).
@MainActor @Observable final class SubredditAboutViewModel {
    private(set) var about: Async<Subreddit> = .loading
    /// Optimistic subscribe state.
    private(set) var subOverride: Bool?

    @ObservationIgnored let name: String
    @ObservationIgnored private var started = false

    init(name: String) { self.name = name }

    func load() {
        if started { return }
        started = true
        Task {
            do {
                let about = try await app.repository.getSubredditAbout(name)
                if app.settings.value.trackHistory { app.recentSubreddits.visit(about) }
                self.about = .data(about)
            } catch {
                self.about = .error(error)
                // A quarantined or gated community refuses its about but can still be
                // joined (or left): whether you're in it comes from your subscriptions.
                let reason = (error as? RedditApiException)?.reason
                if app.session.session?.anonymous == false, reason == "quarantined" || reason == "gated",
                   let subs = try? await app.repository.getSubscribedSubreddits() {
                    subOverride = subs.contains { $0.name.lowercased() == name.lowercased() }
                }
            }
        }
    }

    /// A failed about (or a dropped connection): load it again.
    func retry() {
        about = .loading
        started = false
        load()
    }

    func toggleSub(_ name: String, currentlySubscribed: Bool) {
        let next = !currentlySubscribed
        subOverride = next
        Task {
            do {
                try await app.repository.setSubscribed(name, subscribe: next)
            } catch {
                subOverride = currentlySubscribed
                app.navigator.showActionError(next ? "join" : "leave", error)
            }
        }
    }
}

struct SubredditScreen: View {
    let name: String

    @State private var vm: SubredditAboutViewModel
    @State private var fab = FabScroll()
    /// The banner header's top on screen, and where it rests (#257): the banner is drawn
    /// from there up behind the bar, and the name shows in the bar once it's scrolled under.
    @State private var headerTop: CGFloat = -1_000
    @State private var restTop: CGFloat = 0

    /// Expandable: the community's banner as the header, as a messaging app's profile (#257).
    private var banner: Bool { app.settings.value.topBarMode == .expandable }
    private var folded: Bool { headerTop + bannerHeight + 8 < restTop }

    init(name: String) {
        self.name = name
        _vm = State(initialValue: SubredditAboutViewModel(name: name))
    }

    var body: some View {
        let nav = app.navigator
        let anonymous = app.session.session?.anonymous != false

        Group {
            // "Hide NSFW posts" would leave an NSFW subreddit's page empty: say why instead (#94).
            if app.contentFilters.value.hideNsfw, vm.about.value?.over18 == true {
                ContentUnavailableView {
                    Label("This community is NSFW", systemImage: "eye.slash")
                } description: {
                    Text("Its posts are hidden because Hide NSFW posts is on.")
                } actions: {
                    Button("Content filters") { nav.push(.contentFilters) }.buttonStyle(.glass)
                }
            } else {
                PostListView(feedKey: name, fabScroll: fab) {
                    if banner, case let .data(s) = vm.about {
                        SubredditBannerHeader(about: s, vm: vm)
                            .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .global).minY }) { top in
                                headerTop = top
                                restTop = max(restTop, top)
                            }
                            .onDisappear { headerTop = -1_000 }
                    } else {
                        SubredditHeader(vm: vm)
                    }
                }
            }
        }
            .overlay(alignment: .top) {
                if banner, case let .data(s) = vm.about, restTop > 0 {
                    // From the screen's top to the banner's foot, moving with the list.
                    BannerBackdrop(about: s)
                        .frame(height: restTop + bannerHeight)
                        .offset(y: headerTop - restTop)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .navigationTitle(banner ? "" : "r/\(name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if banner {
                    // The icon and name, in the bar once the header has gone under it.
                    ToolbarItem(placement: .principal) {
                        HStack(spacing: 8) {
                            LetterAvatar(name: name, size: 24, imageUrl: vm.about.value?.iconUrl)
                            Text("r/\(name)").font(.headline).lineLimit(1)
                        }
                        .opacity(folded ? 1 : 0)
                        .animation(.easeOut(duration: 0.2), value: folded)
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Search", systemImage: "magnifyingglass") { nav.push(.search(subreddit: name)) }
                    Menu("More", systemImage: "ellipsis") {
                        Button("About & rules", systemImage: "info.circle") { showAbout(name, vm.about.value) }
                        Button("Browse media", systemImage: "play.rectangle.on.rectangle") { app.feed.controller(name).browseMedia?() }
                        if !anonymous && !["all", "popular"].contains(name.lowercased()) {
                            Button("Add to a custom feed", systemImage: "text.badge.plus") {
                                Task { await showAddToCustomFeed(name) }
                            }
                        }
                        Button("Share", systemImage: "square.and.arrow.up") { nav.share("https://reddit.com/r/\(name)") }
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                CollapsingFab(systemImage: "square.and.pencil", label: "New post", expanded: fab.expanded) {
                    nav.push(.submit(subreddit: name))
                }
                .padding(.trailing, 16)
                .padding(.bottom, 12) // a little clear of the tab bar, as every floating button over it
            }
            .task { vm.load() }
    }
}

private let bannerHeight: CGFloat = 64

/// The banner (or a band in the community's colour), behind the bar's buttons (#257).
private struct BannerBackdrop: View {
    let about: Subreddit

    var body: some View {
        Rectangle()
            // Without a banner or a colour of its own: a soft band of the app's accent, not a grey block.
            .fill(bandColor(about.keyColor).map(AnyShapeStyle.init) ?? AnyShapeStyle(IlayTheme.accent.opacity(0.35).gradient))
            .overlay {
                if let url = about.bannerUrl.flatMap(URL.init(string:)) {
                    RemoteImage(url: url) { Color.clear }
                        .scaledToFill()
                }
            }
            .clipped()
    }
}

/// "#0079D3" as a colour.
private func bandColor(_ hex: String?) -> Color? {
    guard let hex, let v = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16), hex.count >= 6 else { return nil }
    return Color(red: Double(v >> 16 & 0xFF) / 255, green: Double(v >> 8 & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
}

/// The banner header's row (#257): room for the banner, the icon on the left over its
/// foot, the name and members beside it, then the description in a card (3 lines, then
/// Show all) with Join.
private struct SubredditBannerHeader: View {
    let about: Subreddit
    let vm: SubredditAboutViewModel

    @State private var open = false
    @State private var fullHeight: CGFloat = 0
    @State private var shownHeight: CGFloat = 0

    var body: some View {
        let subscribed = vm.subOverride ?? about.userIsSubscriber ?? false
        let snippet = snippetMarkdown(about.description)
        // The feed's own colours: its cards', and the page's behind them.
        let carded = FeedRowConfig.current().isCarded
        let page = Color(carded ? .systemGroupedBackground : .systemBackground)
        let card = Color(carded ? .secondarySystemGroupedBackground : .secondarySystemBackground)
        VStack(alignment: .leading, spacing: 10) {
            Color.clear.frame(height: bannerHeight)
            HStack(alignment: .top, spacing: 12) {
                LetterAvatar(name: about.name, size: 64, imageUrl: about.iconUrl)
                    .overlay(Circle().stroke(page, lineWidth: 3))
                    .padding(.top, -42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(about.namePrefixed).font(.title2.bold()).lineLimit(1)
                    Text("\(compactNumber(about.subscribers)) members").font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.top, -6)
            }
            .padding(.horizontal, 16)
            VStack(alignment: .leading, spacing: 6) {
                if !about.description.isEmpty {
                    if open {
                        // Reddit text, its links working, once it's all shown.
                        RedditMarkdown(text: about.description, fontSize: 15, color: .secondary)
                    } else {
                        Text(snippet)
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .onGeometryChange(for: CGFloat.self, of: \.size.height) { shownHeight = $0 }
                            .background(alignment: .top) {
                                Text(snippet).font(.system(size: 15))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .hidden()
                                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { fullHeight = $0 }
                            }
                    }
                }
                HStack {
                    if open || fullHeight > shownHeight + 1 {
                        Button(open ? "Show less" : "Show all") { withAnimation(.easeOut(duration: 0.2)) { open.toggle() } }
                            .font(.subheadline.weight(.semibold))
                    }
                    Spacer(minLength: 0)
                    Button(subscribed ? "Joined" : "Join") { vm.toggleSub(about.name, currentlySubscribed: subscribed) }
                        .buttonStyle(JoinStyle(on: subscribed))
                        .accessibilityAddTraits(subscribed ? .isSelected : [])
                }
            }
            .padding(14)
            .background(card, in: .rect(cornerRadius: 22))
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
        }
    }
}

private struct SubredditHeader: View {
    let vm: SubredditAboutViewModel

    var body: some View {
        switch vm.about {
        case .loading:
            ProgressView().progressViewStyle(.linear).padding(.horizontal, 16).padding(.vertical, 8)
        case let .error(error):
            // Private (403), banned (404) or quarantined (403): Reddit's reason, so the
            // header says why instead of vanishing. Join where you still can; Retry otherwise.
            let reason = (error as? RedditApiException)?.reason
            HStack(spacing: 14) {
                LetterAvatar(name: vm.name, size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text("r/\(vm.name)").font(.title3.bold()).lineLimit(1)
                    Text(friendlyError(error)).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if let subscribed = vm.subOverride {
                    Button(subscribed ? "Joined" : "Join") { vm.toggleSub(vm.name, currentlySubscribed: subscribed) }
                        .buttonStyle(JoinStyle(on: subscribed))
                        .accessibilityAddTraits(subscribed ? .isSelected : [])
                } else if reason == nil {
                    Button("Retry", action: vm.retry).buttonStyle(.glass)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)
        case let .data(s):
            let subscribed = vm.subOverride ?? s.userIsSubscriber ?? false
            VStack(alignment: .leading, spacing: 12) {
                if let banner = s.bannerUrl.flatMap(URL.init(string:)) {
                    RemoteImage(url: banner) { Color(.secondarySystemFill) }
                        .frame(height: 110)
                        .clipShape(.rect(cornerRadius: 20))
                }
                HStack(spacing: 14) {
                    LetterAvatar(name: s.name, size: 52, imageUrl: s.iconUrl)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.namePrefixed).font(.title3.bold()).lineLimit(1)
                        Text("\(compactNumber(s.subscribers)) members").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    // One toggle: its fill changes with the state, and it reads as on/off.
                    Button(subscribed ? "Joined" : "Join") { vm.toggleSub(s.name, currentlySubscribed: subscribed) }
                        .buttonStyle(JoinStyle(on: subscribed))
                        .accessibilityAddTraits(subscribed ? .isSelected : [])
                }
                if !s.description.isEmpty {
                    // Reddit text: its links open (#194).
                    RedditMarkdown(text: s.description, fontSize: 15, color: .secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
    }
}

/// On/off capsule for Join and Follow: tinted when off (the action), quiet when on.
struct JoinStyle: PrimitiveButtonStyle {
    let on: Bool

    func makeBody(configuration: Configuration) -> some View {
        if on {
            Button(role: configuration.role, action: configuration.trigger) { configuration.label }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
        } else {
            Button(role: configuration.role, action: configuration.trigger) { configuration.label }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
        }
    }
}

@MainActor private func showAbout(_ name: String, _ about: Subreddit?) {
    Overlays.launch(detents: [.medium, .large]) { done in
        SubredditAboutSheet(name: name, about: about, onClose: done)
    }
}

private struct SubredditAboutSheet: View {
    let name: String
    let about: Subreddit?
    let onClose: () -> Void

    @State private var rules: [(title: String, description: String)]?

    var body: some View {
        let signedIn = app.session.session?.anonymous == false
        NavigationStack {
            List {
                Section {
                    if let about, !about.title.isEmpty { Text(about.title).font(.headline) }
                    if let about {
                        Text("\(compactNumber(about.subscribers)) members").foregroundStyle(.secondary)
                    }
                    if signedIn { YourFlair(sub: name) }
                    OwnSort(sub: name)
                    if let about, !about.description.isEmpty { RedditMarkdown(text: about.description) }
                }
                Section("Rules") {
                    if let rules {
                        if rules.isEmpty { Text("No rules listed.") }
                        ForEach(rules.indices, id: \.self) { i in
                            // Expandable, without a row for an empty description's text.
                            DisclosureGroup {
                                if !rules[i].description.isEmpty { RedditMarkdown(text: rules[i].description, fontSize: 15) }
                            } label: {
                                Text("\(i + 1). \(rules[i].title)").fontWeight(.semibold)
                            }
                        }
                    } else {
                        Loading().frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("r/\(name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done", systemImage: "xmark", action: onClose) }
            }
        }
        .task { rules = (try? await app.repository.getSubredditRules(name)) ?? [] }
    }
}

/// The sort r/`sub` opens with (#60), in place of Settings' default sort. Applies right away.
private struct OwnSort: View {
    let sub: String

    var body: some View {
        let settings = app.settings.value
        let own = settings.subredditSorts[sub.lowercased()]
        let label = if let own {
            own.sort.needsTime ? "\(own.sort.label) · \(own.time.label)" : own.sort.label
        } else {
            "\(settings.defaultSort.label) (from Settings)"
        }
        HStack {
            Text("Default sort: \(label)").foregroundStyle(.secondary)
            Spacer()
            Menu("Change") {
                Button { pick(nil, .day) } label: {
                    let title = "Same as Settings (\(settings.defaultSort.label))"
                    if own == nil { Label(title, systemImage: "checkmark") } else { Text(title) }
                }
                ForEach(PostSort.allCases, id: \.self) { s in
                    if s.needsTime {
                        Menu(s.label) {
                            ForEach(TopTime.allCases, id: \.self) { t in
                                Button { pick(s, t) } label: {
                                    if own?.sort == s && own?.time == t { Label(t.label, systemImage: "checkmark") } else { Text(t.label) }
                                }
                            }
                        }
                    } else {
                        Button { pick(s, .day) } label: {
                            if own?.sort == s { Label(s.label, systemImage: "checkmark") } else { Text(s.label) }
                        }
                    }
                }
            }
        }
    }

    private func pick(_ sort: PostSort?, _ time: TopTime) {
        app.settings.setSubredditSort(sub, sort.map { SubredditSort(sort: $0, time: time) })
        app.feed.controller(sub).changeSort(sort ?? app.settings.value.defaultSort, time: time)
    }
}

/// Your user flair in r/`sub` (#31): what it is, and Change when the community offers
/// flair you can pick (No flair, a choice, or your own words where a choice allows it).
private struct YourFlair: View {
    let sub: String

    @State private var version = 0
    @State private var selector: Result<UserFlairSelector, Error>?

    var body: some View {
        let s = try? selector?.get()
        HStack {
            Group {
                if selector == nil {
                    Text("Your flair: …")
                } else if let s {
                    if let current = s.currentText {
                        Text("Your flair: \(current)")
                    } else if s.choices.isEmpty {
                        Text("No user flair in this community")
                    } else {
                        Text("Your flair: none")
                    }
                } else {
                    Text("Your flair: couldn't load")
                }
            }
            .foregroundStyle(.secondary)
            Spacer()
            if let s, !s.choices.isEmpty {
                Button("Change") {
                    Task {
                        if await pickUserFlair(sub, s) { version += 1 }
                    }
                }
                .buttonStyle(.borderless)
            }
        }
        .task(id: version) {
            do { selector = .success(try await app.repository.getUserFlairSelector(sub)) } catch { selector = .failure(error) }
        }
    }
}

private enum FlairPick {
    case noFlair
    case choice(UserFlairChoice)
}

/// Picks and sets your flair in `sub`; true if it changed.
@MainActor private func pickUserFlair(_ sub: String, _ s: UserFlairSelector) async -> Bool {
    let picked: FlairPick? = await Overlays.show(detents: [.medium, .large]) { done in
        NavigationStack {
            List {
                flairRow("No flair", checked: s.currentId == nil && s.currentText == nil) { done(.noFlair) }
                ForEach(s.choices, id: \.id) { c in
                    flairRow(c.text.nilIfEmpty ?? "(write your own)", subtitle: c.editable ? "You can change the text" : nil, checked: c.id == s.currentId) {
                        done(.choice(c))
                    }
                }
            }
            .navigationTitle("Your flair in r/\(sub)")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    guard let picked else { return false }
    var choice: UserFlairChoice?
    if case let .choice(c) = picked { choice = c }
    var text: String?
    if let choice, choice.editable {
        guard let written = await askText(
            "Flair text", label: "Flair text", confirm: "Save",
            initial: choice.id == s.currentId ? s.currentText ?? choice.text : choice.text
        ) else { return false }
        text = written
    }
    do {
        try await app.repository.setUserFlair(sub, username: app.session.username, choice: choice, text: text)
        app.navigator.showSnackbar(choice == nil ? "Flair removed" : "Flair set")
        return true
    } catch {
        app.navigator.showActionError("set your flair", error)
        return false
    }
}

@MainActor private func flairRow(_ title: String, subtitle: String? = nil, checked: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary)
                if let subtitle { Text(subtitle).font(.footnote).foregroundStyle(.secondary) }
            }
            Spacer()
            if checked { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
        }
        .contentShape(.rect)
    }
    .buttonStyle(.plain)
}
