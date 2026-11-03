import PhotosUI
import SwiftUI

/// A picked image / video, in memory and ready to upload (Reddit for inline comment
/// images, Catbox for videos / message attachments).
struct MediaAttachment: Equatable {
    let bytes: Data
    let filename: String
    let mimeType: String
    let isVideo: Bool

    var sizeLabel: String {
        let kb = Double(bytes.count) / 1024
        return kb < 1024 ? "\(Int(kb)) KB" : String(format: "%.1f MB", kb / 1024)
    }
}

/// Composer attachment UI: pending-attachment preview plus pick-image / pick-video /
/// paste buttons. [leading] = extra buttons (e.g. GIF). [catboxForImages]: messages
/// host even images on Catbox. [loading] is on while a picked file is being read
/// (an iCloud download, a video remux): the composer must not send without it.
struct AttachmentControls<Leading: View>: View {
    @Binding var media: MediaAttachment?
    @Binding var loading: Bool
    let onError: (String) -> Void
    var catboxForImages = false
    @ViewBuilder let leading: () -> Leading

    @State private var imageItem: PhotosPickerItem?
    @State private var videoItem: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if loading {
                AttachmentLoading()
            } else if let media {
                AttachmentPreview(media: media) { self.media = nil }
            }
            HStack(spacing: 4) {
                leading()
                PhotosPicker(selection: $imageItem, matching: .images) {
                    Image(systemName: "photo").frame(width: 44, height: 44).contentShape(.rect)
                }
                .accessibilityLabel("Attach image")
                PhotosPicker(selection: $videoItem, matching: .videos) {
                    Image(systemName: "video").frame(width: 44, height: 44).contentShape(.rect)
                }
                .accessibilityLabel("Attach video")
                // The system Paste button: no "Allow Paste?" prompt, and it's only
                // enabled when the clipboard holds an image. The file as it is, so a
                // pasted GIF keeps moving.
                PasteButton(payloadType: PastedImage.self) { pasted in
                    guard let first = pasted.first else { return }
                    Task { @MainActor in media = first.media }
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Paste image")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .disabled(loading)
            if let media {
                Text(media.isVideo || catboxForImages
                    ? "Will be uploaded to catbox.moe and linked (public)."
                    : "Image posts inline (hosted by Reddit; some subs disallow it — falls back to a catbox.moe link).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: imageItem) { _, item in load(item, isVideo: false) }
        .onChange(of: videoItem) { _, item in load(item, isVideo: true) }
    }

    private func load(_ item: PhotosPickerItem?, isVideo: Bool) {
        guard let item else { return }
        loading = true
        Task {
            do {
                // HEIC goes as JPEG and QuickTime as MP4, as a new post does: Reddit takes neither.
                media = try await readPicked(item, isVideo: isVideo)
            } catch {
                onError(error.localizedDescription)
            }
            loading = false
            imageItem = nil
            videoItem = nil
        }
    }
}

/// Holds a pending attachment's place while the picked file is read.
struct AttachmentLoading: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .frame(width: 48, height: 48)
                .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 8))
            Text("Preparing attachment…").font(.footnote).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(Color(.secondarySystemFill), in: .rect(cornerRadius: 12))
    }
}

/// Small inline preview of a pending attachment with a remove button.
struct AttachmentPreview: View {
    let media: MediaAttachment
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if !media.isVideo, let image = UIImage(data: media.bytes) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "film").foregroundStyle(.secondary)
                }
            }
            .frame(width: 48, height: 48)
            .background(Color(.tertiarySystemFill))
            .clipShape(.rect(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: media.filename).font(.footnote).lineLimit(1)
                Text(verbatim: media.sizeLabel).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("Remove attachment", systemImage: "xmark.circle.fill", action: onRemove)
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(Color(.secondarySystemFill), in: .rect(cornerRadius: 12))
    }
}

/// Giphy search sheet (uses the stored Giphy key, entered at login). Returns the chosen GIF URL or nil.
@MainActor func showGiphyPicker() async -> String? {
    guard let key = await app.secureStore.giphyKey(), !key.isEmpty else {
        app.navigator.showSnackbar("Add a Giphy API key (login screen) to use the GIF picker.")
        return nil
    }
    return await Overlays.show(detents: [.medium, .large]) { done in GiphySheet(apiKey: key, done: done) }
}

private struct Gif: Identifiable {
    let preview: String
    let full: String
    var id: String { full }
}

private func loadGifs(apiKey: String, query: String?) async throws -> [Gif] {
    var c = URLComponents(string: query?.isEmpty != false ? "https://api.giphy.com/v1/gifs/trending" : "https://api.giphy.com/v1/gifs/search")!
    c.queryItems = [URLQueryItem(name: "api_key", value: apiKey)]
        + (query?.isEmpty == false ? [URLQueryItem(name: "q", value: query)] : [])
        + [URLQueryItem(name: "limit", value: "24"), URLQueryItem(name: "rating", value: "pg-13")]
    let res = try await Http.session.send(URLRequest(url: c.url!))
    return (try AppJson.parse(res.body)["data"].arr() ?? []).compactMap { g in
        guard let preview = g["images"]["fixed_width"]["url"].str(), let full = g["images"]["original"]["url"].str() else { return nil }
        return Gif(preview: preview, full: full)
    }
}

private struct GiphySheet: View {
    let apiKey: String
    let done: (String?) -> Void
    @State private var query = ""
    @State private var results: [Gif] = []
    @State private var loading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                    ForEach(results) { gif in
                        Button {
                            done(gif.full)
                        } label: {
                            RemoteImage(url: URL(string: gif.preview), animated: true)
                                .aspectRatio(1, contentMode: .fit)
                                .clipShape(.rect(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
            }
            .overlay { if loading, results.isEmpty { ProgressView() } }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search GIFs")
            .navigationTitle("GIFs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) { done(nil) }
                }
            }
            // Trending first; each change supersedes the previous search, and a failure keeps its results.
            .task(id: query) {
                if !query.isEmpty { try? await Task.sleep(for: .milliseconds(300)) }
                if Task.isCancelled { return }
                loading = true
                if let gifs = try? await loadGifs(apiKey: apiKey, query: query.trimmed), !Task.isCancelled { results = gifs }
                loading = false
            }
        }
    }
}
