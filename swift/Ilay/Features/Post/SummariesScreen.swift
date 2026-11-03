import SwiftUI

/// Profile → Summaries: every post summarized with AI, newest first, with its summary
/// and a link back. Select (or long-press one) to delete several, or all.
struct SummariesScreen: View {
    @State private var query = ""
    @State private var selection = Set<String>()
    @State private var editMode: EditMode = .inactive

    private var items: [SavedSummary] { app.summaries.items }

    private var shown: [SavedSummary] {
        let q = query.trimmed.lowercased()
        if q.isEmpty { return items }
        return items.filter { $0.title.lowercased().contains(q) || $0.subreddit.lowercased().contains(q) || $0.text.lowercased().contains(q) }
    }

    private var selecting: Bool { editMode.isEditing }

    var body: some View {
        let shown = shown
        Group {
            if items.isEmpty {
                ContentUnavailableView(
                    "No summaries yet",
                    systemImage: "sparkles",
                    description: Text("Summarize a thread with the ✦ button in a post and it's kept here.")
                )
            } else if shown.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                List(shown, id: \.postId, selection: $selection) { s in
                    SummaryRow(summary: s, selecting: selecting)
                        .swipeActions {
                            Button("Remove", systemImage: "trash", role: .destructive) { app.summaries.remove(s.postId) }
                        }
                        .contextMenu {
                            if !selecting {
                                Button("Select", systemImage: "checkmark.circle") {
                                    selection = [s.postId]
                                    editMode = .active
                                }
                            }
                            Button("Copy summary", systemImage: "doc.on.doc") { copyToClipboard(s.text) }
                            Button("Remove", systemImage: "trash", role: .destructive) { app.summaries.remove(s.postId) }
                        }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(selecting ? "\(selection.count) selected" : "Summaries")
        .navigationBarTitleDisplayMode(selecting ? .inline : .large)
        .environment(\.editMode, $editMode)
        .modifier(SummarySearch(enabled: items.count > 3, query: $query))
        .toolbar {
            if selecting {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) {
                        selection = []
                        editMode = .inactive
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    let allShown = !shown.isEmpty && shown.allSatisfy { selection.contains($0.postId) }
                    Button(allShown ? "Select none" : "Select all") {
                        selection = allShown ? [] : Set(shown.map(\.postId))
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Delete selected", systemImage: "trash", role: .destructive, action: deleteSelected)
                        .disabled(selection.isEmpty)
                }
            } else if !items.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Select", systemImage: "checklist") { editMode = .active }
                }
            }
        }
    }

    private func deleteSelected() {
        let ids = selection
        let n = ids.count
        Task {
            let ok = await Overlays.alert(
                n == 1 ? "Delete this summary?" : "Delete \(n) summaries?",
                message: "They're removed from this device. The posts stay on Reddit.",
                buttons: [(title: "Delete", role: ButtonRole?.some(.destructive), value: true), (title: "Cancel", role: ButtonRole?.some(.cancel), value: false)]
            )
            guard ok == true else { return }
            app.summaries.removeAll(ids)
            selection = []
            editMode = .inactive
        }
    }
}

private struct SummarySearch: ViewModifier {
    let enabled: Bool
    @Binding var query: String

    func body(content: Content) -> some View {
        if enabled {
            content.searchable(text: $query, prompt: "Search summaries")
        } else {
            content
        }
    }
}

private struct SummaryRow: View {
    let summary: SavedSummary
    let selecting: Bool
    @State private var expanded = false

    private func open() {
        let s = summary
        let route = s.permalink.isEmpty
            ? Route.post(subreddit: s.subreddit.nilIfEmpty ?? "_", postId: s.postId)
            : URL(string: "https://reddit.com\(s.permalink)").flatMap(routeForRedditUrl)
        if let route { app.navigator.push(route) }
    }

    var body: some View {
        let s = summary
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(verbatim: "r/\(s.subreddit) · \(s.style) · \(timeAgo(s.createdAt))").lineLimit(1)
            } icon: {
                Image(systemName: "sparkles").foregroundStyle(.tint)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(verbatim: s.title).font(.headline).lineLimit(3)
            RedditMarkdown(text: s.text, fontSize: 14, maxLines: expanded ? nil : 6, selectable: expanded)
            if !selecting {
                HStack {
                    Button(expanded ? "Show less" : "Full summary") { expanded.toggle() }
                    Spacer()
                    Button("Open post", systemImage: "arrow.up.right", action: open)
                }
                .font(.footnote.weight(.medium))
                .buttonStyle(.borderless)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }
}
