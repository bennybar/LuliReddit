import SwiftUI

/// Add r/`subreddit` to one of your custom feeds (or take it out): your feeds, ticked
/// where it's already in (so it can't be added twice), and New feed, which starts one
/// with it. From a post's ⋯ menu and a community's top bar.
@MainActor func showAddToCustomFeed(_ subreddit: String) async {
    let _: Bool? = await Overlays.show(detents: [.medium, .large]) { done in
        AddToCustomFeedSheet(subreddit: subreddit) { done(nil) }
    }
}

private struct AddToCustomFeedSheet: View {
    let subreddit: String
    let onDone: () -> Void

    /// The feed being changed right now (its row shows a spinner).
    @State private var busy: String?

    private func contains(_ m: Multireddit) -> Bool {
        m.subreddits.contains { $0.lowercased() == subreddit.lowercased() }
    }

    private func toggle(_ m: Multireddit) {
        if busy != nil { return }
        busy = m.path
        let add = !contains(m)
        let path = m.path.hasSuffix("/") ? String(m.path.dropLast()) : m.path
        Task {
            do {
                if add {
                    try await app.repository.addSubredditToMulti(path, subreddit: subreddit)
                } else {
                    try await app.repository.removeSubredditFromMulti(path, subreddit: subreddit)
                }
                app.feed.loadMultireddits(force: true)
                app.navigator.showSnackbar(add ? "Added r/\(subreddit) to \(m.displayName)" : "Removed r/\(subreddit) from \(m.displayName)")
            } catch {
                app.navigator.showSnackbar("Couldn't change \(m.displayName): \(friendlyError(error))")
            }
            busy = nil
        }
    }

    var body: some View {
        NavigationStack {
            List {
                switch app.feed.multireddits {
                case .loading:
                    Loading().frame(maxWidth: .infinity)
                case let .error(error):
                    Text("Couldn't load your custom feeds: \(friendlyError(error))")
                case let .data(multis):
                    ForEach(multis, id: \.path) { multi in
                        let inIt = contains(multi)
                        Button { toggle(multi) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "rectangle.stack").foregroundStyle(.tint)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(multi.displayName).foregroundStyle(.primary)
                                    Text(inIt ? "Has r/\(subreddit) · tap to remove" : "\(multi.subreddits.count) communities")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                if busy == multi.path {
                                    Loading()
                                } else if inIt {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint).accessibilityLabel("In this feed")
                                }
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Section {
                    Button {
                        Task {
                            if await createMulti(username: app.session.username, subreddits: [subreddit]) {
                                app.navigator.showSnackbar("Created a feed with r/\(subreddit)")
                                onDone()
                            }
                        }
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("New feed").foregroundStyle(.primary)
                                Text("Starts with r/\(subreddit)").font(.footnote).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "plus")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Add r/\(subreddit) to a custom feed")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { app.feed.loadMultireddits() }
    }
}
