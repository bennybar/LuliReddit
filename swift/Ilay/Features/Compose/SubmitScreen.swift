import PhotosUI
import SwiftUI

// Raw values are stored in the draft: same order as Kotlin's enum.
private enum Kind: Int, CaseIterable, Hashable {
    case text, link, image, gallery, video

    var icon: String {
        switch self {
        case .text: "text.alignleft"
        case .link: "link"
        case .image: "photo"
        case .gallery: "photo.on.rectangle.angled"
        case .video: "video"
        }
    }

    var label: String {
        switch self {
        case .text: "Text"
        case .link: "Link"
        case .image: "Image"
        case .gallery: "Gallery"
        case .video: "Video"
        }
    }
}

private let draftKey = "compose_post"

/// New post: text / link / image / gallery / video, flair, NSFW/spoiler, drafts.
struct SubmitScreen: View {
    @Environment(AppNavigator.self) private var nav

    // The draft (text only; attachments aren't kept).
    @State private var sr: String
    @State private var title: String
    @State private var postBody: String
    @State private var url: String
    @State private var kind: Kind
    @State private var selection: TextSelection?
    // Picked files, read only when submitting.
    @State private var imageItem: PhotosPickerItem?
    @State private var galleryItems: [PhotosPickerItem] = []
    @State private var videoItem: PhotosPickerItem?
    @State private var preview: UIImage?
    @State private var nsfw = false
    @State private var spoiler = false
    @State private var sendReplies = true
    @State private var busy = false
    @State private var error: String?
    @State private var flairs: [Flair] = []
    @State private var flairId: String?
    @State private var flairsFor = ""
    @State private var hasDraft: Bool
    @FocusState private var subredditFocused: Bool

    init(subreddit: String?) {
        let m = app.drafts.get(draftKey).flatMap(parseJsonOrNull) // a malformed draft reads as none
        let sr = subreddit?.nilIfEmpty ?? m["sr"].str() ?? ""
        let title = m["title"].str() ?? ""
        let body = m["body"].str() ?? ""
        let url = m["url"].str() ?? ""
        _sr = State(initialValue: sr)
        _title = State(initialValue: title)
        _postBody = State(initialValue: body)
        _url = State(initialValue: url)
        _kind = State(initialValue: m["kind"].int().flatMap(Kind.init(rawValue:)) ?? .text)
        _hasDraft = State(initialValue: !sr.isBlank || !title.isBlank || !body.isBlank || !url.isBlank)
    }

    private var hasMedia: Bool { imageItem != nil || !galleryItems.isEmpty || videoItem != nil }
    private var flair: Flair? { flairs.first { $0.id == flairId } }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 2) {
                    Text("r/").foregroundStyle(.secondary)
                    TextField("Subreddit", text: $sr)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($subredditFocused)
                        .onSubmit(loadFlairs)
                    Button("Choose from your subreddits", systemImage: "chevron.up.chevron.down", action: chooseSubreddit)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                }
                TextField("Title", text: $title, axis: .vertical)
                    .lineLimit(1...2)
                if !flairs.isEmpty {
                    Picker("Flair", selection: $flairId) {
                        Text("None").tag(String?.none)
                        ForEach(flairs, id: \.id) { Text($0.text).tag(String?.some($0.id)) }
                    }
                }
            }
            Section {
                ConnectedChoice(options: Kind.allCases.map { (key: $0, label: $0.label) }, selected: kind, onSelect: { kind = $0 }, icon: { $0.icon })
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            content
            Section {
                Toggle("NSFW", isOn: $nsfw)
                Toggle("Spoiler", isOn: $spoiler)
                Toggle("Send me reply notifications", isOn: $sendReplies)
            }
            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle("New post")
        .navigationSubtitle(hasDraft && !busy ? "Draft saved" : "")
        .navigationBarTitleDisplayMode(.inline)
        // An attachment isn't part of the draft: Back asks first.
        .navigationBarBackButtonHidden(hasMedia)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if hasMedia {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Back", systemImage: "chevron.backward", action: leave)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(action: submit) {
                    if busy { ProgressView() } else { Text("Post") }
                }
                .buttonStyle(.glassProminent)
                .disabled(busy)
            }
        }
        .onChange(of: sr) { saveDraft() }
        .onChange(of: title) { saveDraft() }
        .onChange(of: postBody) { saveDraft() }
        .onChange(of: url) { saveDraft() }
        .onChange(of: kind) { saveDraft() }
        .onChange(of: subredditFocused) { if !subredditFocused { loadFlairs() } }
        .onChange(of: imageItem) { _, item in loadPreview(item) }
        .onChange(of: galleryItems) { _, items in loadPreview(items.first) }
        .onChange(of: videoItem) { preview = nil }
        .task { if !sr.isBlank { loadFlairs() } }
    }

    @ViewBuilder private var content: some View {
        switch kind {
        case .text:
            Section {
                MediaTextEditor(
                    text: $postBody, selection: $selection, placeholder: "Body (Markdown, optional)",
                    minLines: 5, maxLines: 12
                )
                MarkdownToolbar(text: $postBody, selection: $selection)
                Button("GIF", systemImage: "photo.stack") {
                    Task {
                        guard let gif = await showGiphyPicker() else { return }
                        postBody = postBody.isEmpty ? gif : "\(postBody)\n\(gif)"
                    }
                }
            }
        case .link:
            Section {
                TextField("URL", text: $url)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        case .image:
            Section {
                PhotosPicker(selection: $imageItem, matching: .images) {
                    PickerBox(label: imageItem == nil ? "Tap to choose an image" : "Image selected", icon: "photo.badge.plus", preview: preview)
                }
                .buttonStyle(.plain)
            }
            .listRowInsets(EdgeInsets())
        case .gallery:
            Section {
                PhotosPicker(selection: $galleryItems, maxSelectionCount: 20, matching: .images) {
                    PickerBox(label: galleryItems.isEmpty ? "Tap to choose images" : "\(galleryItems.count) image(s) selected", icon: "photo.on.rectangle.angled", preview: preview)
                }
                .buttonStyle(.plain)
            }
            .listRowInsets(EdgeInsets())
        case .video:
            Section {
                PhotosPicker(selection: $videoItem, matching: .videos) {
                    PickerBox(label: videoItem == nil ? "Tap to choose a video" : "Video selected", icon: "video.badge.plus", preview: nil)
                }
                .buttonStyle(.plain)
            }
            .listRowInsets(EdgeInsets())
        }
    }

    private func loadPreview(_ item: PhotosPickerItem?) {
        preview = nil
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                preview = await image.byPreparingThumbnail(ofSize: CGSize(width: 800, height: 800))
            }
        }
    }

    private func loadFlairs() {
        let name = sr.trimmed.removePrefix("r/")
        if name.isEmpty || name == flairsFor { return }
        flairsFor = name
        Task {
            flairs = await app.repository.getLinkFlairs(name)
            flairId = nil
        }
    }

    private func saveDraft() {
        let draft: JsonElement = ["sr": .string(sr), "title": .string(title), "body": .string(postBody), "url": .string(url), "kind": .int(kind.rawValue)]
        var info = JsonObject()
        info["kind"] = .string("post")
        app.drafts.save(draftKey, draft.encoded(), info: info)
        hasDraft = !sr.isBlank || !title.isBlank || !postBody.isBlank || !url.isBlank
    }

    private func chooseSubreddit() {
        Task {
            let picked: String? = await Overlays.show(detents: [.medium, .large]) { done in SubredditPicker(done: done) }
            if let picked {
                sr = picked
                loadFlairs()
            }
        }
    }

    private func finish(_ message: String) {
        app.drafts.clear(draftKey)
        nav.showSnackbar(message)
        nav.pop()
    }

    private func goToPost(_ name: String, _ id: String) {
        app.drafts.clear(draftKey)
        if id.isEmpty {
            finish("Posted")
        } else {
            nav.pop()
            nav.push(.post(subreddit: name, postId: id))
        }
    }

    private func submit() {
        let name = sr.trimmed.removePrefix("r/")
        let t = title.trimmed
        if name.isEmpty || t.isEmpty {
            error = "Subreddit and title are required."
        } else if kind == .link, url.isBlank {
            error = "Enter a URL for a link post."
        } else if kind == .image, imageItem == nil {
            error = "Pick an image to upload."
        } else if kind == .gallery, galleryItems.isEmpty {
            error = "Pick at least one image."
        } else if kind == .video, videoItem == nil {
            error = "Pick a video to upload."
        } else {
            error = nil
        }
        if error != nil { return }
        busy = true
        let repo = app.repository
        let (nsfw, spoiler, sendReplies, flair) = (nsfw, spoiler, sendReplies, flair)
        Task {
            do {
                switch kind {
                case .text:
                    goToPost(name, try await repo.submitPost(name, title: t, kind: "self", text: postBody.trimmed, nsfw: nsfw, spoiler: spoiler, sendReplies: sendReplies, flair: flair))
                case .link:
                    goToPost(name, try await repo.submitPost(name, title: t, kind: "link", url: url.trimmed, nsfw: nsfw, spoiler: spoiler, sendReplies: sendReplies, flair: flair))
                case .image:
                    let img = try await readPicked(imageItem!, isVideo: false)
                    let uploaded = try await repo.uploadImage(img.bytes, filename: img.filename, mimeType: img.mimeType)
                    goToPost(name, try await repo.submitPost(name, title: t, kind: "image", url: uploaded, nsfw: nsfw, spoiler: spoiler, sendReplies: sendReplies, flair: flair))
                case .gallery:
                    var ids: [String] = []
                    for (i, item) in galleryItems.enumerated() {
                        let img = try await readPicked(item, isVideo: false)
                        ids.append(try await repo.uploadMediaAsset(img.bytes, filename: "image\(i).\(img.filename.substringAfter(".", missing: "jpg"))", mimeType: img.mimeType).assetId)
                    }
                    try await repo.submitGalleryPost(name, title: t, mediaIds: ids, nsfw: nsfw, spoiler: spoiler, sendReplies: sendReplies, flair: flair)
                    finish("Gallery posted")
                case .video:
                    let v = try await readPicked(videoItem!, isVideo: true)
                    let posterBytes = await posterFrame(v.bytes)
                    let uploaded = try await repo.uploadMediaAsset(v.bytes, filename: v.filename, mimeType: "video/mp4")
                    let poster = try await repo.uploadMediaAsset(posterBytes ?? v.bytes, filename: "poster.jpg", mimeType: "image/jpeg")
                    let id = try await repo.submitVideoPost(name, title: t, videoUrl: uploaded.url, posterUrl: poster.url, nsfw: nsfw, spoiler: spoiler, sendReplies: sendReplies, flair: flair)
                    if id.isEmpty { finish("Video posted") } else { goToPost(name, id) }
                }
            } catch {
                busy = false
                self.error = errorText(error)
            }
        }
    }

    private func leave() {
        Task {
            let ok = await Overlays.alert(
                "Discard attachment?",
                message: "Your text is saved as a draft, but the attached image/video is not. Leave anyway?",
                buttons: [(title: "Stay", role: .cancel, value: false), (title: "Leave", role: .destructive, value: true)]
            )
            if ok == true { nav.pop() }
        }
    }
}

private struct PickerBox: View {
    let label: String
    let icon: String
    let preview: UIImage?

    var body: some View {
        ZStack {
            Color(.secondarySystemFill)
            if let preview {
                Image(uiImage: preview).resizable().scaledToFill().opacity(0.35)
            }
            VStack(spacing: 8) {
                Image(systemName: icon).font(.largeTitle).foregroundStyle(.secondary)
                Text(label).multilineTextAlignment(.center).padding(.horizontal, 16)
            }
        }
        .frame(height: 150)
        .frame(maxWidth: .infinity)
        .clipped()
        .contentShape(.rect)
    }
}

/// A sheet of the user's subscriptions; `done` gets the chosen name.
private struct SubredditPicker: View {
    let done: (String?) -> Void
    @State private var subs: [Subreddit]?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Group {
                if failed {
                    ContentUnavailableView("Couldn't load your subreddits.", systemImage: "icloud.slash")
                } else if let subs {
                    if subs.isEmpty {
                        ContentUnavailableView("You aren't subscribed to any subreddits.", systemImage: "list.bullet")
                    } else {
                        List(subs, id: \.name) { s in
                            Button { done(s.name) } label: {
                                HStack(spacing: 12) {
                                    LetterAvatar(name: s.name, size: 32, imageUrl: s.iconUrl)
                                    Text(s.namePrefixed).foregroundStyle(.primary)
                                }
                            }
                        }
                        .listStyle(.plain)
                    }
                } else {
                    Loading().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Your subreddits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) { done(nil) }
                }
            }
        }
        .task {
            do {
                subs = try await app.repository.getSubscribedSubreddits()
            } catch {
                failed = true
            }
        }
    }
}
