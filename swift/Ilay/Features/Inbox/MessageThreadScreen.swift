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
                MessageThread(threads: [root], conversation: false)
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

/// Every loaded message with one person (#315), `key` as `Correspondent.key`: the Messages
/// list's threads with them, oldest first, as one chat. Their new ones are read on opening.
struct ConversationScreen: View {
    let key: String
    /// Taken once, as it opens: new mail or marking read doesn't rebuild the chat under the
    /// reply being typed. The "N new" line keeps showing where the new ones began.
    @State private var conv: Conversation?

    var body: some View {
        let state = app.inbox.tab("messages")
        Group {
            if let conv {
                MessageThread(threads: conv.threads, conversation: true)
            } else if state.loading {
                Loading().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = state.error {
                ErrorView(message: "Could not load messages.\n\(friendlyError(error))") { app.inbox.refresh("messages") }
            } else {
                ContentUnavailableView("These messages aren't loaded any more.", systemImage: "tray")
            }
        }
        .navigationTitle(conv.map { $0.with.isSubreddit ? subredditName($0.with.name) : userName($0.with.name) } ?? "Messages")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let conv {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        if conv.with.isSubreddit {
                            Image(systemName: "shield").foregroundStyle(.tint)
                        } else {
                            LetterAvatar(name: conv.with.name, size: 30, imageUrl: app.authorAvatars.icons[conv.with.name.lowercased()])
                        }
                        Text(conv.with.isSubreddit ? subredditName(conv.with.name) : userName(conv.with.name))
                            .font(.headline)
                            .lineLimit(1)
                    }
                }
            }
        }
        .task { app.inbox.ensureLoaded("messages") }
        .task(id: state.loading ? -1 : state.items.count) {
            guard conv == nil, !state.loading else { return }
            let me = app.session.username
            guard let found = conversations(state.items, me: me).first(where: { $0.with.key == key }) else { return }
            conv = found
            app.inbox.markReadMany(unreadIn(found.threads, me: me))
        }
    }
}

/// `threads` as one chat, oldest first. As a `conversation` (#315) each thread starts under
/// its date and subject, and a line marks where the new ones begin; a reply goes to the
/// newest thread.
private struct MessageThread: View {
    let root: InboxItem
    let conversation: Bool
    @Environment(AppNavigator.self) private var nav
    @State private var entries: [ChatEntry]
    @State private var reply: String
    @State private var selection: TextSelection?
    @State private var media: MediaAttachment?
    @State private var sending = false
    // A picked file still being read: sending now would go without it.
    @State private var attaching = false
    @State private var pickingImage = false
    @State private var pickingVideo = false
    @State private var pickedImage: PhotosPickerItem?
    @State private var pickedVideo: PhotosPickerItem?

    private var draftKey: String { "msgreply_\(root.fullname)" }

    private var messages: [InboxItem] {
        entries.compactMap { if case let .message(m) = $0 { m } else { nil } }
    }

    init(threads: [InboxItem], conversation: Bool) {
        let root = threads[threads.count - 1]
        self.root = root
        self.conversation = conversation
        _entries = State(initialValue: chatEntries(threads, me: app.session.username, dividers: conversation))
        _reply = State(initialValue: app.drafts.get("msgreply_\(root.fullname)") ?? "")
    }

    var body: some View {
        let me = app.session.username
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(entries) { e in
                        switch e {
                        case let .threadStart(t):
                            Text("\(chatDay(t.createdUtc)) · \(t.subject.nilIfEmpty ?? "(no subject)")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 6)
                                .id(e.id)
                        case let .newFrom(count):
                            HStack(spacing: 10) {
                                Rectangle().fill(.separator).frame(height: 1)
                                Text("\(count) new").font(.caption.weight(.semibold)).foregroundStyle(.tint).fixedSize()
                                Rectangle().fill(.separator).frame(height: 1)
                            }
                            .id(e.id)
                        case let .message(m):
                            MessageBubble(message: m, mine: isMine(m, me: me)).id(e.id)
                        }
                    }
                }
                .padding(12)
            }
            // Chat-style: start at (and follow) the newest message.
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: entries.count) {
                withAnimation { proxy.scrollTo(entries.last?.id, anchor: .bottom) }
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
            if attaching {
                AttachmentLoading()
            } else if let m = media {
                AttachmentPreview(media: m) { media = nil }
            }
            LengthCounter(text: reply, limit: TextLimit.comment)
            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    Button("Attach image", systemImage: "photo") { pickingImage = true }
                    Button("Attach video", systemImage: "video") { pickingVideo = true }
                    // The system Paste button: no "Allow Paste?" prompt, and only
                    // enabled when the clipboard holds an image.
                    PasteButton(payloadType: PastedImage.self) { pasted in
                        guard let first = pasted.first else { return }
                        Task { @MainActor in media = first.media }
                    }
                } label: {
                    Image(systemName: "plus").frame(width: 28, height: 28)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .disabled(sending || attaching)
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
                .disabled(sending || attaching || redditLength(reply.trimmed) > TextLimit.comment)
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
        attaching = true
        Task {
            do {
                media = try await readPicked(item, isVideo: isVideo)
            } catch {
                nav.showSnackbar(errorText(error))
            }
            attaching = false
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
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                app.drafts.clear(draftKey)
                entries.append(.message(InboxItem(
                    fullname: "local_\(entries.count)",
                    kind: .message,
                    author: me.nilIfEmpty ?? "you",
                    subject: root.subject,
                    body: text,
                    createdUtc: nowMillis()
                )))
                reply = ""
                media = nil
            } catch {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
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
                Text("\(userName(message.author)) · \(timeAgo(message.createdUtc))")
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

/// A short date for a thread's start in a conversation: "Today", else "Nov 12" (with the year when not this one).
private func chatDay(_ at: Int) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(at) / 1000)
    let cal = Calendar.current
    if cal.isDateInToday(date) { return "Today" }
    let sameYear = cal.component(.year, from: date) == cal.component(.year, from: .now)
    return date.formatted(sameYear ? .dateTime.month(.abbreviated).day() : .dateTime.month(.abbreviated).day().year())
}
