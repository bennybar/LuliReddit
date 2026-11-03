import SwiftUI

/// "Read later": threads saved for offline reading. Opening one loads it live
/// when online and from the saved copy when not. Swipe to remove.
struct OfflineScreen: View {
    var body: some View {
        let threads = app.offline.state
        Group {
            if threads.isEmpty {
                ContentUnavailableView {
                    Label("Nothing saved yet", systemImage: "arrow.down.circle")
                } description: {
                    Text("Use \"Save for offline\" in a post's ⋯ menu to keep it, with its comments, for reading without a connection.")
                }
            } else {
                List(threads, id: \.id) { t in
                    NavigationLink(value: Route.post(subreddit: t.subreddit.nilIfEmpty ?? "_", postId: t.id)) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.title).lineLimit(2)
                                Text("r/\(t.subreddit) · saved \(timeAgo(t.savedAt))").font(.footnote).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "arrow.down.circle.fill")
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Remove", systemImage: "trash", role: .destructive) {
                            Task { await app.offline.remove(t.id) }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Read later")
    }
}
