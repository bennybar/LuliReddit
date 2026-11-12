import SwiftUI

/// Settings › Explore sections (#161): which sections Explore shows, and in what order.
/// Each change applies at once. Your communities aren't listed: they stay last, with the
/// filter and sort.
struct ExploreSectionsScreen: View {
    @State private var editMode = EditMode.active

    var body: some View {
        let s = app.settings.value
        let entries = s.exploreSections
        List {
            Section {
                ForEach(Array(entries.enumerated()), id: \.element.section) { i, entry in
                    Toggle(isOn: Binding(get: { entry.shown }, set: { v in
                        var next = entries
                        next[i].shown = v
                        app.settings.setExploreSections(next)
                    })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.section.label)
                            if entry.section == .recentlyVisited && !s.showRecentlyVisited {
                                Text("Hidden everywhere while Data & storage › Recently visited is off")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .tint(IlayTheme.accent)
                }
                .onMove { from, to in
                    var next = entries
                    next.move(fromOffsets: from, toOffset: to)
                    app.settings.setExploreSections(next)
                }
            } footer: {
                Text("Drag to reorder. Your communities stay last, with their filter and sort.")
            }
            Section {
                Button("Reset to default") { app.settings.setExploreSections(nil) }
            }
        }
        .environment(\.editMode, $editMode)
        .navigationTitle("Explore sections")
        .navigationBarTitleDisplayMode(.inline)
    }
}
