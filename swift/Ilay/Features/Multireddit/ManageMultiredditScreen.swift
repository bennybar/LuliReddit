import SwiftUI

/// Looks up a single multireddit by name from the user's list.
@MainActor @Observable final class MultiredditByNameViewModel {
    private(set) var multi: Async<Multireddit?> = .loading
    @ObservationIgnored private let name: String

    init(name: String) { self.name = name }

    func reload() {
        Task {
            do {
                multi = .data(try await app.repository.getMyMultireddits().first { $0.name == name })
            } catch {
                multi = .error(error)
            }
        }
    }
}

struct ManageMultiredditScreen: View {
    let username: String
    let name: String

    @State private var vm: MultiredditByNameViewModel

    init(username: String, name: String) {
        self.username = username
        self.name = name
        _vm = State(initialValue: MultiredditByNameViewModel(name: name))
    }

    var body: some View {
        let nav = app.navigator
        let repo = app.repository
        // `multi.value` is an optional of an optional: no list yet, or no such feed.
        let loaded = vm.multi.value ?? nil

        Group {
            switch vm.multi {
            case .loading:
                Loading().frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .error(error):
                ErrorView(message: "Could not load feed: \(friendlyError(error))")
            case .data(nil):
                ContentUnavailableView("Feed not found", systemImage: "rectangle.stack")
            case let .data(multi?):
                List {
                    Section {
                        Text(multi.visibility == "public" ? "Public: anyone with the link can see it" : "Private: only you can see it")
                            .foregroundStyle(.secondary)
                        if !multi.descriptionMd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(multi.descriptionMd).foregroundStyle(.secondary)
                        }
                        Button("Add subreddit", systemImage: "plus") {
                            Task {
                                guard let sr = await askText("Add subreddit", label: "Name", confirm: "Add", prefix: "r/", plain: true), !sr.isEmpty else { return }
                                do {
                                    try await repo.addSubredditToMulti(multi.path, subreddit: sr)
                                } catch {
                                    nav.showActionError("add r/\(sr)", error)
                                }
                                vm.reload()
                                app.feed.loadMultireddits(force: true)
                            }
                        }
                    }
                    Section {
                        if multi.subreddits.isEmpty {
                            Text("No subreddits yet").foregroundStyle(.secondary)
                        }
                        ForEach(multi.subreddits, id: \.self) { sr in
                            NavigationLink(value: Route.subreddit(name: sr)) { Text("r/\(sr)") }
                                .swipeActions(edge: .trailing) {
                                    Button("Remove", systemImage: "trash", role: .destructive) {
                                        Task {
                                            do {
                                                try await repo.removeSubredditFromMulti(multi.path, subreddit: sr)
                                            } catch {
                                                nav.showActionError("remove r/\(sr)", error)
                                            }
                                            vm.reload()
                                            app.feed.loadMultireddits(force: true)
                                        }
                                    }
                                }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable { vm.reload() }
            }
        }
        .navigationTitle(loaded?.displayName.nilIfEmpty ?? name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Share link", systemImage: "square.and.arrow.up") { nav.share("https://www.reddit.com/user/\(username)/m/\(name)/") }
                Menu("More", systemImage: "ellipsis") {
                    Button("Edit name, description, visibility", systemImage: "pencil") {
                        guard let multi = loaded else { return }
                        Task {
                            guard let e = await editFeedDialog(title: "Edit feed", confirm: "Save", name: multi.displayName, description: multi.descriptionMd, visibility: multi.visibility) else { return }
                            do {
                                try await repo.updateMultireddit(multi, displayName: e.displayName, description: e.description, visibility: e.visibility)
                                vm.reload()
                                app.feed.loadMultireddits(force: true)
                            } catch {
                                nav.showActionError("update the feed", error)
                            }
                        }
                    }
                    Button("Delete feed", systemImage: "trash", role: .destructive) {
                        guard let multi = loaded else { return }
                        Task {
                            guard await confirmDialog("Delete \"\(name)\"?", "This custom feed will be removed.", "Delete", destructive: true) else { return }
                            do {
                                try await repo.deleteMultireddit(multi.path)
                                app.feed.loadMultireddits(force: true)
                                nav.pop()
                            } catch {
                                nav.showActionError("delete the feed", error)
                            }
                        }
                    }
                }
            }
        }
        .task {
            if case .loading = vm.multi { vm.reload() }
        }
    }
}
