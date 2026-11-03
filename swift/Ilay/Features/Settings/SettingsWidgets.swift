import SwiftUI
import UniformTypeIdentifiers

/// A setting's title with its explanation under it.
struct SettingLabel: View {
    let title: String
    var subtitle: String? = nil
    var titleColor: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).foregroundStyle(titleColor ?? .primary)
            if let subtitle {
                // The colour, not the style: inside a Button the style would follow the tint.
                Text(subtitle).font(.footnote).foregroundStyle(Color.secondary)
            }
        }
    }
}

/// One choice in a picker page.
struct PickOption<T: Hashable> {
    let value: T
    let label: String
    var subtitle: String? = nil
    /// SF Symbol.
    var icon: String? = nil
}

/// One row of the settings list. `search` = its title + subtitle, nil = not searchable.
struct SettingEntry: Identifiable {
    let id: String
    let section: String
    /// Splits a category's page into list sections (Kotlin's `divider`).
    let group: Int
    let title: String
    let search: String?
    let content: AnyView
}

/// What a text-entry prompt returned.
enum TextResult {
    case save(String)
    case remove
}

/// A single-field prompt. `secret` hides the text; `removable` adds "Remove".
struct TextPrompt {
    let title: String
    var hint = ""
    var note: String? = nil
    var secret = false
    var removable = false
    var keyboard: UIKeyboardType = .default
    let onDone: (TextResult) -> Void
}

/// The exported backup, for `fileExporter`.
struct BackupDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]

    let text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// What the rows ask of their screen: prompts and the file panels, which SwiftUI
/// wants attached to a view.
@MainActor @Observable
final class SettingsPrompts {
    var text: TextPrompt?
    var input = ""
    var exporting: BackupDocument?
    var importing = false
    /// Bumped after a key changes (its row re-reads the key's state), and after a
    /// switch was refused (so it flips back).
    var refresh = 0

    func ask(_ prompt: TextPrompt, initial: String = "") {
        input = initial
        text = prompt
    }
}

/// A yes/no alert. True if confirmed.
@MainActor func confirmDialog(_ title: String, _ text: String, _ confirm: String, cancel: String = "Cancel", destructive: Bool = false) async -> Bool {
    await Overlays.alert(title, message: text, buttons: [
        (title: cancel, role: .cancel, value: false),
        (title: confirm, role: destructive ? .destructive : nil, value: true),
    ]) == true
}

/// An info alert with a single `close` button.
@MainActor func infoDialog(_ title: String, _ text: String, close: String = "Close") async {
    let _: Bool? = await Overlays.alert(title, message: text, buttons: [(title: close, role: .cancel, value: true)])
}

/// The subreddits hidden from the front page ("Hide r/… for 7 days"), each with Unhide.
private struct HiddenSubsSheet: View {
    var body: some View {
        let subs = app.hiddenHomeSubs.ids.sorted()
        NavigationStack {
            List {
                if subs.isEmpty {
                    Text("None. Hide one from a post's ⋯ menu or a swipe; it comes back after 7 days.")
                        .foregroundStyle(.secondary)
                }
                ForEach(subs, id: \.self) { sub in
                    HStack {
                        Text("r/\(sub)")
                        Spacer()
                        Button("Unhide") { app.hiddenHomeSubs.remove(sub) }.buttonStyle(.borderless)
                    }
                }
            }
            .navigationTitle("Hidden subreddits")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

@MainActor func showHiddenSubsSheet() {
    Overlays.launch(detents: [.medium, .large]) { _ in HiddenSubsSheet() }
}
