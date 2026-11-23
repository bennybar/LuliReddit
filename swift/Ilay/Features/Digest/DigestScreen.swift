import SwiftUI

/// The Digest on a page of its own (side bar, Profile menu, the "menu only" choice), or as
/// a tab (`tab`: Show Digest in › Bottom tab), with ☰ where a page has Back.
struct DigestScreen: View {
    var tab = false

    var body: some View {
        DigestList()
            .navigationTitle("Digest")
            .navigationBarTitleDisplayMode(tab ? .large : .inline)
            .toolbar {
                if tab { ToolbarItem(placement: .topBarLeading) { SideBarButton() } }
            }
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

    func markRead(_ post: Post) {
        let id = post.id
        app.history.markViewed(post)
        app.navigator.showSnackbar("Marked read", actionLabel: "Undo") { app.history.removeViewed(id) }
        // Off the list once Undo has had its time, not under the finger.
        Task {
            try? await Task.sleep(for: .seconds(4))
            if app.history.ids.contains(id) { gone.insert(id) }
        }
    }

    func markUnread(_ post: Post) {
        app.history.removeViewed(post.id)
        gone.remove(post.id)
        app.navigator.showSnackbar("Marked unread")
    }

    /// The list's rows: what's shown for the day, with its states.
    func rows(top: Bool) -> [DigestRowItem] {
        var out: [DigestRowItem] = top ? [.top, .head] : [.head]
        let s = app.settings.value
        guard let d = app.digest.store.days.first(where: { $0.day == (day ?? app.digest.today()) }) else {
            switch outcome {
            case .signedOut:
                out.append(.message(title: "Sign in to get your digest", text: "It's built from communities you follow.", action: nil))
            case .noCommunities:
                out.append(.message(title: "No communities yet", text: "Star a few favourites in your subscriptions, or choose the communities in Digest settings.", action: .settings))
            case let .failed(text) where !app.digest.building:
                out.append(.message(title: "Couldn't build your digest", text: text, action: .retry))
            default:
                out += (0..<4).map(DigestRowItem.skeleton)
            }
            return out
        }
        if d.aiFailed && s.digestAi { out.append(.note("AI wasn't available; picked by activity")) }
        if s.digestAi && s.digestOverview, let overview = d.overview { out.append(.overview(overview)) }
        if d.items.isEmpty {
            out.append(.message(title: "Nothing notable today", text: "No post stands out in your communities yet. Pull down to check again later.", action: nil))
            return out
        }
        let read = app.history.ids
        let shownIds = Set(d.items.filter { s.digestShowRead || !read.contains($0.post.id) || (!readAtOpen.contains($0.post.id) && !gone.contains($0.post.id)) }.map(\.post.id))
        if shownIds.isEmpty {
            out.append(.message(title: "You're all caught up", text: "You've read everything in this digest.", action: .showRead))
            return out
        }
        let seen: Int
        if let known = seenAt[d.day] { seen = known } else { seenAt[d.day] = d.seenAt; seen = d.seenAt }
        // The AI's order only means something while it's on.
        let order = DigestOrder.of(s.digestOrder)
        // Grouped before hiding read posts, so a community keeps its place as they go.
        for group in orderDigest(d.items, order == .ai && !s.digestAi ? .notable : order) {
            let items = group.items.filter { shownIds.contains($0.post.id) }
            if items.isEmpty { continue }
            out.append(.community(group.community))
            for item in items { out.append(.post(item, isNew: item.addedAt > d.builtAt && item.addedAt > seen)) }
        }
        return out
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

/// A row of the Digest's list.
enum DigestRowItem {
    case top
    case head
    case note(String)
    case overview(String)
    case message(title: String, text: String, action: DigestAction?)
    case community(String)
    case post(DigestItem, isNew: Bool)
    case skeleton(Int)

    var key: AnyHashable {
        switch self {
        case .top: "top"
        case .head: "head"
        case let .note(t): "note|\(t)"
        case let .overview(t): "overview|\(t.hashValue)"
        case let .message(title, _, _): "message|\(title)"
        case let .community(c): "community|\(c.lowercased())"
        // Its line and New mark are part of it: a change re-renders the row.
        case let .post(item, isNew): "post|\(item.post.id)|\(item.why.hashValue)|\(isNew)"
        case let .skeleton(i): "skeleton|\(i)"
        }
    }
}

/// What an empty state's button does.
enum DigestAction {
    case showRead, settings, retry
}

/// The Digest as a list, under `top` (Posts: its title and chips): the feed's own list, so
/// cards follow Settings' layout and swipe as in the feed (left: read / unread; right:
/// your own swipe). Builds today's when it's missing or stale, and marks it seen on leaving.
struct DigestList<Top: View>: View {
    private let top: (() -> Top)?
    @State private var model = DigestModel()
    @State private var source: PagedSource<DigestRowItem>

    init(@ViewBuilder top: @escaping () -> Top) { self.init(optionalTop: top) }

    fileprivate init(optionalTop top: (() -> Top)?) {
        self.top = top
        let model = DigestModel()
        _model = State(initialValue: model)
        var first = true
        let hasTop = top != nil
        _source = State(initialValue: PagedSource { [model] _ in
            // The first load is what's stored; a pull asks for what's new.
            if first {
                first = false
            } else {
                await model.refresh(manual: true)
            }
            return Listing(items: model.rows(top: hasTop))
        })
    }

    var body: some View {
        let rows = model.rows(top: top != nil)
        PagedList(
            source: source,
            itemKey: { $0.key },
            emptyLabel: "",
            contentType: { row in
                if case let .post(item, _) = row { return pagedPostKind(item.post) }
                return 20
            },
            staleAfterMillis: .max,
            posts: PagedPostRows(post: { row in
                if case let .post(item, _) = row { return item.post }
                return nil
            }, swipes: { [model] post in
                let s = app.settings.value
                let dark = UITraitCollection.current.userInterfaceStyle == .dark
                let accent = UIColor(IlayTheme.accent)
                let read = app.history.ids.contains(post.id)
                let trailing = read
                    ? PostSwipe(systemImage: "circle", color: accent, label: "Unread") { model.markUnread(post) }
                    : PostSwipe(systemImage: "checkmark.circle", color: accent, label: "Read") { model.markRead(post) }
                let leading = s.swipeActions ? PostSwipe.make(s.swipePostStart, post: post, dismissible: false, frontpage: false, dark: dark) : nil
                return (leading, trailing)
            })
        ) { row in
            switch row {
            case .top: top?()
            case .head: DigestHead(model: model).padding(.horizontal, 16).padding(.vertical, 4)
            case let .note(text):
                Label(text, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.bottom, 4)
            case let .overview(text):
                VStack(alignment: .leading, spacing: 6) {
                    Label("Today in your communities", systemImage: "sparkles").font(.subheadline.weight(.semibold)).foregroundStyle(.tint)
                    Text(text)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.pagedCard, in: .rect(cornerRadius: 20))
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            case let .message(title, text, action):
                DigestMessage(title: title, text: text, action: action, model: model)
            case let .community(name):
                Text("r/\(name)").font(.subheadline.weight(.semibold)).foregroundStyle(.tint)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 4)
            case let .post(item, isNew):
                VStack(alignment: .leading, spacing: 4) {
                    DigestWhy(why: item.why, isNew: isNew).padding(.horizontal, 16)
                    PagedPostRow(post: item.post)
                }
            case .skeleton: PostSkeleton()
            }
        }
        .onChange(of: rows.map(\.key), initial: true) { source.show(rows) }
        .task { await model.start() }
        .onDisappear { app.digest.markSeen() }
    }
}

extension DigestList where Top == EmptyView {
    /// The Digest on its own page: no title or chips above it.
    init() { self.init(optionalTop: nil) }
}

private struct DigestWhy: View {
    let why: String
    let isNew: Bool

    var body: some View {
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
            Text(why).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

private struct DigestMessage: View {
    let title: String
    let text: String
    let action: DigestAction?
    let model: DigestModel

    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(.headline)
            Text(text).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let action {
                let label = switch action {
                case .showRead: "Show read"
                case .settings: "Choose communities"
                case .retry: "Retry"
                }
                Button(label) {
                    switch action {
                    case .showRead: app.settings.setDigestShowRead(true)
                    case .settings: app.navigator.push(.settingsSection(title: "Digest"))
                    case .retry: Task { await model.refresh(manual: false) }
                    }
                }
                .buttonStyle(.glassProminent)
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 48)
    }
}

private struct DigestHead: View {
    let model: DigestModel

    var body: some View {
        let day = app.digest.store.days.first { $0.day == (model.day ?? app.digest.today()) }
        let label = day.flatMap { digestDate($0.day) }.map { historyDayLabel($0) } ?? "Today"
        let detail = app.digest.building ? (app.digest.progress ?? (day == nil ? "Building your digest…" : "Checking for new posts…"))
            : day.map { "Updated \(timeAgoPhrase($0.refreshedAt))" } ?? ""
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
