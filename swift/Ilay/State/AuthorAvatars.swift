import Foundation

/// Commenters' profile pictures (#133), by lowercased name. Reddit's comments .json has
/// none. With the website sign-in they come from its GraphQL comment forest, about 25
/// comments a request: the first page as a thread opens (one more request), and up to
/// `morePages` more once a long thread's full page is in (#217). With an API key they
/// come by account id, 100 a request, for at most 200 new commenters at a time (#185):
/// the first page, the full page and loaded "more replies" (#217). (The website sign-in
/// gets a 404 there.) Kept here for this thread and the next ones. In memory only.
@MainActor @Observable final class AuthorAvatars {
    private(set) var icons: [String: String] = [:]
    @ObservationIgnored private var order: [String] = []
    @ObservationIgnored private var asked: Set<String> = []
    /// Account ids already asked for with an API key (found or not).
    @ObservationIgnored private var askedIds: Set<String> = []
    /// Website sign-in: where each thread's (postId|sort) GraphQL pages continue.
    @ObservationIgnored private var next: [String: String] = [:]
    private static let max = 3000
    private static let morePages = 3

    /// Once per thread and sort ([comments]: its first page); nothing with the setting off.
    func loadFor(postId: String, sort: String, comments: [Comment]) async {
        let key = "\(postId)|\(sort)"
        guard app.settings.value.commentAvatars, asked.insert(key).inserted else { return }
        guard await app.client.isWebMode() else { return await loadAuthors(comments) }
        guard let page = try? await app.repository.getCommentAvatars(postId: postId, sort: sort) else {
            asked.remove(key)
            return
        }
        if let after = page.next { next[key] = after }
        add(page.icons)
    }

    /// A long thread's full page is in ([comments]): the commenters past the first page.
    func loadRest(postId: String, sort: String, comments: [Comment]) async {
        guard app.settings.value.commentAvatars else { return }
        guard await app.client.isWebMode() else { return await loadAuthors(comments) }
        let key = "\(postId)|\(sort)"
        for _ in 0..<Self.morePages {
            guard let after = next.removeValue(forKey: key),
                  let page = try? await app.repository.getCommentAvatars(postId: postId, sort: sort, after: after) else { return }
            if let more = page.next { next[key] = more }
            add(page.icons)
        }
    }

    /// API key: [comments]' authors not known yet, by account id (each asked for once).
    func loadAuthors(_ comments: [Comment]) async {
        guard app.settings.value.commentAvatars, await !app.client.isWebMode() else { return }
        var ids: [String] = []
        for c in CommentTree.flatten(comments, []) where c.authorFullname.hasPrefix("t2_") && icons[c.author.lowercased()] == nil {
            if ids.count < 200, askedIds.insert(c.authorFullname).inserted { ids.append(c.authorFullname) }
        }
        var found: [String: String] = [:]
        var start = 0
        while start < ids.count {
            let batch = Array(ids[start..<min(start + 100, ids.count)])
            guard let icons = try? await app.repository.getUserIcons(batch) else {
                askedIds.subtract(ids)
                return
            }
            found.merge(icons) { _, new in new }
            start += 100
        }
        add(found)
    }

    private func add(_ found: [String: String]) {
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
