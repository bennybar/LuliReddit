import SwiftUI

/// The communities you've joined. One shared list: the Explore tab's, read by the
/// side bar too, so it costs no requests of its own.
@MainActor @Observable final class SubscriptionsViewModel {
    static let shared = SubscriptionsViewModel()

    private(set) var subs: Async<[Subreddit]> = .loading
    private var job: Task<Void, Never>?
    /// The account generation the list was loaded for (reload after a switch).
    private var loadedFor: Int?

    private init() {}

    /// The first load, or a fresh one after an account switch (each screen that shows the list asks).
    func loadIfNeeded() {
        if loadedFor != app.feed.version { load(force: loadedFor != nil) }
    }

    @discardableResult func load(force: Bool = false) -> Task<Void, Never> {
        loadedFor = app.feed.version
        job?.cancel()
        let job = Task {
            if case .data = subs {} else { subs = .loading }
            do {
                let list = try await app.repository.getSubscribedSubreddits(force: force)
                if !Task.isCancelled { subs = .data(list) }
            } catch {
                if !Task.isCancelled { subs = .error(error) }
            }
        }
        self.job = job
        return job
    }
}
