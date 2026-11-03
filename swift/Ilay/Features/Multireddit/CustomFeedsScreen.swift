import SwiftUI

extension Multireddit {
    /// Who owns a feed path (/user/<name>/m/<feed>), else the signed-in user.
    @MainActor func owner() -> String { owner(fallback: app.session.username) }

    func owner(fallback: String) -> String {
        let parts = path.split(separator: "/").map(String.init)
        return parts.count >= 4 && parts[0] == "user" ? parts[1] : fallback
    }
}

/// Every custom feed of yours, in one list (Explore's row gets long).
struct CustomFeedsScreen: View {
    var body: some View {
        let nav = app.navigator
        Group {
            switch app.feed.multireddits {
            case .loading:
                Loading().frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .error(error):
                ErrorView(message: "Couldn't load your custom feeds: \(friendlyError(error))", onRetry: { app.feed.loadMultireddits(force: true) })
            case let .data(multis):
                if multis.isEmpty {
                    ContentUnavailableView {
                        Label("No custom feeds yet", systemImage: "rectangle.stack")
                    } description: {
                        Text("A custom feed mixes the communities you pick into one feed.")
                    } actions: {
                        Button("New feed") { Task { _ = await createMulti(username: app.session.username) } }.buttonStyle(.glass)
                    }
                } else {
                    List(multis, id: \.path) { multi in
                        NavigationLink(value: Route.multireddit(username: multi.owner(), name: multi.name)) {
                            HStack(spacing: 12) {
                                Image(systemName: "rectangle.stack")
                                    .frame(width: 40, height: 40)
                                    .background(Color(.secondarySystemFill), in: .circle)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(multi.displayName.nilIfEmpty ?? multi.name).lineLimit(1)
                                    Text("\(multi.subreddits.count) communities · \(multi.visibility == "public" ? "Public" : "Private")")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Button("Manage", systemImage: "slider.horizontal.3") {
                                    nav.push(.manageMultireddit(username: multi.owner(), name: multi.name))
                                }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable { app.feed.loadMultireddits(force: true) }
                }
            }
        }
        .navigationTitle("Custom feeds")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("New feed", systemImage: "plus") { Task { _ = await createMulti(username: app.session.username) } }
            }
        }
        .task { app.feed.loadMultireddits(force: true) }
    }
}

/// Asks for a name and creates a custom feed (starting with `subreddits`). True if one was made.
@MainActor func createMulti(username: String, subreddits: [String] = []) async -> Bool {
    guard let name = await askText("New custom feed", label: "Feed name", confirm: "Create"), !name.isEmpty else { return false }
    do {
        try await app.repository.createMultireddit(username: username, name: name, subreddits: subreddits)
        app.feed.loadMultireddits(force: true)
        return true
    } catch {
        var message = error.localizedDescription
        if message.hasPrefix("Exception: ") { message.removeFirst("Exception: ".count) }
        app.navigator.showSnackbar("Could not create feed: \(message)")
        return false
    }
}

/// One line of text, in a small sheet (an alert can't be awaited with a field in it here).
/// `prefix`: shown before the field ("r/"). Trimmed; nil when cancelled.
@MainActor func askText(_ title: String, label: String, confirm: String, initial: String = "", prefix: String? = nil, plain: Bool = false) async -> String? {
    await Overlays.show(detents: [.height(190)]) { done in
        AskTextSheet(title: title, label: label, confirm: confirm, initial: initial, prefix: prefix, plain: plain, onDone: done)
    }
}

private struct AskTextSheet: View {
    let title: String
    let label: String
    let confirm: String
    let prefix: String?
    let plain: Bool
    let onDone: (String?) -> Void

    @State private var text: String
    @FocusState private var focused: Bool

    init(title: String, label: String, confirm: String, initial: String, prefix: String?, plain: Bool, onDone: @escaping (String?) -> Void) {
        self.title = title
        self.label = label
        self.confirm = confirm
        self.prefix = prefix
        self.plain = plain
        self.onDone = onDone
        _text = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            Form {
                HStack(spacing: 2) {
                    if let prefix { Text(prefix).foregroundStyle(.secondary) }
                    TextField(label, text: $text)
                        .focused($focused)
                        .submitLabel(.done)
                        .autocorrectionDisabled(plain)
                        .textInputAutocapitalization(plain ? .never : .sentences)
                        .onSubmit { onDone(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { onDone(nil) } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirm) { onDone(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
                }
            }
        }
        .onAppear { focused = true }
    }
}

struct FeedEdit {
    let displayName: String
    let description: String
    let visibility: String
}

/// Name, description and Public / Private for a custom feed (`title`: Edit / Copy).
@MainActor func editFeedDialog(title: String, confirm: String, name: String, description: String, visibility: String) async -> FeedEdit? {
    await Overlays.show(detents: [.medium]) { done in
        EditFeedSheet(title: title, confirm: confirm, name: name, description: description, visibility: visibility, onDone: done)
    }
}

private struct EditFeedSheet: View {
    let title: String
    let confirm: String
    let onDone: (FeedEdit?) -> Void

    @State private var name: String
    @State private var description: String
    @State private var visibility: String

    init(title: String, confirm: String, name: String, description: String, visibility: String, onDone: @escaping (FeedEdit?) -> Void) {
        self.title = title
        self.confirm = confirm
        self.onDone = onDone
        _name = State(initialValue: name)
        _description = State(initialValue: description)
        _visibility = State(initialValue: visibility)
    }

    var body: some View {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name).textInputAutocapitalization(.sentences)
                    TextField("Description (optional)", text: $description, axis: .vertical).lineLimit(2...4)
                }
                Section {
                    ConnectedChoice(options: [(key: "private", label: "Private"), (key: "public", label: "Public")], selected: visibility, onSelect: { visibility = $0 })
                } footer: {
                    Text(visibility == "public" ? "Anyone with the link can see it, follow it or copy it." : "Only you can see it.")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { onDone(nil) } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirm) {
                        onDone(FeedEdit(displayName: trimmedName, description: description.trimmingCharacters(in: .whitespacesAndNewlines), visibility: visibility))
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
    }
}
