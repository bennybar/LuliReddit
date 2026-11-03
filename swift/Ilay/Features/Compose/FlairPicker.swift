import SwiftUI

/// What the post flair picker returned: `flair` nil is "No flair"; an editable one carries your text.
struct LinkFlairPick {
    let flair: Flair?
}

/// Reddit's longest flair text.
private let flairTextLimit = 64

/// The flairs whose words contain `query` (any case); all of them for a blank query.
func filterFlairs(_ flairs: [Flair], _ query: String) -> [Flair] {
    let q = query.trimmed
    if q.isEmpty { return flairs }
    return flairs.filter { ($0.label?.text ?? $0.text).localizedCaseInsensitiveContains(q) }
}

/// Picks a post flair in r/`subreddit` (#87, #88): a searchable sheet of the flairs as
/// their own coloured labels, "No flair", a check on `current`; an editable flair then
/// asks for its text. Nil when cancelled.
@MainActor func pickLinkFlair(_ subreddit: String, flairs: [Flair], current: Flair?) async -> LinkFlairPick? {
    let picked: LinkFlairPick? = await Overlays.show(detents: [.medium, .large]) { done in
        LinkFlairPicker(subreddit: subreddit, flairs: flairs, current: current, done: done)
    }
    guard let picked else { return nil }
    guard let f = picked.flair, f.editable else { return picked }
    guard let written = await askText(
        "Flair text", label: "Flair text", confirm: "Save",
        initial: current.flatMap { $0.id == f.id ? $0.text : nil } ?? f.text
    ) else { return nil }
    let text = String(written.trimmed.prefix(flairTextLimit)).nilIfEmpty ?? f.text
    // The label shows your words now, not the template's.
    return LinkFlairPick(flair: f.with { $0.text = text; $0.label = UserFlair(parts: [FlairPart(text: text)]) })
}

private struct LinkFlairPicker: View {
    let subreddit: String
    let flairs: [Flair]
    let current: Flair?
    let done: (LinkFlairPick?) -> Void

    @State private var query = ""

    var body: some View {
        let shown = filterFlairs(flairs, query)
        NavigationStack {
            List {
                if query.isBlank {
                    row(checked: current == nil, pick: LinkFlairPick(flair: nil)) { Text("No flair") }
                }
                ForEach(shown, id: \.id) { f in
                    row(subtitle: f.editable ? "You can change the text" : nil, checked: f.id == current?.id, pick: LinkFlairPick(flair: f)) {
                        FlairTemplateLabel(flair: f)
                    }
                }
            }
            .overlay { if shown.isEmpty { ContentUnavailableView.search(text: query) } }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search flairs")
            .navigationTitle("Flair in r/\(subreddit)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { done(nil) }
                }
            }
        }
    }

    private func row(subtitle: String? = nil, checked: Bool, pick: LinkFlairPick, @ViewBuilder title: () -> some View) -> some View {
        Button {
            done(pick)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    title().foregroundStyle(.primary)
                    if let subtitle { Text(subtitle).font(.footnote).foregroundStyle(.secondary) }
                }
                Spacer()
                if checked { Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(.tint) }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// A post flair as Reddit styles it: its background colour and light or dark text, emoji inline.
struct FlairTemplateLabel: View {
    let flair: Flair

    var body: some View {
        let bg = flair.backgroundColor.map {
            Color(red: Double(($0 >> 16) & 0xFF) / 255, green: Double(($0 >> 8) & 0xFF) / 255, blue: Double($0 & 0xFF) / 255)
        }
        HStack(spacing: 3) {
            if let label = flair.label {
                ForEach(Array(label.parts.enumerated()), id: \.offset) { _, part in
                    if let url = part.emojiUrl.flatMap(URL.init(string:)) {
                        RemoteImage(url: url, contentMode: .fit, maxPixelSize: 48) { Color.clear }
                            .frame(width: 16, height: 16)
                    } else if let text = part.text {
                        Text(verbatim: text.trimmed)
                    }
                }
            } else {
                Text(verbatim: flair.text)
            }
        }
        .lineLimit(2)
        .font(.subheadline)
        .foregroundStyle(bg == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(flair.lightText ? Color.white : Color.black.opacity(0.85)))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(bg.map(AnyShapeStyle.init) ?? AnyShapeStyle(Color(.tertiarySystemFill)), in: .rect(cornerRadius: 6))
    }
}
