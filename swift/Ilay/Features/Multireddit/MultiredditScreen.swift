import SwiftUI

/// A custom feed (multireddit): its posts, with a shortcut to manage it.
struct MultiredditScreen: View {
    let username: String
    let name: String

    var body: some View {
        let nav = app.navigator
        let me = app.session.username
        PostListView(feedKey: "m::\(username)::\(name)")
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if username.lowercased() == me.lowercased() {
                        Button("Manage", systemImage: "slider.horizontal.3") { nav.push(.manageMultireddit(username: username, name: name)) }
                    } else if !me.isEmpty {
                        // Someone's public feed: make your own copy of it (Reddit's "Copy custom feed").
                        Button("Copy to your feeds", systemImage: "doc.on.doc") {
                            Task {
                                guard let e = await editFeedDialog(title: "Copy to your feeds", confirm: "Copy", name: name.replacingOccurrences(of: "_", with: " "), description: "", visibility: "private") else { return }
                                do {
                                    try await app.repository.copyMultireddit(fromPath: "/user/\(username)/m/\(name)", username: me, displayName: e.displayName)
                                    app.feed.loadMultireddits(force: true)
                                    nav.showSnackbar("Copied to your custom feeds")
                                } catch {
                                    nav.showActionError("copy the feed", error)
                                }
                            }
                        }
                    }
                    Button("Share link", systemImage: "square.and.arrow.up") { nav.share("https://www.reddit.com/user/\(username)/m/\(name)/") }
                }
            }
    }
}
