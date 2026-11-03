import SwiftUI

/// Previews a comment and its parent chain as an image card, then shares it as a PNG.
/// Usernames can be hidden before sharing.
@MainActor func showShareCommentImage(_ post: Post, _ chain: [Comment]) {
    Overlays.launch(detents: [.large]) { done in ShareImageSheet(post: post, chain: chain, done: done) }
}

private struct ShareImageSheet: View {
    let post: Post
    let chain: [Comment]
    let done: () -> Void

    @State private var hideNames = false
    @State private var busy = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ChainCard(post: post, chain: chain, hideNames: hideNames)
                        .clipShape(.rect(cornerRadius: 12))
                        .listRowInsets(EdgeInsets())
                }
                Section {
                    Toggle("Hide usernames", isOn: $hideNames)
                }
            }
            .navigationTitle("Share as image")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel, action: done)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Share", systemImage: "square.and.arrow.up", action: share)
                        .disabled(busy)
                        .buttonStyle(.glassProminent)
                }
            }
        }
    }

    private func share() {
        busy = true
        defer { busy = false }
        let renderer = ImageRenderer(content: ChainCard(post: post, chain: chain, hideNames: hideNames)
            .frame(width: 400)
            .environment(\.colorScheme, colorScheme))
        renderer.scale = displayScale
        guard let png = renderer.uiImage?.pngData() else {
            snack("Couldn't create the image")
            return
        }
        do {
            let dir = FileManager.default.temporaryDirectory.appending(path: "share")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appending(path: "ilay_comment_\(nowMillis()).png")
            try png.write(to: file)
            // Over this sheet, which stays open behind it.
            presentShareSheet(items: [file])
        } catch {
            snack("Couldn't create the image")
        }
    }
}

/// The card that becomes the image: post title, then the comment chain.
private struct ChainCard: View {
    let post: Post
    let chain: [Comment]
    let hideNames: Bool

    var body: some View {
        let names = CommentTree.shareNames(chain, hide: hideNames)
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "r/\(post.subreddit)").font(.caption.bold()).foregroundStyle(.secondary)
            Text(verbatim: post.title).font(.headline).padding(.top, 4).padding(.bottom, 12)
            ForEach(Array(chain.enumerated()), id: \.offset) { i, c in
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "\(names[i]) · \(compactNumber(c.score)) points")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    RedditMarkdown(text: c.body, media: c.media, fontSize: 14, color: .primary)
                }
                .padding(.leading, 10)
                .padding(.trailing, 6)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(alignment: .leading) {
                    (i == chain.count - 1 ? Color.accentColor : Color(.separator)).frame(width: 3)
                }
                .background(Color(.secondarySystemBackground))
                .clipShape(.rect(cornerRadius: 12))
                .padding(.leading, CGFloat(i) * 10)
                .padding(.bottom, 8)
            }
            Text("Shared from Ilay for Reddit")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(14)
        .background(Color(.systemBackground))
    }
}
