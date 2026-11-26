import SwiftUI

/// A subreddit's about info (header + about sheet).
@MainActor @Observable final class SubredditAboutViewModel {
    private(set) var about: Async<Subreddit> = .loading
    /// Optimistic subscribe state.
    private(set) var subOverride: Bool?

    @ObservationIgnored let name: String
    @ObservationIgnored private var started = false

    /// Abouts seen this session: a community opened again paints its header at once, then
    /// refreshes it. It used to slot in above the cached posts a moment later and push them
    /// down ~150 pt (measured on the simulator).
    private static var seen: [String: Subreddit] = [:]

    init(name: String) {
        self.name = name
        if let known = Self.seen[name.lowercased()] { about = .data(known) }
    }

    func load() {
        if started { return }
        started = true
        Task {
            do {
                let about = try await app.repository.getSubredditAbout(name)
                if app.settings.value.trackHistory { app.recentSubreddits.visit(about) }
                Self.seen[name.lowercased()] = about
                if self.about.value != about { self.about = .data(about) }
            } catch {
                // Keep the header from earlier this session rather than drop it.
                if self.about.value == nil { self.about = .error(error) }
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

    /// `done`: called once Reddit took it (the "Joined r/x" pill, #277), never on a failure.
    func toggleSub(_ name: String, currentlySubscribed: Bool, done: ((Bool) -> Void)? = nil) {
        let next = !currentlySubscribed
        subOverride = next
        Task {
            do {
                try await app.repository.setSubscribed(name, subscribe: next)
                done?(next)
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
    /// "Joined r/x" / "Left r/x" after the banner header's + / ✓ (#277), for a few seconds.
    @State private var joinPill: String?
    /// Home's namespace: the Search screen grows out of this page's search button (#285).
    @Environment(\.searchZoom) private var homeZoom
    /// Outside Home (previews): one of its own, matching nothing.
    @Namespace private var ownZoom

    /// Expandable: the community's banner as the header, as a messaging app's profile (#257).
    private var banner: Bool { app.settings.value.topBarMode == .expandable }
    private var folded: Bool { headerTop + bannerHeight + 8 < restTop }
    /// Its own id: this page sits over Posts, whose button has the plain one.
    private var zoomSource: String { "\(searchZoomSource):r/\(name)" }

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
                        SubredditBannerHeader(about: s, vm: vm) { joined in
                            joinPill = joined ? "Joined \(subredditName(s.namePrefixed))" : "Left \(subredditName(s.namePrefixed))"
                        }
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
                    // From the screen's top to the banner's foot, moving with the list; the
                    // icon over its foot is drawn here too, so the banner never covers it.
                    BannerBackdrop(about: s, height: restTop + bannerHeight)
                        .offset(y: headerTop - restTop)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .navigationTitle(banner ? "" : subredditName(name))
            .navigationBarTitleDisplayMode(.inline)
            // What the Search screen grows out of, as on Posts (#285): its button in the bar.
            .barZoomSource(zoomSource, in: homeZoom ?? ownZoom, label: banner ? "Search" : "Search in r/\(name)")
            .toolbar {
                if banner {
                    // The icon and name, in the bar once the header has gone under it.
                    ToolbarItem(placement: .principal) {
                        HStack(spacing: 8) {
                            LetterAvatar(name: name, size: 24, imageUrl: vm.about.value?.iconUrl)
                            Text(subredditName(name)).font(.headline).lineLimit(1)
                        }
                        .opacity(folded ? 1 : 0)
                        .animation(.easeOut(duration: 0.2), value: folded)
                    }
                    // What the Search screen grows out of, as on Posts (#285).
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Search", systemImage: "magnifyingglass") { nav.push(.search(subreddit: name), zoom: true, zoomSource: zoomSource) }
                    }
                } else {
                    // The Full bar, as the tabs' (#285): a round search bar in place of the title.
                    ToolbarItem(placement: .principal) {
                        Button { nav.push(.search(subreddit: name), zoom: true, zoomSource: zoomSource) } label: {
                            Text("Search in r/\(name)")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(width: 220, alignment: .center)
                        }
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
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
            // Above the floating button, in the inverse of the page's colours (#277).
            .overlay(alignment: .bottom) {
                if let joinPill {
                    Text(joinPill)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(.systemBackground))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Color(.label), in: .capsule)
                        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
                        .padding(.bottom, 84)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .id(joinPill)
                        .task {
                            try? await Task.sleep(for: .seconds(3))
                            withAnimation(.easeOut(duration: 0.25)) { self.joinPill = nil }
                        }
                }
            }
            .animation(.spring(duration: 0.3), value: joinPill)
            .task { vm.load() }
    }
}

private let bannerHeight: CGFloat = 64
private let bannerIcon: CGFloat = 76 // the icon over the banner's foot (#268: was 64)
private let iconOver: CGFloat = 26 // how much of it is over the banner's foot: about a third (#277)

/// The banner (or a band in the community's colour), behind the bar's buttons, and the
/// icon over its foot (#257).
private struct BannerBackdrop: View {
    let about: Subreddit
    let height: CGFloat

    var body: some View {
        let page = Color(FeedRowConfig.current().isCarded ? .systemGroupedBackground : .systemBackground)
        ZStack(alignment: .topLeading) {
            band.frame(height: height)
            // The ring is a disc behind the icon, not a stroke over its edge, which let the
            // picture show around it (#268); the icon bigger, too.
            LetterAvatar(name: about.name, size: bannerIcon, imageUrl: about.iconUrl)
                .padding(3)
                .background(page, in: Circle())
                .offset(x: 13, y: height - iconOver - 3)
        }
        .frame(height: height + bannerIcon - iconOver + 3, alignment: .top)
    }

    private var band: some View {
        Rectangle()
            // Without a banner or a colour of its own: a soft band of the app's accent, not a grey block.
            .fill(bandColor(about.keyColor).map(AnyShapeStyle.init) ?? AnyShapeStyle(IlayTheme.accent.opacity(0.35).gradient))
            .overlay {
                if let url = about.bannerUrl.flatMap(URL.init(string:)) {
                    BannerImage(url: url)
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
/// foot, the name and members beside it with Join as + / ✓ (#277), then the description
/// in a card (3 lines, then Show all), or no card without one (#278).
private struct SubredditBannerHeader: View {
    let about: Subreddit
    let vm: SubredditAboutViewModel
    /// Joined (true) or left (false) by the + / ✓.
    let onJoined: (Bool) -> Void

    /// RedditMarkdown's size: the 3 lines and the whole text read the same (#277).
    @ScaledMetric(relativeTo: .body) private var textScale: CGFloat = 1

    @State private var open = false
    /// Grown to the whole text (or growing): `open` shows it, `tall` animates the card's
    /// height between the 3 lines and it, so Show all / Show less doesn't jump (#286).
    @State private var tall = false
    @State private var fullHeight: CGFloat = 0
    @State private var shownHeight: CGFloat = 0
    @State private var markdownHeight: CGFloat = 0

    var body: some View {
        let subscribed = vm.subOverride ?? about.userIsSubscriber ?? false
        let snippet = snippetMarkdown(about.description)
        // The feed's own colours: its cards', and the page's behind them.
        let carded = FeedRowConfig.current().isCarded
        let card = Color(carded ? .secondarySystemGroupedBackground : .secondarySystemBackground)
        VStack(alignment: .leading, spacing: 10) {
            Color.clear.frame(height: bannerHeight)
            HStack(alignment: .top, spacing: 12) {
                // The icon's place: it's drawn with the banner (BannerBackdrop), the rest of it
                // below the banner's foot beside the name (#277).
                Color.clear.frame(width: bannerIcon, height: bannerIcon - iconOver - 10)
                // Bigger, and a little further from the banner's foot (#268).
                VStack(alignment: .leading, spacing: 2) {
                    Text(subredditName(about.namePrefixed)).font(.title.bold()).lineLimit(1)
                    Text("\(compactNumber(about.subscribers)) members").font(.subheadline).foregroundStyle(.secondary)
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
                // Join as an icon by the name (#277): + to join, ✓ to leave; it never cuts the name.
                Button {
                    vm.toggleSub(about.name, currentlySubscribed: subscribed, done: onJoined)
                } label: {
                    Image(systemName: subscribed ? "checkmark" : "plus")
                        .font(.body.weight(.semibold))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 40, height: 40)
                        .foregroundStyle(subscribed ? Color.secondary : Color.white)
                        .background(subscribed ? AnyShapeStyle(Color(.tertiarySystemFill)) : AnyShapeStyle(IlayTheme.accent), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(subscribed ? "Leave \(subredditName(about.namePrefixed))" : "Join \(subredditName(about.namePrefixed))")
                .accessibilityAddTraits(subscribed ? .isSelected : [])
            }
            .padding(.horizontal, 16)
            if !about.description.isEmpty {
                let size = 15 * textScale
                VStack(alignment: .leading, spacing: 6) {
                    if open {
                        // Reddit text, its links working, once it's all shown.
                        RedditMarkdown(text: about.description, fontSize: 15, color: .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .onGeometryChange(for: CGFloat.self, of: \.size.height) { markdownHeight = $0 }
                            .frame(height: tall ? markdownHeight : shownHeight, alignment: .top)
                            .clipped()
                    } else {
                        Text(snippet)
                            .font(.system(size: size))
                            .lineSpacing(size * MdMetrics.lineSpacing)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .onGeometryChange(for: CGFloat.self, of: \.size.height) { shownHeight = $0 }
                            .background(alignment: .top) {
                                Text(snippet).font(.system(size: size)).lineSpacing(size * MdMetrics.lineSpacing)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .hidden()
                                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { fullHeight = $0 }
                            }
                    }
                    if open || fullHeight > shownHeight + 1 {
                        Button(tall ? "Show less" : "Show all") {
                            if tall {
                                // Shrinks to the 3 lines' height, then they take the text's place.
                                withAnimation(.easeInOut(duration: 0.26)) { tall = false } completion: { if !tall { open = false } }
                            } else {
                                // The text takes the 3 lines' place at their height, then grows.
                                open = true
                                DispatchQueue.main.async { withAnimation(.easeInOut(duration: 0.28)) { tall = true } }
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(card, in: .rect(cornerRadius: 22))
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            }
        }
        .overlay(alignment: .topLeading) {
            // The icon is drawn behind the list (BannerBackdrop), which takes no touches: a
            // clear circle at its exact place opens it full screen and is where it zooms from (#279).
            if let icon = about.iconUrl {
                Color.clear
                    .frame(width: bannerIcon + 6, height: bannerIcon + 6)
                    .contentShape(Circle())
                    .zoomSource(circle: true)
                    .onTapGesture { app.navigator.openPicture(icon, name: about.namePrefixed) }
                    .accessibilityLabel("Open picture")
                    .accessibilityAddTraits(.isButton)
                    // Where BannerBackdrop puts the ringed icon, in this header's coordinates.
                    .offset(x: 13, y: bannerHeight - iconOver - 3)
            }
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
                    Text(subredditName(vm.name)).font(.title3.bold()).lineLimit(1)
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
                    BannerImage(url: banner)
                        .background(Color(.secondarySystemFill))
                        .frame(height: 110)
                        .clipShape(.rect(cornerRadius: 20))
                }
                HStack(spacing: 14) {
                    LetterAvatar(name: s.name, size: 52, imageUrl: s.iconUrl)
                        .pictureOpens(s.iconUrl, name: s.namePrefixed)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(subredditName(s.namePrefixed)).font(.title3.bold()).lineLimit(1)
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
            .navigationTitle(subredditName(name))
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

/// A subreddit's banner filling its box. Reddit's desktop banners are 4000 px wide and as
/// little as 128 tall: filling a phone's header shows a sliver of one blown up several
/// times (Reddit feedback, r/Howtomen). One that would need more than 1.5× becomes a soft
/// wash of its own colours with the banner sharp across it (#294) instead of a blurry
/// zoom; a big enough one shows as it is.
struct BannerImage: View {
    let url: URL

    @State private var image: UIImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geo in
            if let image {
                let soft = geo.size.height * displayScale > image.size.height * image.scale * 1.5
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .blur(radius: soft ? 30 : 0, opaque: true)
                    .clipped()
                    .overlay {
                        // The banner itself sharp across the wash, at its own shape, as the
                        // website shows it (#294).
                        if soft {
                            Image(uiImage: image).resizable().scaledToFit()
                        }
                    }
                    .transition(.opacity)
            }
        }
        // Full size: its real height decides between sharp and soft.
        .task(id: url) {
            // From memory at once; else it fades in over the band (it popped in a moment
            // after the header, measured on the simulator).
            if let hit = ImageLoader.shared.cached(url: url, maxPixelSize: 0) {
                image = hit
                return
            }
            let loaded = await ImageLoader.shared.image(url: url, maxPixelSize: 0)
            withAnimation(.easeOut(duration: 0.25)) { image = loaded }
        }
    }
}

extension View {
    /// A community's or user's picture that opens full screen on a tap, zooming out of
    /// itself (#279). Nothing for a letter avatar.
    @ViewBuilder func pictureOpens(_ url: String?, name: String) -> some View {
        if let url {
            zoomSource(circle: true)
                .contentShape(Circle())
                .onTapGesture { app.navigator.openPicture(url, name: name) }
                .accessibilityLabel("Open picture")
                .accessibilityAddTraits(.isButton)
        } else {
            self
        }
    }
}
