import Foundation
import os

/// A thread: the post, its comment tree and the mods' suggested sort (e.g. "qa").
/// Kotlin's `Thread`; renamed because Foundation has one.
struct RedditThread: Sendable {
    let post: Post
    let comments: [Comment]
    let suggestedSort: String?
}

/// Crossposts whose listing left out the original (`Post.missingCrosspostParent`),
/// rebuilt around it once it's fetched (`RedditRepository.fillCrossposts`), by post id.
/// Cards and the thread header read this, so the post fills in where it's shown and
/// the list itself never moves.
@MainActor @Observable final class Crossposts {
    private(set) var posts: [String: Post] = [:]

    nonisolated init() {}

    func add(_ new: [String: Post]) { posts.merge(new) { $1 } }

    /// `post`, or once its original has loaded, the crosspost rebuilt around it. Only a
    /// view showing such a crosspost reads (and so watches) the map.
    func merged(_ post: Post) -> Post { post.missingCrosspostParent ? Crossposts.merged(post, in: posts) : post }

    nonisolated static func merged(_ post: Post, in posts: [String: Post]) -> Post {
        guard post.missingCrosspostParent, let m = posts[post.id] else { return post }
        // For You's "why you're seeing this" is set on the listed post, not the fetched one.
        return m.with { $0.feedReason = post.feedReason }
    }
}

/// The most comments one "more replies" request asks for.
private let moreLimit = 500

/// How many hidden comments one tap fetches one by one, when a page doesn't reach them.
private let moreBatch = 10

/// An uploaded media asset: its public S3 url and Reddit asset id (= media_id).
struct MediaAsset: Sendable {
    let url: String
    let assetId: String
}

/// A saved item: Reddit's saved list mixes posts and comments.
enum SavedItem: Sendable {
    case post(Post)
    case comment(Comment)
}

private let leadingR = Re(#"^/?r/"#, ignoreCase: true)
private let flairCode = Re(#":[\w-]+:"#)
private let locationRe = Re(#"<Location>(.*?)</Location>"#)
private let notFeedName = Re(#"[^a-z0-9_]+"#)

/// Every Reddit endpoint the app uses. Parsing mirrors the Flutter build
/// one-to-one; JSON work happens off the main thread (these are nonisolated
/// async methods: they don't run on the main actor).
final class RedditRepository: Sendable {
    let client: RedditClient

    private struct State {
        // Short-lived cache of the subscription list — it's expensive (up to 5
        // sequential paged requests) and hit on every For You build. Config is
        // pushed in from settings.
        var subsCache: [Subreddit]?
        var subsCacheAt = 0
        var subsCacheEnabled = true
        var subsCacheTtlMillis = 10 * 60_000
        // The raw JSON of recently parsed posts (bounded), so a ranked For You
        // page or an offline thread can be saved and painted instantly next time.
        var rawPosts = OrderedMap<JsonElement>()
        // The originals of crossposts that came without them, raw, by fullname, so a
        // reloaded page rebuilds its crossposts at once; and those asked for (in
        // flight, or Reddit didn't return them).
        var crosspostParents: [String: JsonElement] = [:]
        var crosspostsAsked: Set<String> = []
        // Share links (`Post.shareLink`) by URL, resolved to the fullname of the post
        // they redirect to, so a reloaded page needn't resolve them again. "": not a
        // post, or it couldn't be resolved (not tried again); missing but asked: in flight.
        var shareLinkTargets: [String: String] = [:]
        var shareLinksAsked: Set<String> = []
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    let crossposts = Crossposts()

    init(client: RedditClient) { self.client = client }

    func setSubsCache(enabled: Bool, ttlMillis: Int) {
        state.withLock {
            $0.subsCacheEnabled = enabled
            $0.subsCacheTtlMillis = ttlMillis
        }
    }

    func rawPost(_ id: String) -> JsonElement? { state.withLock { $0.rawPosts[id] } }

    private func keepRaw(_ id: String, _ raw: JsonElement) {
        state.withLock {
            $0.rawPosts.removeValue(forKey: id)
            $0.rawPosts[id] = raw
            if $0.rawPosts.count > 800 { $0.rawPosts.removeFirst() }
        }
    }

    /// Rebuilds `children` (crossposts missing their original, with their raw JSON) as
    /// if `crosspost_parent_list` had been there: at once from the originals already
    /// known, the rest after one request for all of them. A share-link post becomes a
    /// crosspost of the post its link resolves to. Failures are silent: the card keeps
    /// its in-app link to the original.
    private func fillCrossposts(_ children: [(Post, JsonElement)]) {
        if children.isEmpty { return }
        func parentOf(_ post: Post, _ s: State) -> String? {
            post.crosspostParent ?? s.shareLinkTargets[post.url]?.nilIfEmpty
        }
        func rebuild() {
            let merged: [(String, JsonElement)] = state.withLock { s in
                children.compactMap { post, raw in
                    guard let fullname = parentOf(post, s), let parent = s.crosspostParents[fullname] else { return nil }
                    return (post.id, Post.withCrosspostParent(raw, parent, fullname: fullname))
                }
            }
            if merged.isEmpty { return }
            // Kept for a For You page or an offline thread saved from here.
            state.withLock { s in for (id, raw) in merged where s.rawPosts[id] != nil { s.rawPosts[id] = raw } }
            let posts = Dictionary(merged.map { ($0.0, Post.fromData($0.1)) }) { $1 }
            Task { @MainActor in self.crossposts.add(posts) }
        }
        func wanted() -> [String] {
            state.withLock { s in
                var w: [String] = []
                for case let id? in children.map({ parentOf($0.0, s) }) where w.count < 100 && !s.crosspostsAsked.contains(id) {
                    s.crosspostsAsked.insert(id)
                    w.append(id)
                }
                return w
            }
        }
        rebuild()
        let unresolved: [String] = state.withLock { s in
            var u: [String] = []
            for (post, _) in children where post.shareLink && !s.shareLinksAsked.contains(post.url) {
                s.shareLinksAsked.insert(post.url)
                u.append(post.url)
            }
            return u
        }
        let known = wanted()
        if unresolved.isEmpty && known.isEmpty { return }
        Task {
            if !unresolved.isEmpty {
                // Each is a redirect on www.reddit.com (no sign-in); a few at a time.
                let targets = await withTaskGroup(of: (String, String).self) { group in
                    var out: [(String, String)] = []
                    for (i, link) in unresolved.enumerated() {
                        if i >= 4, let r = await group.next() { out.append(r) }
                        group.addTask {
                            guard let uri = URL(string: link), let resolved = await resolveShareLink(uri),
                                  case let .post(_, id, _)? = redditPostRoute(resolved.absoluteString) else { return (link, "") }
                            return (link, "t3_\(id)")
                        }
                    }
                    for await r in group { out.append(r) }
                    return out
                }
                state.withLock { s in for (link, fullname) in targets { s.shareLinkTargets[link] = fullname } }
            }
            // The originals the share links resolved to join the same request.
            let ids = known + wanted()
            if ids.isEmpty { return }
            do {
                // Reddit's /by_id (or PostsByIds) takes them all in one go.
                let parents = try await getPostsByIds(ids)
                state.withLock { s in
                    for p in parents { if let raw = s.rawPosts[p.id] { s.crosspostParents[p.fullname] = raw } }
                }
                rebuild()
            } catch {
                // Asked again with the next page that has them.
                state.withLock { $0.crosspostsAsked.subtract(ids) }
            }
        }
    }

    func parsePostListing(_ json: JsonElement, fromCache: Bool = false) -> Listing<Post> {
        let data = json["data"]
        var posts: [Post] = []
        var crossposts: [(Post, JsonElement)] = []
        for c in data["children"].arr() ?? [] {
            guard c["kind"].str() == "t3", let raw = c["data"] else { continue }
            let post = Post.fromData(raw)
            posts.append(post)
            if post.missingCrosspostParent { crossposts.append((post, raw)) }
            keepRaw(post.id, raw)
        }
        fillCrossposts(crossposts)
        return Listing(items: posts, after: data["after"].str(), fromCache: fromCache)
    }

    /// Posts by fullname (t3_…), in the order given (Reddit reorders and drops removed ones).
    func getPostsByIds(_ fullnames: [String]) async throws -> [Post] {
        if fullnames.isEmpty { return [] }
        var byId: [String: Post] = [:]
        if await client.isWebMode() {
            // /by_id.json is refused for the website sign-in (Reddit Home, Blend).
            let data = try await client.gql("PostsByIds", GQL_POSTS_BY_IDS, postsByIdsVariables(fullnames))
            for n in data["postsInfoByIds"].arr() ?? [] where gqlIsPost(n) {
                guard let o = n.obj() else { continue }
                let raw = JsonElement.object(gqlPostData(o))
                let post = Post.fromData(raw)
                // Kept like a listing's, e.g. for a Home page saved for offline.
                keepRaw(post.id, raw)
                byId["t3_\(post.id)"] = post
            }
        } else {
            let json = try await client.get("/by_id/\(fullnames.joined(separator: ","))", [("limit", "\(fullnames.count)"), ("sr_detail", "true")])
            for p in parsePostListing(json).items { byId["t3_\(p.id)"] = p }
        }
        return fullnames.compactMap { byId[$0] }
    }

    private func postsQuery(_ sort: PostSort, _ time: TopTime, _ after: String?, _ limit: Int) -> Fields {
        // sr_detail: each post carries its subreddit's icon for the card.
        var q: Fields = [("limit", "\(limit)"), ("sr_detail", "true")]
        if let after { q.append(("after", after)) }
        if sort.needsTime { q.append(("t", time.param)) }
        return q
    }

    /// Frontpage (subreddit == nil) or a specific subreddit's posts.
    func getPosts(
        subreddit: String? = nil,
        sort: PostSort = .best,
        time: TopTime = .day,
        after: String? = nil,
        limit: Int = 25
    ) async throws -> Listing<Post> {
        let base = subreddit.map { "/r/\($0)" } ?? ""
        return try await orGql {
            let res = try await self.client.getResult("\(base)/\(sort.path)", self.postsQuery(sort, time, after, limit))
            return self.parsePostListing(res.json, fromCache: res.fromCache)
        } gql: {
            // Reddit's app loads a feed page as post ids, then the posts by id
            // (its page sizes: 6 first, then 24).
            var cursor = after
            // PostsByIds drops removed posts, so a page can come back empty
            // while the feed goes on: skip ahead a few pages, not end it there.
            for _ in 0..<5 {
                guard let q = gqlFeedQuery(subreddit, sort, time, cursor) else { throw RedditApiException(statusCode: 403) }
                let ids = gqlFeedPostIds(try await self.client.gql(q.operation, q.hash, q.variables))
                let posts = try await self.getPostsByIds(ids)
                cursor = ids.last
                if !posts.isEmpty || cursor == nil { return Listing(items: posts, after: cursor) }
            }
            return Listing(items: [])
        }
    }

    /// The last cached first page for exactly this feed, or nil (to paint instantly).
    func cachedPosts(subreddit: String? = nil, sort: PostSort = .best, time: TopTime = .day, limit: Int = 25) async -> Listing<Post>? {
        let base = subreddit.map { "/r/\($0)" } ?? ""
        guard let json = await client.cached("\(base)/\(sort.path)", postsQuery(sort, time, nil, limit)) else { return nil }
        let listing = parsePostListing(json, fromCache: true)
        return listing.items.isEmpty ? nil : listing
    }

    func getComments(subreddit: String, postId: String, sort: String = "confidence", focusCommentId: String? = nil, limit: Int = 100) async throws -> RedditThread {
        try parseThread(try await getCommentsRaw(subreddit: subreddit, postId: postId, sort: sort, focusCommentId: focusCommentId, limit: limit))
    }

    /// The raw comments response — kept as-is for offline reading.
    func getCommentsRaw(subreddit: String, postId: String, sort: String = "confidence", focusCommentId: String? = nil, limit: Int = 100) async throws -> JsonElement {
        // `_` (or empty) means the subreddit is unknown (e.g. a redd.it link).
        let unknown = subreddit.isEmpty || subreddit == "_"
        let path = unknown ? "/comments/\(postId)" : "/r/\(subreddit)/comments/\(postId)"
        var query: Fields = [("sort", sort), ("limit", "\(limit)")]
        // Focus on a single comment (permalink / inbox reply): Reddit returns
        // that comment's thread with a few parents for context.
        if let focusCommentId {
            query.append(("comment", focusCommentId))
            query.append(("context", "3"))
        }
        return try await orGql {
            try await self.client.get(path, query)
        } gql: {
            // Reddit's app loads the post by id and its comments side by side.
            async let post = self.client.gql("PostsByIds", GQL_POSTS_BY_IDS, postsByIdsVariables(["t3_\(postId)"]))
            async let forest = self.client.gql("PostComments", GQL_POST_COMMENTS, postCommentsVariables("t3_\(postId)", sort, focusCommentId, nil))
            let first = try await post["postsInfoByIds"][0]
            guard let p = first.obj(), gqlIsPost(first) else { throw AppException("This post isn't available") }
            let trees = try await forest["postInfoById"]["commentForest"]["trees"].arr() ?? []
            return gqlThreadData(gqlPostData(p), trees)
        }
    }

    /// Commenters' profile pictures (#133), lowercased name → url, from the first page of
    /// the thread's GraphQL comment forest (the .json comments carry none). Website sign-in only.
    func getCommentAvatars(postId: String, sort: String) async throws -> [String: String] {
        let data = try await client.gql("PostComments", GQL_POST_COMMENTS, postCommentsVariables("t3_\(postId)", sort, nil, nil))
        return gqlAuthorIcons(data["postInfoById"]["commentForest"]["trees"].arr() ?? [])
    }

    /// Parses a comments response (live or saved offline).
    func parseThread(_ body: JsonElement) throws -> RedditThread {
        guard let postData = body[0]["data"]["children"][0]["data"] else { throw AppException("This post isn't available") }
        let post = Post.fromData(postData)
        if post.missingCrosspostParent { fillCrossposts([(post, postData)]) }
        let comments = (body[1]["data"]["children"].arr() ?? []).filter { $0.obj() != nil }.map { Comment.fromChild($0, 0) }
        return RedditThread(post: post, comments: comments, suggestedSort: postData["suggested_sort"].str()?.nilIfEmpty)
    }

    /// Expands a "load more comments" node (flat list, rendered at its depth).
    func getMoreComments(linkFullname: String, moreNode: Comment, sort: String = "confidence") async throws -> [Comment] {
        let childrenIds = moreNode.moreChildren
        let depth = moreNode.depth
        // A "more" row from the GraphQL fallback: continue it by its cursor.
        if childrenIds.count == 1, childrenIds[0].hasPrefix(GQL_MORE) {
            let rest = childrenIds[0].removePrefix(GQL_MORE)
            let parent = rest.substringBefore(" ")
            let cursor = rest.substringAfter(" ", missing: "")
            let data = try await client.gql("PostComments", GQL_POST_COMMENTS, postCommentsVariables(linkFullname, sort, nil, cursor))
            let trees = data["postInfoById"]["commentForest"]["trees"].arr() ?? []
            return gqlCommentThings(trees, linkFullname, moreParent: parent).map { Comment.fromChild($0, depth) }
        }
        // Reddit answers /api/morechildren with a 403 since late October 2026
        // (#59), so the hidden replies come from the thread itself.
        let postId = linkFullname.removePrefix("t3_")
        func fetch(_ focus: String?) async throws -> [Comment] {
            let raw = try await getCommentsRaw(subreddit: "", postId: postId, sort: sort, focusCommentId: focus, limit: moreLimit)
            return CommentTree.flatten(try parseThread(raw).comments, [])
        }
        let parent = moreNode.parentId
        let page: [Comment]
        if parent.hasPrefix("t1_") {
            let all = try await fetch(parent.removePrefix("t1_"))
            page = CommentTree.flatten(all.first { $0.fullname == parent }?.replies ?? [], [])
        } else {
            page = try await fetch(nil)
        }
        // Not the row itself coming back: a "more" row takes its first child's id.
        if page.contains(where: { !$0.isMore && childrenIds.contains($0.id) }) { return page }
        // Past what one page holds (a huge thread): fetch some of the hidden
        // comments one by one, and leave the rest on the row.
        var batch: [Comment] = []
        for id in childrenIds.prefix(moreBatch) {
            let all = try await fetch(id)
            batch += CommentTree.flatten(all.first { $0.id == id }.map { [$0] } ?? [], [])
        }
        let rest = Array(childrenIds.dropFirst(moreBatch))
        if rest.isEmpty { return batch }
        return batch + [moreNode.with {
            $0.moreChildren = rest
            $0.moreCount = max(moreNode.moreCount - moreBatch, rest.count)
        }]
    }

    func getSubredditAbout(_ name: String) async throws -> Subreddit {
        guard let d = try await client.get("/r/\(name)/about")["data"] else { throw AppException("r/\(name) wasn't found") }
        return Subreddit.fromData(d)
    }

    /// Subreddit rules as (title, description) pairs.
    func getSubredditRules(_ name: String) async throws -> [(title: String, description: String)] {
        (try await client.get("/r/\(name)/about/rules")["rules"].arr() ?? []).compactMap { r in
            r.obj() == nil ? nil : ((r["short_name"].str() ?? "").trimmed, (r["description"].str() ?? "").trimmed)
        }
    }

    func getUserAbout(_ username: String) async throws -> RedditUser {
        guard let d = try await client.get("/user/\(username)/about")["data"] else { throw AppException("u/\(username) wasn't found") }
        // A suspended account still answers, with only its name: say so, not "0 karma, joined 1970".
        if d["is_suspended"].isTrue() { throw AppException("u/\(username) has been suspended.") }
        return RedditUser.fromData(d)
    }

    /// [where] ∈ submitted | upvoted | downvoted | hidden (post listings); [sort] (and [time] for Top) only for submitted.
    func getUserPosts(_ username: String, where place: String = "submitted", after: String? = nil, limit: Int = 25, sort: PostSort? = nil, time: TopTime? = nil) async throws -> Listing<Post> {
        let json = try await client.get(
            "/user/\(username)/\(place)",
            [("limit", "\(limit)"), ("after", after), ("sr_detail", "true"), ("sort", sort?.path), ("t", time?.param)]
        )
        return parsePostListing(json)
    }

    func getUserComments(_ username: String, after: String? = nil, sort: PostSort? = nil, time: TopTime? = nil) async throws -> Listing<Comment> {
        let json = try await client.get(
            "/user/\(username)/comments",
            [("limit", "25"), ("after", after), ("sort", sort?.path), ("t", time?.param)]
        )
        let data = json["data"]
        return Listing(
            items: (data["children"].arr() ?? []).filter { $0["kind"].str() == "t1" }.map { Comment.fromChild($0, 0) },
            after: data["after"].str()
        )
    }

    /// Saved items are mixed posts (t3) and comments (t1), in original order.
    func getUserSaved(_ username: String, after: String? = nil, limit: Int = 25) async throws -> Listing<SavedItem> {
        let json = try await client.get("/user/\(username)/saved", [("limit", "\(limit)"), ("after", after), ("sr_detail", "true")])
        let data = json["data"]
        var crossposts: [(Post, JsonElement)] = []
        let items = (data["children"].arr() ?? []).compactMap { c -> SavedItem? in
            switch c["kind"].str() {
            case "t3":
                guard let raw = c["data"] else { return nil }
                let post = Post.fromData(raw)
                if post.missingCrosspostParent { crossposts.append((post, raw)) }
                return .post(post)
            case "t1": return .comment(Comment.fromChild(c, 0))
            default: return nil
            }
        }
        fillCrossposts(crossposts)
        return Listing(items: items, after: data["after"].str())
    }

    func searchPosts(_ query: String, subreddit: String? = nil, after: String? = nil, sort: String = "relevance", time: String = "all") async throws -> Listing<Post> {
        if await client.isWebMode() {
            // The posts come from the results themselves: /by_id.json is refused too.
            let (nodes, next) = gqlSearch(
                try await client.gql("SearchPosts", GQL_SEARCH_POSTS, searchPostsVariables(query, subreddit, after, sort, time)),
                "posts"
            )
            return Listing(items: nodes.map { Post.fromData(.object(gqlPostData($0))) }, after: next)
        }
        let base = subreddit.map { "/r/\($0)/search" } ?? "/search"
        var q: Fields = [("q", query), ("type", "link"), ("sort", sort), ("t", time), ("limit", "25"), ("sr_detail", "true")]
        if subreddit != nil { q.append(("restrict_sr", "true")) }
        if let after { q.append(("after", after)) }
        return parsePostListing(try await client.get(base, q))
    }

    func searchSubreddits(_ query: String) async throws -> [Subreddit] {
        if await client.isWebMode() {
            let vars: JsonObject = [
                "query": .string(leadingR.replace(query.trimmed, with: "")),
                "productSurface": "android",
                "first": 25,
            ]
            let (nodes, _) = gqlSearch(try await client.gql("CommunityPickerSearchPaginated", GQL_SEARCH_COMMUNITIES, vars), "communities")
            return nodes.filter { $0["__typename"].str() == "Subreddit" && $0["name"].str() != nil }.map { Subreddit.fromData(gqlSubredditData($0)) }
        }
        let json = try await client.get("/subreddits/search", [("q", query), ("limit", "25")])
        return (json["data"]["children"].arr() ?? []).compactMap { $0["data"].map(Subreddit.fromData) }
    }

    func searchUsers(_ query: String) async throws -> [RedditUser] {
        if await client.isWebMode() {
            let vars: JsonObject = ["query": .string(query), "productSurface": "android", "pageSize": 25]
            let (nodes, _) = gqlSearch(try await client.gql("SearchPeople", GQL_SEARCH_PEOPLE, vars), "authors")
            return nodes.filter { $0["__typename"].str() == "Redditor" && $0["name"].str() != nil }.map { RedditUser.fromData(gqlUserData($0)) }
        }
        let json = try await client.get("/search", [("q", query), ("type", "user"), ("limit", "25")])
        return (json["data"]["children"].arr() ?? []).compactMap { $0["data"].map(RedditUser.fromData) }
    }

    /// Drops the in-memory subscription cache (e.g. on account switch).
    func clearSubsCache() {
        state.withLock {
            $0.subsCache = nil
            $0.subsCacheAt = 0
        }
    }

    /// Subscriptions: favourites first, then alphabetical.
    func getSubscribedSubreddits(force: Bool = false) async throws -> [Subreddit] {
        let cached: [Subreddit]? = state.withLock { s in
            if !force, s.subsCacheEnabled, let c = s.subsCache, nowMillis() - s.subsCacheAt < s.subsCacheTtlMillis { return c }
            return nil
        }
        if let cached { return cached }
        var result: [Subreddit] = []
        var after: String?
        // Reddit caps at 100/page; loop a few pages for heavy subscribers.
        for _ in 0..<5 {
            let data = try await client.get("/subreddits/mine/subscriber", [("limit", "100"), ("after", after)])["data"]
            for c in data["children"].arr() ?? [] {
                if let d = c["data"] { result.append(Subreddit.fromData(d)) }
            }
            after = data["after"].str()
            if after == nil { break }
        }
        let sorted = result.enumerated().sorted { a, b in
            if a.element.userHasFavorited != b.element.userHasFavorited { return a.element.userHasFavorited }
            let (x, y) = (a.element.name.lowercased(), b.element.name.lowercased())
            return x != y ? x < y : a.offset < b.offset
        }.map(\.element)
        state.withLock {
            $0.subsCache = sorted
            $0.subsCacheAt = nowMillis()
        }
        return sorted
    }

    func setSubredditFavorite(_ subredditName: String, favorite: Bool) async throws {
        try await client.post("/api/favorite", [("sr_name", subredditName), ("make_favorite", "\(favorite)")])
        state.withLock { $0.subsCache = nil } // favourite flag changed
    }

    // --- Moderation (requires mod permission on the thing's subreddit) ---

    func modApprove(_ fullname: String) async throws { try await client.post("/api/approve", [("id", fullname)]) }

    func modRemove(_ fullname: String, spam: Bool = false) async throws {
        try await client.post("/api/remove", [("id", fullname), ("spam", "\(spam)")])
    }

    func modLock(_ fullname: String, lock: Bool) async throws {
        try await client.post(lock ? "/api/lock" : "/api/unlock", [("id", fullname)])
    }

    /// how: 'yes' (mod), 'no', or 'admin'. [sticky] pins a top comment.
    func modDistinguish(_ fullname: String, how: String = "yes", sticky: Bool = false) async throws {
        try await client.post("/api/distinguish", [("id", fullname), ("how", how), ("sticky", "\(sticky)"), ("api_type", "json")])
    }

    /// dir: 1 upvote, -1 downvote, 0 clear.
    func vote(_ fullname: String, dir: Int) async throws {
        try await orGql {
            try await self.client.post("/api/vote", [("id", fullname), ("dir", "\(dir)"), ("rank", "10")])
        } gql: {
            let post = fullname.hasPrefix("t3_")
            let state = dir == 1 ? "UP" : dir == -1 ? "DOWN" : "NONE"
            try await self.gqlMutation(
                post ? "UpdatePostVoteState" : "UpdateCommentVoteState",
                post ? GQL_POST_VOTE : GQL_COMMENT_VOTE,
                post ? "updatePostVoteState" : "updateCommentVoteState",
                [post ? "postId" : "commentId": .string(fullname), "voteState": .string(state)]
            )
            return nil
        }
    }

    /// Website sign-in: [rest], or when Reddit's edge refuses it (403, as it
    /// did for search and /by_id) the same thing through GraphQL ([gql]). A
    /// 403 with a reason (a private, quarantined or gated subreddit) is
    /// Reddit's own answer, not the edge's page.
    @discardableResult
    private func orGql<T>(_ rest: () async throws -> T, gql: () async throws -> T) async throws -> T {
        do {
            return try await rest()
        } catch let e as RedditApiException {
            if e.statusCode != 403 { throw e }
            if e.reason != nil { throw e }
            if await !client.isWebMode() { throw e }
            return try await gql()
        }
    }

    /// A GraphQL mutation taking `input`, whose result is [field].
    private func gqlMutation(_ operation: String, _ hash: String, _ field: String, _ input: JsonObject) async throws {
        try gqlCheckOk(try await client.gql(operation, hash, ["input": .object(input)])[field])
    }

    /// Opts in to a quarantined or gated ([reason]) subreddit so its posts load.
    /// Only quarantine has an OAuth API; the website sign-in uses GraphQL,
    /// like Reddit's app.
    func optInSubreddit(_ name: String, reason: String) async throws {
        if await !client.isWebMode() {
            try await client.post("/api/quarantine_option", [("sr_name", name), ("accept", "true")])
            return
        }
        if reason == "gated" {
            try await gqlMutation("UpdateOptInToGatedSubreddit", GQL_OPT_IN_GATED, "optInToGatedSubreddit", ["subredditName": .string(name)])
        } else {
            guard let id = try await client.gql("SubredditInfoByName", GQL_SUBREDDIT_INFO, subredditInfoVariables(name))["subredditInfoByName"]["id"].str() else {
                throw AppException("r/\(name) wasn't found")
            }
            try await gqlMutation("UpdateOptInToQuarantinedSubreddit", GQL_OPT_IN_QUARANTINED, "updateSubredditQuarantineOptInState", [
                "subredditId": .string(id), "optInState": "OPTED_IN",
            ])
        }
    }

    /// Whether [reason] (a refused subreddit's) is one the user can opt in to here.
    func canOptIn(_ reason: String?) async -> Bool {
        if reason == "quarantined" { return true }
        if reason == "gated" { return await client.isWebMode() }
        return false
    }

    func setSubscribed(_ subredditName: String, subscribe: Bool) async throws {
        try await client.post("/api/subscribe", [("action", subscribe ? "sub" : "unsub"), ("sr_name", subredditName)])
        state.withLock { $0.subsCache = nil } // subscription set changed
    }

    func setSaved(_ fullname: String, saved: Bool) async throws {
        try await orGql {
            try await self.client.post(saved ? "/api/save" : "/api/unsave", [("id", fullname)])
        } gql: {
            let post = fullname.hasPrefix("t3_")
            try await self.gqlMutation(
                post ? "UpdatePostSaveState" : "UpdateCommentSaveState",
                post ? GQL_POST_SAVE : GQL_COMMENT_SAVE,
                post ? "updatePostSaveState" : "updateCommentSaveState",
                [post ? "postId" : "commentId": .string(fullname), "saveState": saved ? "SAVED" : "NONE"]
            )
            return nil
        }
    }

    // --- Participate: reply / submit / edit / delete ---

    private func apiErrors(_ body: JsonElement?) -> [String] {
        (body["json"]["errors"].arr() ?? []).map { e in
            if let list = e.arr(), list.count > 1 { return list[1].content() ?? list[1].encoded() }
            return e.encoded()
        }
    }

    private func throwIfErrors(_ body: JsonElement?) throws {
        if let first = apiErrors(body).first { throw AppException(first) }
    }

    /// Replies to [parentFullname] (t3_ post or t1_ comment); returns the new comment at [depth].
    func reply(_ parentFullname: String, text: String, richtextJson: String? = nil, depth: Int = 0) async throws -> Comment {
        var data: Fields = [("api_type", "json"), ("thing_id", parentFullname)]
        if let richtextJson { data.append(("richtext_json", richtextJson)) } else { data.append(("text", text)) }
        let res = try await client.post("/api/comment", data)
        try throwIfErrors(res)
        guard let thing = res["json"]["data"]["things"][0] else { throw AppException("Reddit did not return the new comment.") }
        let c = Comment.fromChild(thing, depth)
        // A website session gets the legacy reply format: id + rendered HTML,
        // no author, body or timestamp. Fill those in from what was sent, or
        // the new comment shows up blank (it looked like the reply vanished).
        if !c.body.isEmpty, c.author != "[deleted]" { return c }
        let username = await app.session.username
        return c.with {
            $0.author = username
            $0.body = text
            $0.parentId = c.parentId.nilIfEmpty ?? parentFullname
            $0.createdUtc = nowMillis()
            $0.score = 1
            $0.likes = true
        }
    }

    /// Reddit's answer when a subreddit doesn't allow images in comments.
    private func isImageRefusal(_ message: String?) -> Bool {
        guard let m = message?.lowercased() else { return false }
        return m.contains("image") || m.contains("media") || m.contains("richtext") || m.contains("not allowed")
    }

    /// A comment reply with an inline image hosted by Reddit via the richtext
    /// API (as the official app does). Subreddits that disallow comment images
    /// reject it, so fall back to Catbox and drop a link into the comment.
    func replyWithImage(_ parentFullname: String, text: String, bytes: Data, filename: String, mimeType: String, depth: Int = 0) async throws -> Comment {
        func viaCatbox() async throws -> Comment {
            let url = try await uploadToCatbox(bytes, filename: filename)
            return try await reply(parentFullname, text: text.isEmpty ? url : "\(text)\n\n\(url)", depth: depth)
        }
        // Reddit wouldn't take the image (upload failed): host it on Catbox.
        let asset: MediaAsset
        do {
            asset = try await uploadMediaAsset(bytes, filename: filename, mimeType: mimeType)
        } catch {
            if Task.isCancelled || error is CancellationError { throw error }
            return try await viaCatbox()
        }
        do {
            var document: [JsonElement] = []
            if !text.isEmpty { document.append(["e": "par", "c": [["e": "text", "t": .string(text)]]]) }
            document.append(["e": "img", "id": .string(asset.assetId)])
            let doc: JsonElement = ["document": .array(document)]
            return try await reply(parentFullname, text: text, richtextJson: doc.encoded(), depth: depth)
        } catch let e as RedditApiException {
            // Only when the subreddit refuses images in comments. Anything else
            // (rate limit, locked thread, a network error after Reddit may have
            // accepted it) is reported as-is: falling back then published the
            // image on Catbox and could post the comment twice.
            if !isImageRefusal(e.message) { throw e }
            return try await viaCatbox()
        } catch let e as AppException {
            if !isImageRefusal(e.message) { throw e }
            return try await viaCatbox()
        }
    }

    /// Edits the body of your own post (selftext) or comment. Returns the new body.
    func editText(_ thingFullname: String, text: String) async throws -> String {
        try throwIfErrors(try await client.post("/api/editusertext", [("api_type", "json"), ("thing_id", thingFullname), ("text", text)]))
        return text
    }

    func deleteThing(_ fullname: String) async throws { try await client.post("/api/del", [("id", fullname)]) }

    /// Submits a text, link or image post (upload images first with
    /// [uploadImage]). Returns the new post id.
    func submitPost(
        _ subreddit: String,
        title: String,
        kind: String, // 'self' | 'link' | 'image'
        text: String? = nil,
        url: String? = nil,
        nsfw: Bool = false,
        spoiler: Bool = false,
        sendReplies: Bool = true,
        flair: Flair? = nil
    ) async throws -> String {
        var data: Fields = [("api_type", "json"), ("sr", subreddit), ("title", title), ("kind", kind)]
        if kind == "self" { data.append(("text", text ?? "")) }
        if kind == "link" || kind == "image" {
            data.append(("url", url ?? ""))
            if let text, !text.isEmpty { data.append(("text", text)) }
        }
        if let flair {
            data.append(("flair_id", flair.id))
            data.append(("flair_text", flair.text))
        }
        data.append(("nsfw", "\(nsfw)"))
        data.append(("spoiler", "\(spoiler)"))
        data.append(("sendreplies", "\(sendReplies)"))
        let res = try await client.post("/api/submit", data)
        try throwIfErrors(res)
        let id = res["json"]["data"]["id"].str()
        // Image posts are created asynchronously: Reddit answers with a
        // websocket URL, not the id. No errors means it was posted (treating it
        // as a failure invited a duplicate post).
        if id == nil, kind == "image" { return "" }
        guard let id else { throw AppException("Reddit did not return the new post.") }
        return id
    }

    // --- Inbox / messages ---

    /// [where] ∈ inbox | unread | messages | sent | comments | mentions.
    func getInbox(where place: String = "inbox", after: String? = nil, limit: Int = 25) async throws -> Listing<InboxItem> {
        let data = try await client.get("/message/\(place)", [("limit", "\(limit)"), ("after", after)])["data"]
        return Listing(items: (data["children"].arr() ?? []).map { InboxItem.fromChild($0) }, after: data["after"].str())
    }

    /// One page of 100 (Reddit's max): the badge shows "99+" beyond that.
    func getUnreadCount() async throws -> Int { try await getInbox(where: "unread", limit: 100).items.count }

    func markRead(_ fullname: String) async throws { try await client.post("/api/read_message", [("id", fullname)]) }
    func markAllRead() async throws { try await client.post("/api/read_all_messages") }
    func markUnread(_ fullname: String) async throws { try await client.post("/api/unread_message", [("id", fullname)]) }

    /// Deletes a private message (t4_ only; comment replies can't be deleted).
    func deleteMessage(_ fullname: String) async throws { try await client.post("/api/del_msg", [("id", fullname)]) }

    /// Replies to a message or inbox comment (thing_id = t4_/t1_ fullname).
    func sendReply(_ parentFullname: String, text: String) async throws {
        try throwIfErrors(try await client.post("/api/comment", [("api_type", "json"), ("thing_id", parentFullname), ("text", text)]))
    }

    func composeMessage(to: String, subject: String, text: String) async throws {
        try throwIfErrors(try await client.post("/api/compose", [("api_type", "json"), ("to", to), ("subject", subject), ("text", text)]))
    }

    /// Uploads media to Reddit's media store: lease from Reddit, then S3 POST.
    /// Returns the public S3 url (link/image/video posts) and the asset id
    /// (= media_id, needed for galleries and richtext images).
    func uploadMediaAsset(_ bytes: Data, filename: String, mimeType: String) async throws -> MediaAsset {
        let lease = try await client.post("/api/media/asset.json", [("filepath", filename), ("mimetype", mimeType)])
        let args = lease["args"]
        guard let action = args["action"].str() else { throw AppException("Could not get an upload lease.") }
        let assetId = lease["asset"]["asset_id"].str() ?? ""
        var form = MultipartForm()
        for f in args["fields"].arr() ?? [] {
            guard let name = f["name"].str() else { continue }
            form.add(name: name, value: f["value"].content() ?? "")
        }
        form.add(name: "file", filename: filename, data: bytes)
        var req = URLRequest(url: URL(string: action.hasPrefix("http") ? action : "https:\(action)")!)
        req.httpMethod = "POST"
        req.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        req.httpBody = form.finished()
        let xml = String(decoding: try await Http.session.send(req).body, as: UTF8.self)
        guard let location = locationRe.firstMatch(xml)?.groups[1].htmlAmpFixed() else { throw AppException("Upload failed (no location).") }
        return MediaAsset(url: location, assetId: assetId)
    }

    func uploadImage(_ bytes: Data, filename: String, mimeType: String) async throws -> String {
        try await uploadMediaAsset(bytes, filename: filename, mimeType: mimeType).url
    }

    // --- Post actions: hide / report / block / crosspost ---

    func setHidden(_ fullname: String, hidden: Bool) async throws {
        try await client.post(hidden ? "/api/hide" : "/api/unhide", [("id", fullname)])
    }

    func report(_ fullname: String, reason: String) async throws {
        try await client.post("/api/report", [("thing_id", fullname), ("reason", reason)])
    }

    /// Blocks a user (you stop seeing their posts/comments/messages).
    func blockUser(_ username: String) async throws { try await client.post("/api/block_user", [("name", username)]) }

    func submitCrosspost(_ subreddit: String, title: String, crosspostFullname: String, nsfw: Bool = false, spoiler: Bool = false) async throws -> String {
        let res = try await client.post("/api/submit", [
            ("api_type", "json"), ("sr", subreddit), ("title", title), ("kind", "crosspost"),
            ("crosspost_fullname", crosspostFullname), ("nsfw", "\(nsfw)"), ("spoiler", "\(spoiler)"),
            ("sendreplies", "true"),
        ])
        try throwIfErrors(res)
        guard let id = res["json"]["data"]["id"].str() else { throw AppException("Crosspost failed.") }
        return id
    }

    // --- Flair ---

    /// Your user flair in [subreddit] (from its About, which carries it for the
    /// signed-in user) and the choices it offers (user_flair_v2; empty when it
    /// has none for you, or won't let you pick).
    func getUserFlairSelector(_ subreddit: String) async throws -> UserFlairSelector {
        let about = try await client.get("/r/\(subreddit)/about")["data"]
        var choices: [UserFlairChoice] = []
        do {
            // ".json": the website session's www host 404s this path without it.
            choices = (try await client.get("/r/\(subreddit)/api/user_flair_v2.json").arr() ?? []).compactMap { c in
                guard let id = c["id"].str() else { return nil }
                return UserFlairChoice(id: id, text: c["text"].str()?.trimmed ?? "", editable: c["text_editable"].isTrue())
            }
        } catch {
            if Task.isCancelled { throw error } // else 403: no user flair here for you
        }
        return UserFlairSelector(
            currentText: about["user_flair_text"].str().flatMap { flairCode.replace($0, with: "").trimmed.nilIfEmpty },
            currentId: about["user_flair_template_id"].str()?.nilIfEmpty,
            choices: choices
        )
    }

    /// Sets your user flair in [subreddit] ([choice] nil: no flair). [text]: your words, for an editable choice.
    func setUserFlair(_ subreddit: String, username: String, choice: UserFlairChoice?, text: String?) async throws {
        var data: Fields = [("api_type", "json"), ("name", username)]
        if let choice {
            data.append(("flair_template_id", choice.id))
            if choice.editable, let text { data.append(("text", text)) }
        }
        try throwIfErrors(try await client.post("/r/\(subreddit)/api/selectflair", data))
    }

    /// The post flairs you can pick in [subreddit] (v2: with colours, emoji and editable text; ".json" as for user flair).
    func getLinkFlairs(_ subreddit: String) async -> [Flair] {
        // Failure: the subreddit may have no flairs / no permission.
        let json = try? await client.get("/r/\(subreddit)/api/link_flair_v2.json")
        return (json.arr() ?? []).map(Flair.fromJson).filter { !$0.text.isEmpty }
    }

    /// Sets the flair of your post [postFullname] in [subreddit] ([flair] nil: no flair; its text is yours for an editable one).
    func setPostFlair(_ subreddit: String, postFullname: String, flair: Flair?) async throws {
        try throwIfErrors(try await client.post("/r/\(subreddit)/api/selectflair", Self.postFlairForm(postFullname, flair)))
    }

    /// /api/selectflair's form for a post's flair; the text only for an editable template, as for user flair.
    static func postFlairForm(_ postFullname: String, _ flair: Flair?) -> Fields {
        var data: Fields = [("api_type", "json"), ("link", postFullname)]
        if let flair {
            data.append(("flair_template_id", flair.id))
            if flair.editable { data.append(("text", flair.text)) }
        }
        return data
    }

    // --- Gallery & video submission ---

    /// Submits a gallery post from already-uploaded media ids (asset_ids).
    func submitGalleryPost(_ subreddit: String, title: String, mediaIds: [String], text: String = "", nsfw: Bool = false, spoiler: Bool = false, sendReplies: Bool = true, flair: Flair? = nil) async throws {
        var body: JsonObject = [
            "sr": .string(subreddit),
            "submit_type": "subreddit",
            "api_type": "json",
            "show_error_list": true,
            "title": .string(title),
            "text": .string(text),
            "spoiler": .bool(spoiler),
            "nsfw": .bool(nsfw),
            "kind": "self",
            "original_content": false,
            "post_to_twitter": false,
            "sendreplies": .bool(sendReplies),
            "validate_on_submit": true,
        ]
        if let flair {
            body["flair_id"] = .string(flair.id)
            body["flair_text"] = .string(flair.text)
        }
        body["items"] = .array(mediaIds.map { ["caption": "", "outbound_url": "", "media_id": .string($0)] })
        try throwIfErrors(try await client.postJson("/api/submit_gallery_post.json", body.encoded()))
    }

    /// Submits a video (or video-gif) post from S3 urls returned by [uploadMediaAsset].
    func submitVideoPost(_ subreddit: String, title: String, videoUrl: String, posterUrl: String, isGif: Bool = false, text: String = "", nsfw: Bool = false, spoiler: Bool = false, sendReplies: Bool = true, flair: Flair? = nil) async throws -> String {
        var data: Fields = [
            ("api_type", "json"), ("sr", subreddit), ("title", title),
            ("kind", isGif ? "videogif" : "video"), ("url", videoUrl), ("video_poster_url", posterUrl),
        ]
        if !text.isEmpty { data.append(("text", text)) }
        if let flair {
            data.append(("flair_id", flair.id))
            data.append(("flair_text", flair.text))
        }
        data.append(("nsfw", "\(nsfw)"))
        data.append(("spoiler", "\(spoiler)"))
        data.append(("sendreplies", "\(sendReplies)"))
        let res = try await client.post("/api/submit", data)
        try throwIfErrors(res)
        return res["json"]["data"]["id"].str() ?? ""
    }

    // --- Multireddits ---

    func getMyMultireddits() async throws -> [Multireddit] {
        (try await client.get("/api/multi/mine", [("expand_srs", "true")]).arr() ?? [])
            .compactMap { $0["data"].map(Multireddit.fromData) }
            .sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
    }

    func getMultiPosts(username: String, multiname: String, sort: PostSort = .hot, time: TopTime = .day, after: String? = nil, limit: Int = 25) async throws -> Listing<Post> {
        let res = try await client.getResult("/user/\(username)/m/\(multiname)/\(sort.path)", postsQuery(sort, time, after, limit))
        return parsePostListing(res.json, fromCache: res.fromCache)
    }

    func createMultireddit(username: String, name: String, subreddits: [String] = [], visibility: String = "private", description: String = "") async throws {
        let multipath = "/user/\(username)/m/\(name)"
        let model: JsonElement = [
            "display_name": .string(name),
            "subreddits": .array(subreddits.map { ["name": .string($0)] }),
            "visibility": .string(visibility),
            "description_md": .string(description),
        ]
        try throwIfErrors(try await client.post("/api/multi\(multipath)", [("model", model.encoded()), ("multipath", multipath), ("api_type", "json")]))
    }

    func deleteMultireddit(_ multipath: String) async throws { try await client.delete("/api/multi\(multipath)") }

    /// Renames / re-describes a custom feed, or makes it public or private (its communities stay).
    func updateMultireddit(_ multi: Multireddit, displayName: String, description: String, visibility: String) async throws {
        let multipath = multi.path.trimmingEnd("/")
        let model: JsonElement = [
            "display_name": .string(displayName),
            "description_md": .string(description),
            "visibility": .string(visibility),
            "subreddits": .array(multi.subreddits.map { ["name": .string($0)] }),
        ]
        try throwIfErrors(try await client.putForm("/api/multi\(multipath)", [("model", model.encoded()), ("multipath", multipath), ("api_type", "json")]))
    }

    /// Copies someone's (public) custom feed into yours as [displayName].
    func copyMultireddit(fromPath: String, username: String, displayName: String) async throws {
        let name = String(notFeedName.replace(displayName.lowercased(), with: "_").trimming("_").prefix(50)).nilIfEmpty ?? "feed"
        try throwIfErrors(try await client.post("/api/multi/copy", [
            ("from", fromPath.trimmingEnd("/")), ("to", "/user/\(username)/m/\(name)"), ("display_name", displayName), ("api_type", "json"),
        ]))
    }

    func addSubredditToMulti(_ multipath: String, subreddit: String) async throws {
        let body: JsonElement = ["name": .string(subreddit)]
        try await client.put("/api/multi\(multipath)/r/\(subreddit)", body.encoded())
    }

    func removeSubredditFromMulti(_ multipath: String, subreddit: String) async throws {
        try await client.delete("/api/multi\(multipath)/r/\(subreddit)")
    }

    /// One private-message conversation (root + replies) by any
    /// message id in it, for opening a thread from a notification.
    func getMessageThread(_ id: String) async throws -> InboxItem? {
        let json = try await client.get("/message/messages/\(id.removePrefix("t4_"))")
        return json["data"]["children"].arr()?.first.map { InboxItem.fromChild($0) }
    }
}
