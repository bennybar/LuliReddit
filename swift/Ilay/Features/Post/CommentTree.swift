import Foundation

/// Pure comment-tree operations, shared by the comments view model and the
/// unit tests.
enum CommentTree {
    /// The collapse-set key that folds [id]'s replies away (its own text stays).
    static func folded(_ id: String) -> String { "f:\(id)" }

    /// How many comments are under [c] (all levels; "more" rows not counted).
    static func replyCount(_ c: Comment) -> Int {
        c.replies.reduce(0) { $0 + ($1.isMore ? 0 : 1 + replyCount($1)) }
    }

    /// Depth-first visible rows: a collapsed comment's replies (and a "more"
    /// node's) are skipped. A [folded] comment ("f:<id>" in [collapsed]: the
    /// "Open threads collapsed" setting) shows in full but hides its replies.
    static func flatten(_ nodes: [Comment], _ collapsed: Set<String>) -> [Comment] {
        var out: [Comment] = []
        out.reserveCapacity(nodes.count * 2)
        func walk(_ c: Comment) {
            out.append(c)
            if !c.isMore, !collapsed.contains(c.id), !collapsed.contains(folded(c.id)) { c.replies.forEach(walk) }
        }
        nodes.forEach(walk)
        return out
    }

    /// [c] and its parents up to the top-level comment, top first — the
    /// chain a "Share as image" card shows (at most 8). Visible rows include
    /// every ancestor of a visible comment.
    static func chainTo(_ flat: [Comment], _ c: Comment) -> [Comment] {
        let byName = Dictionary(flat.map { ($0.fullname, $0) }, uniquingKeysWith: { _, last in last })
        var chain = [c]
        var parent = byName[c.parentId]
        while let p = parent, chain.count < 8 {
            chain.insert(p, at: 0)
            parent = byName[p.parentId]
        }
        return chain
    }

    /// Splices [reply] under [parentFullname] (newest first), at its parent's depth + 1.
    static func insertReply(_ nodes: [Comment], _ parentFullname: String, _ reply: Comment) -> [Comment] {
        nodes.map { n in
            if n.fullname == parentFullname {
                return n.with { $0.replies = [reply.with { $0.depth = n.depth + 1 }] + n.replies }
            }
            return n.replies.isEmpty ? n : n.with { $0.replies = insertReply(n.replies, parentFullname, reply) }
        }
    }

    /// Applies [change] to one comment. Vote and save state live in the tree
    /// rather than the row, which the list disposes as it scrolls off-screen —
    /// so they survive scrolling away and back. Untouched subtrees are left as
    /// they are (cheap: they keep sharing their storage).
    static func update(_ nodes: [Comment], _ fullname: String, _ change: (Comment) -> Comment) -> [Comment] {
        func contains(_ list: [Comment]) -> Bool {
            list.contains { $0.fullname == fullname || contains($0.replies) }
        }
        return nodes.map { n in
            if n.fullname == fullname { return change(n) }
            if n.replies.isEmpty || !contains(n.replies) { return n }
            return n.with { $0.replies = update(n.replies, fullname, change) }
        }
    }

    /// After deleting a comment: drop it, or — if it has replies — keep the
    /// replies under a "[deleted]" placeholder, as Reddit does.
    static func remove(_ nodes: [Comment], _ fullname: String) -> [Comment] {
        nodes.compactMap { n in
            if n.fullname != fullname {
                return n.replies.isEmpty ? n : n.with { $0.replies = remove(n.replies, fullname) }
            }
            if !n.replies.isEmpty {
                return n.with {
                    $0.author = "[deleted]"
                    $0.body = "[deleted]"
                    $0.media = [:]
                }
            }
            return nil
        }
    }

    /// Re-nests a flat list of fetched comments by parent_id and splices it in
    /// place of [moreNode] (matched by fullname). They come from re-reading the
    /// thread, so some are already on screen: those are dropped, as a duplicate
    /// key would crash the list.
    static func replaceMore(_ nodes: [Comment], _ moreNode: Comment, _ flat: [Comment]) -> [Comment] {
        var shown = Set(flatten(nodes, []).map(\.fullname))
        shown.remove(moreNode.fullname)
        var seen = Set<String>()
        let fresh = flat.filter { !shown.contains($0.fullname) && seen.insert($0.fullname).inserted }
        let byParent = Dictionary(grouping: fresh, by: \.parentId)
        func attach(_ c: Comment, _ depth: Int) -> Comment {
            c.with {
                $0.depth = depth
                $0.replies = (byParent[c.fullname] ?? []).map { attach($0, depth + 1) }
            }
        }
        let roots = (byParent[moreNode.parentId] ?? []).map { attach($0, moreNode.depth) }

        func replace(_ list: [Comment]) -> [Comment] {
            var out: [Comment] = []
            out.reserveCapacity(list.count + roots.count)
            for n in list {
                if n.isMore, n.fullname == moreNode.fullname {
                    out += roots
                } else if !n.replies.isEmpty {
                    out.append(n.with { $0.replies = replace(n.replies) })
                } else {
                    out.append(n)
                }
            }
            return out
        }
        return replace(nodes)
    }

    /// "Hide usernames" on a share image: "Commenter 1, 2…", consistent within the image.
    static func shareNames(_ chain: [Comment], hide: Bool) -> [String] {
        var names = OrderedMap<String>()
        return chain.map { c in
            guard hide else { return "u/\(c.author)" }
            if let n = names[c.author] { return n }
            let n = "Commenter \(names.count + 1)"
            names[c.author] = n
            return n
        }
    }
}
