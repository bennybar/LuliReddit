import Foundation

/// Commenters' profile pictures (#133), by lowercased name. Reddit's comments .json has
/// none; its GraphQL comment forest has each author's, so with the website sign-in a
/// thread asks for its first page that way too (one more request). With an API key they
/// come by account id, 100 a request, for at most the first 200 new commenters (#185).
/// Kept here for this thread and the next ones. In memory only.
@MainActor @Observable final class AuthorAvatars {
    private(set) var icons: [String: String] = [:]
    @ObservationIgnored private var order: [String] = []
    @ObservationIgnored private var asked: Set<String> = []
    /// Account ids already asked for with an API key (found or not).
    @ObservationIgnored private var askedIds: Set<String> = []
    private static let max = 3000

    /// Once per thread and sort ([comments]: its first page); nothing with the setting off.
    func loadFor(postId: String, sort: String, comments: [Comment]) async {
        let key = "\(postId)|\(sort)"
        guard app.settings.value.commentAvatars, asked.insert(key).inserted else { return }
        var found: [String: String] = [:]
        do {
            if await app.client.isWebMode() {
                found = try await app.repository.getCommentAvatars(postId: postId, sort: sort)
            } else {
                var ids: [String] = []
                for c in CommentTree.flatten(comments, []) where c.authorFullname.hasPrefix("t2_") && icons[c.author.lowercased()] == nil {
                    if ids.count < 200, askedIds.insert(c.authorFullname).inserted { ids.append(c.authorFullname) }
                }
                var start = 0
                while start < ids.count {
                    let batch = Array(ids[start..<min(start + 100, ids.count)])
                    found.merge(try await app.repository.getUserIcons(batch)) { _, new in new }
                    start += 100
                }
            }
        } catch {
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
