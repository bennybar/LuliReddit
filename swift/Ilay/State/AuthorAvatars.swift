import Foundation

/// Commenters' profile pictures (#133), by lowercased name. Reddit's comments .json has
/// none; its GraphQL comment forest has each author's, so with the website sign-in a
/// thread asks for its first page that way too (one more request) and keeps what comes
/// back here, for this thread and the next ones. In memory only.
@MainActor @Observable final class AuthorAvatars {
    private(set) var icons: [String: String] = [:]
    @ObservationIgnored private var order: [String] = []
    @ObservationIgnored private var asked: Set<String> = []
    private static let max = 3000

    /// Once per thread and sort; nothing without the website sign-in or with the setting off.
    func loadFor(postId: String, sort: String) async {
        let key = "\(postId)|\(sort)"
        guard app.settings.value.commentAvatars, asked.insert(key).inserted else { return }
        guard await app.client.isWebMode() else { return }
        guard let found = try? await app.repository.getCommentAvatars(postId: postId, sort: sort) else {
            asked.remove(key)
            return
        }
        if found.isEmpty { return }
        var all = icons
        for (name, url) in found {
            if all.updateValue(url, forKey: name) == nil { order.append(name) }
        }
        // Bounded: the oldest go first.
        if order.count > Self.max {
            for name in order.prefix(order.count - Self.max) { all.removeValue(forKey: name) }
            order.removeFirst(order.count - Self.max)
        }
        icons = all
    }
}
