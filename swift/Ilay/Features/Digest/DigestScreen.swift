import SwiftUI

/// The Digest on a page of its own (side bar, Profile menu, the "menu only" choice).
struct DigestScreen: View {
    var body: some View {
        DigestList { EmptyView() }
            .navigationTitle("Digest")
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// What the Digest shows (its page, or Posts with the Digest chip picked): the day, what's
/// been marked read here, how the last build went.
@MainActor @Observable
final class DigestModel {
    /// The day shown: nil for today.
    var day: String?
    var outcome: DigestModule.Outcome?
    var refreshing = false
    /// Read when this opened: hidden unless Show read is on. Read while here, a post stays (dimmed).
    @ObservationIgnored let readAtOpen: Set<String> = app.history.ids
    /// Swiped read here, and the Undo window has passed: hidden too.
    var gone: Set<String> = []
    /// Each day's "seen" time when it was first shown here: what came after it is New.
    @ObservationIgnored var seenAt: [String: Int] = [:]

    func start() async {
        if let out = await app.digest.refreshIfStale() { outcome = out }
    }

    func refresh(manual: Bool, rebuild: Bool = false) async {
        day = nil
        refreshing = manual
        defer { refreshing = false }
        let out = await app.digest.refresh(manual: manual, rebuild: rebuild)
        outcome = out
        guard manual else { return }
        let nav = app.navigator
        switch out {
        case .upToDate: nav.showSnackbar("Up to date")
        case let .updated(added): nav.showSnackbar(rebuild ? "Rebuilt" : added == 0 ? "Nothing new yet" : "\(added) new")
        case let .failed(message): nav.showSnackbar("Couldn't refresh: \(message)")
        default: break
        }
    }

    func markRead(_ item: DigestItem) {
        let id = item.post.id
        app.history.markViewed(item.post)
        app.navigator.showSnackbar("Marked read", actionLabel: "Undo") { app.history.removeViewed(id) }
        // Off the list once Undo has had its time, not under the finger.
        Task {
            try? await Task.sleep(for: .seconds(4))
            if app.history.ids.contains(id) { gone.insert(id) }
        }
    }

    func markUnread(_ item: DigestItem) {
        app.history.removeViewed(item.post.id)
        gone.remove(item.post.id)
        app.navigator.showSnackbar("Marked unread")
    }

    func rebuild() async {
        if await confirmDialog(
            "Rebuild today's digest?",
            "Today's digest starts over from the posts on Reddit now. Posts it already showed may not come back.",
            "Rebuild"
        ) {
            await refresh(manual: true, rebuild: true)
        }
    }
}

/// The Digest as a list, under `top` (Posts: its title and chips). Builds today's when it's
/// missing or stale, and marks it seen on leaving.
struct DigestList<Top: View>: View {
    @ViewBuilder let top: () -> Top
    @State private var model = DigestModel()

    var body: some View {
        let today = app.digest.today()
        let d = app.digest.store.days.first { $0.day == (model.day ?? today) }
        List {
            top()
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            DigestHead(model: model, day: d)
                .listRowSeparator(.hidden)
            content(d)
        }
        .listStyle(.plain)
        .refreshable { await model.refresh(manual: true) }
        .task { await model.start() }
        .onDisappear { app.digest.markSeen() }
    }

    @ViewBuilder
    private func content(_ d: DigestDay?) -> some View {
        if let d {
            let read = app.history.ids
            let showRead = app.settings.value.digestShowRead
            let shown = d.items.filter { showRead || !read.contains($0.post.id) || (!model.readAtOpen.contains($0.post.id) && !model.gone.contains($0.post.id)) }
            if d.items.isEmpty {
                message("Nothing notable today", "No post stands out in your communities yet. Pull down to check again later.")
            } else if shown.isEmpty {
                message("You're all caught up", "You've read everything in this digest.", action: "Show read") { app.settings.setDigestShowRead(true) }
            } else {
                let seenAt = seenAt(d)
                let ids = Set(shown.map(\.post.id))
                // Grouped before hiding read posts, so a community keeps its place as they go.
                ForEach(groupByCommunity(d.items), id: \.community) { group in
                    let items = group.items.filter { ids.contains($0.post.id) }
                    if !items.isEmpty {
                        Text("r/\(group.community)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.tint)
                            .listRowSeparator(.hidden)
                            .padding(.top, 6)
                        ForEach(items, id: \.post.id) { item in
                            DigestRow(model: model, item: item, read: read.contains(item.post.id), isNew: item.addedAt > d.builtAt && item.addedAt > seenAt)
                        }
                    }
                }
            }
        } else {
            switch model.outcome {
            case .signedOut:
                message("Sign in to get your digest", "It's built from communities you follow.")
            case .noCommunities:
                message("No communities yet", "Star a few favourites in your subscriptions, or choose the communities in Digest settings.", action: "Choose communities") {
                    app.navigator.push(.settingsSection(title: "Digest"))
                }
            case let .failed(text) where !app.digest.building:
                message("Couldn't build your digest", text, action: "Retry") { Task { await model.refresh(manual: false) } }
            default:
                ForEach(0..<4, id: \.self) { _ in PostSkeleton().listRowSeparator(.hidden) }
            }
        }
    }

    private func seenAt(_ d: DigestDay) -> Int {
        if let s = model.seenAt[d.day] { return s }
        model.seenAt[d.day] = d.seenAt
        return d.seenAt
    }

    private func message(_ title: String, _ text: String, action: String? = nil, onAction: (() -> Void)? = nil) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.headline)
            Text(text).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let action, let onAction {
                Button(action, action: onAction).buttonStyle(.glassProminent).padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 48)
        .listRowSeparator(.hidden)
    }
}

private struct DigestHead: View {
    let model: DigestModel
    let day: DigestDay?

    var body: some View {
        let label = day.flatMap { digestDate($0.day) }.map { historyDayLabel($0) } ?? "Today"
        let detail = day == nil ? (app.digest.building ? "Building your digest…" : "")
            : app.digest.building ? "Checking for new posts…" : "Updated \(timeAgoPhrase(day!.refreshedAt))"
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.headline)
                if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            DigestMenu(model: model)
        }
    }
}

/// Show read, Previous digests, Rebuild today's digest, Digest settings.
private struct DigestMenu: View {
    let model: DigestModel

    var body: some View {
        let s = app.settings.value
        let days = app.digest.store.days
        Menu {
            Button(s.digestShowRead ? "Hide read" : "Show read", systemImage: s.digestShowRead ? "eye.slash" : "eye") {
                app.settings.setDigestShowRead(!s.digestShowRead)
            }
            Menu("Previous digests", systemImage: "clock.arrow.circlepath") {
                ForEach(days, id: \.day) { d in
                    let today = d.day == app.digest.today()
                    let on = (model.day ?? app.digest.today()) == d.day
                    Button {
                        model.day = today ? nil : d.day
                    } label: {
                        let label = digestDate(d.day).map { historyDayLabel($0) } ?? d.day
                        if on { Label(label, systemImage: "checkmark") } else { Text(label) }
                    }
                }
            }
            Button("Rebuild today's digest", systemImage: "arrow.clockwise") { Task { await model.rebuild() } }
            Button("Digest settings", systemImage: "gearshape") { app.navigator.push(.settingsSection(title: "Digest")) }
        } label: {
            Image(systemName: "ellipsis").frame(width: 32, height: 32).contentShape(.rect)
        }
        .accessibilityLabel("Digest menu")
    }
}

private struct DigestRow: View {
    let model: DigestModel
    let item: DigestItem
    let read: Bool
    let isNew: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let s = app.settings.value
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if isNew {
                    Text("New")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.2), in: .capsule)
                } else {
                    Image(systemName: "info.circle").font(.caption2).foregroundStyle(.tint)
                }
                Text(item.why).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.horizontal, 12)
            PostCard(post: item.post)
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
        .listRowSeparator(.hidden)
        // Left (the trailing side): read / unread. The other side keeps your own swipe.
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if read {
                Button("Unread", systemImage: "circle") { model.markUnread(item) }.tint(.accentColor)
            } else {
                Button("Read", systemImage: "checkmark.circle") { model.markRead(item) }.tint(.accentColor)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if s.swipeActions, let swipe = PostSwipe.make(s.swipePostStart, post: item.post, dismissible: false, frontpage: false, dark: scheme == .dark) {
                Button(swipe.label, systemImage: swipe.systemImage) { swipe.handler() }.tint(Color(swipe.color))
            }
        }
    }
}

/// A digest's day (yyyy-MM-dd) as a date, for its label.
private func digestDate(_ day: String) -> Date? {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .gregorian)
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    return f.date(from: day)
}

/// Today's digest posts not read yet: the count on the Posts chip.
@MainActor func digestUnread() -> Int {
    let read = app.history.ids
    return app.digest.store.days.first { $0.day == app.digest.today() }?.items.count { !read.contains($0.post.id) } ?? 0
}
