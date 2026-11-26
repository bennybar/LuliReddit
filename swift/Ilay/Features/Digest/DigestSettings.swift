import SwiftUI

/// "How Digest works" (the same words on both apps; keep them true to what's built).
let digestExplained: [(title: String, text: String)] = [
    ("What it is", "The posts that stood out in the last 24 hours in the communities you choose, in one short list."),
    ("How it picks", "By how unusual a post is for its own community: its points and comments against what's "
        + "typical there. A small community's big day counts as much as a big one's, and a quiet day gives a short digest."),
    ("What AI adds", "With \"Use AI\" on, your own AI key picks and explains the posts, and can add a short overview. "
        + "One small request per digest, fewer on refresh since only new posts are sent. Post titles, the start of "
        + "text posts and the topics you read go to the AI provider you set up. Nothing is sent unless you turn it on."),
    ("Your communities", "Your starred favourites, or up to \(DigestModule.maxCommunities) you choose."),
    ("When it's built", "When you open it, if it's more than 12 hours old, or daily at your time with the notification on "
        + "(on iPhone: a reminder at that time, built when you open it). Pull down for what's new: it only adds "
        + "posts, nothing already there goes away."),
    ("Where you'll find it", "A Digest chip at the top of Posts, a tab in the bottom bar, or only the side bar and the Profile menu: your choice."),
    ("Reading it", "Swipe a post to mark it read (left, unless you change the side). A post you saw in one digest isn't repeated in the next. Digests stay on this phone for 7 days."),
]

/// The explainer. `ask`: before Digest is first turned on, with Turn on / Not now (true
/// when turned on); otherwise just Close.
@MainActor func showDigestExplainer(ask: Bool) async -> Bool {
    await Overlays.show(detents: [.large]) { (done: @escaping (Bool?) -> Void) in
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(digestExplained, id: \.title) { part in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(part.title).font(.headline)
                            Text(part.text).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) {
                if ask {
                    VStack(spacing: 8) {
                        Button { done(true) } label: { Text("Turn on").frame(maxWidth: .infinity) }
                            .buttonStyle(.glassProminent)
                            .controlSize(.large)
                        Button("Not now") { done(false) }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }
            }
            .navigationTitle("How Digest works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !ask {
                    ToolbarItem(placement: .confirmationAction) { Button("Close") { done(false) } }
                }
            }
        }
    } == true
}

private let explainedKey = "digestExplained"

/// Turning the Digest on: the explainer first, the first time. False if it stayed off.
@MainActor @discardableResult func setDigestEnabled(_ on: Bool) async -> Bool {
    if on, app.prefs.getBool(explainedKey) != true {
        if await !showDigestExplainer(ask: true) { return false }
        app.prefs.setBool(explainedKey, true)
    }
    app.settings.setDigestEnabled(on)
    DigestNotifications.reschedule()
    return true
}

/// The Communities row's subtitle.
@MainActor func digestCommunitiesLabel(_ chosen: [String]?) -> String {
    guard let chosen else { return "Your favourites" }
    if chosen.isEmpty { return "None chosen" }
    if chosen.count <= 3 { return chosen.map { subredditName($0) }.joined(separator: ", ") }
    return "\(chosen.count) communities"
}

/// The communities editor: your subscriptions, favourites first, as a checklist of at most
/// `DigestModule.maxCommunities`; "Use my favourites" follows your favourites again. It
/// opens at once on Explore's list (loading it if it isn't yet), and a second tap while
/// it's open does nothing.
@MainActor func editDigestCommunities() async {
    if editingCommunities { return }
    editingCommunities = true
    defer { editingCommunities = false }
    let result: CommunitiesPick? = await Overlays.show(detents: [.large]) { done in
        DigestCommunitiesSheet(chosen: app.digest.chosen, done: done)
    }
    switch result {
    case let .list(names): app.digest.setCommunities(names)
    case .favourites: app.digest.setCommunities(nil)
    case nil: break
    }
}

@MainActor private var editingCommunities = false

private enum CommunitiesPick {
    case list([String])
    case favourites
}

private struct DigestCommunitiesSheet: View {
    let chosen: [String]?
    let done: (CommunitiesPick?) -> Void
    /// Nil until the list is there (it starts from your favourites when none are chosen).
    @State private var picked: Set<String>?

    init(chosen: [String]?, done: @escaping (CommunitiesPick?) -> Void) {
        self.chosen = chosen
        self.done = done
        _picked = State(initialValue: chosen.map(Set.init))
    }

    private var subs: [Subreddit] {
        (SubscriptionsViewModel.shared.subs.value ?? []).sorted { a, b in
            a.userHasFavorited != b.userHasFavorited ? a.userHasFavorited : a.name.lowercased() < b.name.lowercased()
        }
    }

    var body: some View {
        let max = DigestModule.maxCommunities
        let subs = subs
        let model = SubscriptionsViewModel.shared
        let picked = picked ?? []
        let full = picked.count >= max
        NavigationStack {
            List {
                if case .loading = model.subs, subs.isEmpty {
                    HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear)
                } else if case let .error(error) = model.subs, subs.isEmpty {
                    Text(friendlyError(error)).foregroundStyle(.secondary)
                    Button("Retry") { model.load(force: true) }
                } else {
                    Section {
                        if subs.isEmpty { Text("You haven't joined any communities yet.").foregroundStyle(.secondary) }
                        ForEach(subs, id: \.name) { s in
                            let k = s.name.lowercased()
                            let on = picked.contains(k)
                            Button {
                                var next = picked
                                if on { next.remove(k) } else if !full { next.insert(k) }
                                self.picked = next
                            } label: {
                                HStack {
                                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(on ? Color.accentColor : .secondary)
                                    Text(subredditName(s.name)).foregroundStyle(on || !full ? .primary : .secondary)
                                    Spacer()
                                    if s.userHasFavorited { Image(systemName: "star.fill").font(.caption).foregroundStyle(.tint) }
                                }
                            }
                        }
                    } header: {
                        Text(full ? "That's \(max), the most a digest takes." : "\(picked.count) of up to \(max)")
                    } footer: {
                        Button("Use my favourites") { done(.favourites) }.padding(.top, 8)
                    }
                }
            }
            .navigationTitle("Digest communities")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { done(nil) } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { done(.list(subs.map { $0.name.lowercased() }.filter(picked.contains))) }
                        .disabled(self.picked == nil)
                }
            }
            .task { model.loadIfNeeded() }
            // Following your favourites: start from them once the list is there.
            .onChange(of: subs.count, initial: true) {
                if self.picked == nil, !subs.isEmpty {
                    self.picked = Set(subs.filter(\.userHasFavorited).map { $0.name.lowercased() }.prefix(max))
                }
            }
        }
    }
}
