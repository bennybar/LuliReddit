import SwiftUI

private let DAY = 24 * 60 * 60 * 1000

/// Filters history by subreddit (nil: all) and by words in its title or subreddit.
func filterHistory(_ history: [HistoryEntry], query: String, subreddit: String?) -> [HistoryEntry] {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return history.filter {
        (subreddit == nil || $0.subreddit == subreddit) && (q.isEmpty || $0.title.lowercased().contains(q) || $0.subreddit.lowercased().contains(q))
    }
}

/// Recently viewed posts (on-device only), searchable and filterable by subreddit.
struct HistoryScreen: View {
    @State private var query = ""
    @State private var subFilterRaw: String? // nil = all subreddits
    /// Select mode (#155): pick several rows and remove them together (Undo puts them back).
    @State private var selection = Set<String>()
    @State private var editMode = EditMode.inactive

    var body: some View {
        let history = app.history.state
        // "Hide NSFW posts" (Content filters) covers History too; entries from before it
        // was recorded have no flag and stay shown.
        let visible = app.contentFilters.value.hideNsfw ? history.filter { !$0.nsfw } : history
        let subs = Set(visible.map(\.subreddit)).sorted()
        // Keep the chosen filter valid if its subreddit dropped out of history.
        let subFilter = subFilterRaw.flatMap { subs.contains($0) ? $0 : nil }

        Group {
            if history.isEmpty {
                ContentUnavailableView {
                    Label("No history yet", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text(note)
                }
            } else if visible.isEmpty {
                ContentUnavailableView {
                    Label("NSFW posts are hidden", systemImage: "eye.slash")
                } description: {
                    Text(note)
                }
            } else {
                let filtered = filterHistory(visible, query: query, subreddit: subFilter)
                // Each community's picture (#155): saved with what's read since this version;
                // older entries borrow it from a newer one, or from Recently visited.
                let icons = historyIcons(history)
                List(selection: $selection) {
                    Section {
                        ForEach(filtered, id: \.id) { row($0, icon: icons[$0.subreddit.lowercased()]) }
                    } footer: {
                        Text(note)
                    }
                }
                .listStyle(.insetGrouped)
                .overlay {
                    if filtered.isEmpty { ContentUnavailableView.search }
                }
                .searchable(text: $query, prompt: "Search history")
                .environment(\.editMode, $editMode)
            }
        }
        .navigationTitle("History")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if editMode.isEditing {
                    Button("Remove", systemImage: "trash", role: .destructive) {
                        let gone = history.filter { selection.contains($0.id) }
                        selection = []
                        editMode = .inactive
                        gone.forEach { app.history.removeViewed($0.id) }
                        app.navigator.showSnackbar("Removed \(gone.count) from History", actionLabel: "Undo") { gone.forEach(app.history.restore) }
                    }
                    .disabled(selection.isEmpty)
                }
                if !visible.isEmpty {
                    Button(editMode.isEditing ? "Done" : "Select") {
                        selection = []
                        editMode = editMode.isEditing ? .inactive : .active
                    }
                }
                if !subs.isEmpty && !editMode.isEditing {
                    Menu("Filter by subreddit", systemImage: subFilter == nil ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill") {
                        Picker("Filter by subreddit", selection: $subFilterRaw) {
                            Text("All subreddits").tag(String?.none)
                            ForEach(subs, id: \.self) { Text("r/\($0)").tag(String?.some($0)) }
                        }
                        .pickerStyle(.inline)
                    }
                }
                if !history.isEmpty {
                    Menu("Clear history", systemImage: "trash") {
                        Button("Clear older than 7 days") {
                            app.history.clearOlderThan(7 * DAY)
                            app.recentSubreddits.clearOlderThan(7 * DAY)
                        }
                        Button("Clear older than 30 days") {
                            app.history.clearOlderThan(30 * DAY)
                            app.recentSubreddits.clearOlderThan(30 * DAY)
                        }
                        Button("Clear all history", role: .destructive) {
                            app.history.clear()
                            app.recentSubreddits.clear()
                            app.threadVisits.clear()
                        }
                    }
                }
            }
        }
    }

    private var note: String {
        "Recently viewed posts are stored only on this device — Reddit does not sync viewing history to third-party apps."
    }

    private func historyIcons(_ history: [HistoryEntry]) -> [String: String] {
        var icons: [String: String] = [:]
        for r in app.recentSubreddits.state { if let i = r.iconUrl { icons[r.name.lowercased()] = i } }
        for h in history.reversed() { if let i = h.icon { icons[h.subreddit.lowercased()] = i } }
        return icons
    }

    @ViewBuilder private func row(_ e: HistoryEntry, icon: String?) -> some View {
        let route = e.permalink.isEmpty
            ? Route.post(subreddit: e.subreddit.nilIfEmpty ?? "_", postId: e.id)
            : URL(string: "https://reddit.com\(e.permalink)").flatMap(routeForRedditUrl)
        NavigationLink(value: route) {
            HStack(spacing: 12) {
                LetterAvatar(name: e.subreddit.nilIfEmpty ?? "?", size: 36, imageUrl: icon)
                VStack(alignment: .leading, spacing: 2) {
                    // The community opens its page (#155).
                    Button("r/\(e.subreddit)") { if !e.subreddit.isEmpty { app.navigator.push(.subreddit(name: e.subreddit)) } }
                        .buttonStyle(.borderless)
                        .font(.footnote.weight(.semibold))
                        .disabled(editMode.isEditing)
                    Text(e.title).lineLimit(2)
                }
            }
        }
        .swipeActions(edge: .trailing) {
            Button("Remove", systemImage: "trash", role: .destructive) {
                app.history.removeViewed(e.id)
                // Swiped by accident: Undo puts it back (#154).
                app.navigator.showSnackbar("Removed from History", actionLabel: "Undo") { app.history.restore(e) }
            }
        }
    }
}
