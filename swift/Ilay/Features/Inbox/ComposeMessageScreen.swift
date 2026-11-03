import SwiftUI

private let draftKey = "compose_msg"

/// A new private message, to `to` when given. The draft survives leaving the screen.
/// Pushed from a route, or in a sheet (`onCancel` then closes it).
struct ComposeMessageScreen: View {
    let to: String?
    var onCancel: (() -> Void)? = nil

    @Environment(AppNavigator.self) private var nav
    @Environment(\.dismiss) private var dismiss
    @State private var toField: String
    @State private var subject: String
    @State private var messageBody: String
    @State private var selection: TextSelection?
    @State private var busy = false
    @State private var error: String?
    @State private var media: MediaAttachment?
    // A picked file still being read: sending now would go without it.
    @State private var attaching = false

    init(to: String?, onCancel: (() -> Void)? = nil) {
        self.to = to
        self.onCancel = onCancel
        // Restore the saved draft, unless it was to someone else than `to`.
        var draft = app.drafts.get(draftKey).flatMap(parseJsonOrNull)
        let draftTo = draft["to"].str() ?? ""
        if let to, !to.isEmpty, !draftTo.isEmpty, draftTo.lowercased() != to.lowercased() { draft = nil }
        _toField = State(initialValue: to?.nilIfEmpty ?? draft["to"].str() ?? "")
        _subject = State(initialValue: draft["subject"].str() ?? "")
        _messageBody = State(initialValue: draft["body"].str() ?? "")
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 2) {
                    Text("u/").foregroundStyle(.secondary)
                    TextField("To", text: $toField)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                TextField("Subject", text: $subject)
            }
            Section {
                MediaTextEditor(
                    text: $messageBody, selection: $selection, placeholder: "Message (Markdown)",
                    minLines: 6, maxLines: 14,
                    onMedia: { media = $0; error = nil }
                )
                LengthCounter(text: messageBody, limit: TextLimit.comment)
                MarkdownToolbar(text: $messageBody, selection: $selection)
                AttachmentControls(
                    media: Binding(get: { media }, set: { media = $0; error = nil }), loading: $attaching,
                    onError: { error = $0 }, catboxForImages: true
                ) { EmptyView() }
            }
            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle("New message")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onCancel {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark", role: .cancel, action: onCancel)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(action: send) {
                    if busy {
                        ProgressView()
                    } else {
                        Label("Send", systemImage: "arrow.up")
                    }
                }
                .buttonStyle(.glassProminent)
                .disabled(busy || attaching || redditLength(messageBody.trimmed) > TextLimit.comment)
            }
        }
        .onChange(of: toField) { saveDraft() }
        .onChange(of: subject) { saveDraft() }
        .onChange(of: messageBody) { saveDraft() }
    }

    private func saveDraft() {
        let draft: JsonElement = ["to": .string(toField), "subject": .string(subject), "body": .string(messageBody)]
        var info = JsonObject()
        info["kind"] = .string("msg")
        app.drafts.save(draftKey, draft.encoded(), info: info)
    }

    private func send() {
        let recipient = toField.trimmed.removePrefix("/").removePrefix("u/")
        let subj = subject.trimmed
        var text = messageBody.trimmed
        let attachment = media
        if recipient.isEmpty || subj.isEmpty || (text.isEmpty && attachment == nil) {
            error = "Recipient, subject and a message or attachment are required."
            return
        }
        busy = true
        error = nil
        Task {
            do {
                if let attachment {
                    // Reddit messages are markdown-text only, so host on Catbox + link.
                    let url = try await uploadToCatbox(attachment.bytes, filename: attachment.filename)
                    text = text.isEmpty ? url : "\(text)\n\n\(url)"
                }
                try await app.repository.composeMessage(to: recipient, subject: subj, text: text)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                app.drafts.clear(draftKey)
                nav.showSnackbar("Message sent")
                if let onCancel { onCancel() } else { dismiss() }
            } catch {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                busy = false
                self.error = errorText(error)
            }
        }
    }
}
