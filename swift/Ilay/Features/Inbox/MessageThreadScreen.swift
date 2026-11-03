import PhotosUI
import SwiftUI

/// A private-message conversation. The root InboxItem is in NavCache under `fullname` (else fetched).
struct MessageThreadScreen: View {
    let fullname: String
    @State private var root: InboxItem?
    @State private var loadError: Error?
    @State private var attempt = 0

    init(fullname: String) {
        self.fullname = fullname
        _root = State(initialValue: NavCache.get(fullname))
    }

    var body: some View {
        Group {
            if let root {
                MessageThread(root: root)
            } else if let loadError {
                ErrorView(message: loadError) { attempt += 1 }
            } else {
                Loading().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(root?.subject.nilIfEmpty ?? "Message")
        .navigationBarTitleDisplayMode(.inline)
        // Opened from a notification: the thread isn't in memory, so fetch it.
        .task(id: attempt) {
            if root != nil { return }
            loadError = nil
            do {
                guard let thread = try await app.repository.getMessageThread(fullname) else {
                    throw AppException("This message is no longer available.")
                }
                root = thread
            } catch {
                loadError = error
            }
        }
    }
}

private struct MessageThread: View {
    let root: InboxItem
    @Environment(AppNavigator.self) private var nav
    @State private var messages: [InboxItem]
    @State private var reply: String
    @State private var selection: TextSelection?
    @State private var media: MediaAttachment?
    @State private var sending = false
    @State private var pickingImage = false
    @State private var pickingVideo = false
    @State private var pickedImage: PhotosPickerItem?
    @State private var pickedVideo: PhotosPickerItem?

    private var draftKey: String { "msgreply_\(root.fullname)" }

    init(root: InboxItem) {
        self.root = root
        _messages = State(initialValue: [root] + root.replies)
        _reply = State(initialValue: app.drafts.get("msgreply_\(root.fullname)") ?? "")
    }

    var body: some View {
        let me = app.session.username
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(messages) { m in
                        MessageBubble(message: m, mine: !me.isEmpty && m.author.lowercased() == me.lowercased())
                            .id(m.fullname)
                    }
                }
                .padding(12)
            }
            // Chat-style: start at (and follow) the newest message.
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) {
                withAnimation { proxy.scrollTo(messages.last?.fullname, anchor: .bottom) }
            }
        }
        .safeAreaBar(edge: .bottom) { composer }
        // The composer takes the place of the tab bar, as in Messages.
        .toolbar(.hidden, for: .tabBar)
        .onChange(of: reply) { _, new in saveDraft(new) }
        .photosPicker(isPresented: $pickingImage, selection: $pickedImage, matching: .images)
        .photosPicker(isPresented: $pickingVideo, selection: $pickedVideo, matching: .videos)
        .onChange(of: pickedImage) { _, item in load(item, isVideo: false) }
        .onChange(of: pickedVideo) { _, item in load(item, isVideo: true) }
    }

    private var composer: some View {
        VStack(spacing: 6) {
            if let m = media {
                AttachmentPreview(media: m) { media = nil }
            }
            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    Button("Attach image", systemImage: "photo") { pickingImage = true }
                    Button("Attach video", systemImage: "video") { pickingVideo = true }
                    Button("Paste image", systemImage: "doc.on.clipboard") {
                        if let pasted = pasteImageAttachment() { media = pasted } else { nav.showSnackbar("No image on the clipboard.") }
                    }
                } label: {
                    Image(systemName: "plus").frame(width: 28, height: 28)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .disabled(sending)
                .accessibilityLabel("Attach")

                MediaTextEditor(
                    text: $reply, selection: $selection, placeholder: "Reply…", maxLines: 5,
                    onMedia: { media = $0 }
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .rect(cornerRadius: 20))

                Button(action: send) {
                    if sending {
                        ProgressView().frame(width: 28, height: 28)
                    } else {
                        Image(systemName: "arrow.up").frame(width: 28, height: 28)
                    }
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .disabled(sending)
                .accessibilityLabel("Send")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private func saveDraft(_ text: String) {
        let me = app.session.username.lowercased()
        var info = JsonObject()
        info["kind"] = .string("msgreply")
        info["subject"] = .string(root.subject)
        info["to"] = .string(messages.first { $0.author.lowercased() != me }?.author ?? root.author)
        app.drafts.save(draftKey, text, info: info)
    }

    private func load(_ item: PhotosPickerItem?, isVideo: Bool) {
        guard let item else { return }
        Task {
            do {
                media = try await readPicked(item, isVideo: isVideo)
            } catch {
                nav.showSnackbar(errorText(error))
            }
            pickedImage = nil
            pickedVideo = nil
        }
    }

    private func send() {
        var text = reply.trimmed
        let attachment = media
        if text.isEmpty && attachment == nil { return }
        sending = true
        // Reply to the most recent real message in the thread for correct threading.
        guard let target = messages.last(where: { !$0.fullname.hasPrefix("local_") })?.fullname else { return }
        let me = app.session.username
        Task {
            do {
                if let attachment {
                    // Reddit messages are markdown-text only, so host on Catbox + link.
                    let url = try await uploadToCatbox(attachment.bytes, filename: attachment.filename)
                    text = text.isEmpty ? url : "\(text)\n\n\(url)"
                }
                try await app.repository.sendReply(target, text: text)
                app.drafts.clear(draftKey)
                messages.append(InboxItem(
                    fullname: "local_\(messages.count)",
                    kind: .message,
                    author: me.nilIfEmpty ?? "you",
                    subject: root.subject,
                    body: text,
                    createdUtc: nowMillis()
                ))
                reply = ""
                media = nil
            } catch {
                nav.showSnackbar(errorText(error))
            }
            sending = false
        }
    }
}

private struct MessageBubble: View {
    let message: InboxItem
    let mine: Bool
    @Environment(AppNavigator.self) private var nav

    var body: some View {
        HStack {
            if mine { Spacer(minLength: 0) }
            VStack(alignment: .leading, spacing: 4) {
                Text("u/\(message.author) · \(timeAgo(message.createdUtc))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                RedditMarkdown(text: message.body, fontSize: 14, selectable: true, onLinkClick: { nav.openLink($0) })
            }
            .padding(12)
            .background(mine ? AnyShapeStyle(.tint.opacity(0.2)) : AnyShapeStyle(Color(.secondarySystemBackground)), in: .rect(cornerRadius: 18))
            .containerRelativeFrame(.horizontal, alignment: mine ? .trailing : .leading) { width, _ in width * 0.82 }
            if !mine { Spacer(minLength: 0) }
        }
    }
}
