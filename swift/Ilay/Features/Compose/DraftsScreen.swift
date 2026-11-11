import SwiftUI

/// A draft as a row: what it is, where it goes, its text, and the screen that resumes it.
private struct DraftRow {
    let icon: String
    let place: String
    let preview: String
    let open: Route?

    init(_ d: Draft) {
        let info = d.info
        let json = parseJsonOrNull(d.text)
        func nonBlank(_ s: String?) -> String? { s.flatMap { $0.isBlank ? nil : $0 } }
        if d.key.hasPrefix("reply_") {
            icon = "arrowshape.turn.up.left"
            place = [
                info["to"].str().map { "Reply to u/\($0)" } ?? "Reply",
                info["title"].str().map { "in \"\($0)\"" },
                info["sub"].str().map { "r/\($0)" },
            ].compactMap { $0 }.joined(separator: " · ")
            preview = d.text
            open = info["post"].str().map { .post(subreddit: info["sub"].str() ?? "_", postId: $0, focusCommentId: info["comment"].str()) }
        } else if d.key.hasPrefix("msgreply_") {
            icon = "envelope"
            place = [info["to"].str().map { "Reply to u/\($0)" } ?? "Message reply", nonBlank(info["subject"].str())]
                .compactMap { $0 }.joined(separator: " · ")
            preview = d.text
            open = .messageThread(fullname: d.key.removePrefix("msgreply_"))
        } else if d.key == "compose_msg" {
            icon = "envelope"
            place = nonBlank(json["to"].str()).map { "Message to u/\($0)" } ?? "New message"
            preview = [nonBlank(json["subject"].str()), nonBlank(json["body"].str())].compactMap { $0 }.joined(separator: " — ")
            open = .composeMessage(to: nonBlank(json["to"].str()))
        } else if d.key == "compose_post" {
            icon = "square.and.pencil"
            place = nonBlank(json["sr"].str()).map { "New post in r/\($0)" } ?? "New post"
            preview = [nonBlank(json["title"].str()), nonBlank(json["body"].str()) ?? nonBlank(json["url"].str())].compactMap { $0 }.joined(separator: " — ")
            open = .submit(subreddit: nonBlank(json["sr"].str()))
        } else {
            icon = "square.and.pencil"
            place = "Draft"
            preview = d.text
            open = nil
        }
    }
}

/// You → Drafts: this account's unfinished replies, messages and posts. Tap to go where
/// it belongs (its composer then restores it); swipe to delete.
struct DraftsScreen: View {
    @Environment(AppNavigator.self) private var nav

    var body: some View {
        // `changes` is read so a save or a delete refreshes the list.
        let drafts = app.drafts.changes >= 0 ? app.drafts.list() : []
        Group {
            if drafts.isEmpty {
                ContentUnavailableView("No drafts", systemImage: "square.and.pencil", description: Text("Unfinished replies, messages and posts are kept here until you send them."))
            } else {
                List(drafts, id: \.key) { d in
                    let row = DraftRow(d)
                    Button {
                        if let route = row.open { nav.push(route) }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: row.icon).foregroundStyle(.secondary).frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.preview.isBlank ? "(empty)" : row.preview).lineLimit(2)
                                Text(([row.place] + (d.savedAt > 0 ? [timeAgoPhrase(d.savedAt)] : [])).joined(separator: " · "))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            app.drafts.clear(d.key)
                            nav.showSnackbar("Draft deleted")
                        }
                    }
                }
                // Grouped like History (#160), under a large title that folds away as you scroll.
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Drafts")
    }
}
