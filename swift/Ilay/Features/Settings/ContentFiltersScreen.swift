import SwiftUI

/// Manage content filters: keywords (title), domains, subreddits and flairs
/// that hide matching posts across all feeds.
struct ContentFiltersScreen: View {
    var body: some View {
        let store = app.contentFilters
        let filters = store.value
        List {
            Section {
                FilterSection(hint: "e.g. spoiler", type: "keyword", values: filters.keywords)
            } header: {
                Text("Title keywords")
            } footer: {
                Text("Hide posts that match these. Filters are stored only on this device and apply to every feed.")
            }
            Section("Domains") {
                FilterSection(hint: "e.g. twitter.com", type: "domain", values: filters.domains)
            }
            Section {
                FilterSection(hint: "e.g. politics", type: "subreddit", values: filters.subreddits)
            } header: {
                Text("Subreddits")
            } footer: {
                Text("Hidden from the frontpage, For You, Popular and custom feeds. Its own page still shows it.")
            }
            Section("Flairs") {
                FilterSection(hint: "e.g. Politics", type: "flair", values: filters.flairs)
            }
            Section {
                Toggle(isOn: Binding(get: { filters.hideNsfw }, set: store.setHideNsfw)) {
                    SettingLabel(title: "Hide NSFW posts", subtitle: "Remove them from feeds and search instead of blurring")
                }
                Toggle(isOn: Binding(get: { filters.collapseAutoMod }, set: store.setCollapseAutoMod)) {
                    SettingLabel(title: "Collapse AutoModerator", subtitle: "Start AutoModerator comments collapsed")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Content filters")
    }
}

private struct FilterSection: View {
    let hint: String
    let type: String
    let values: [String]

    @State private var text = ""

    private func add() {
        app.contentFilters.add(type, text)
        text = ""
    }

    var body: some View {
        HStack {
            TextField(hint, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(add)
            Button("Add", action: add)
                .buttonStyle(.borderless)
                .disabled(text.isBlank)
        }
        ForEach(values, id: \.self) { value in
            HStack {
                Text(value)
                Spacer()
                Button("Remove \(value)", systemImage: "xmark.circle.fill") {
                    app.contentFilters.remove(type, value)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
        }
    }
}
