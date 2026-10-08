package com.bennybar.luli_for_reddit.feature.post

import com.bennybar.luli_for_reddit.model.Comment

/**
 * Pure comment-tree operations (no Android), shared by [CommentsViewModel]
 * and the unit tests.
 */
object CommentTree {
    /** Depth-first visible rows: a collapsed comment's replies (and a "more" node's) are skipped. */
    fun flatten(nodes: List<Comment>, collapsed: Set<String>): List<Comment> {
        val out = ArrayList<Comment>(nodes.size * 2)
        fun walk(c: Comment) {
            out.add(c)
            if (!c.isMore && c.id !in collapsed) c.replies.forEach(::walk)
        }
        nodes.forEach(::walk)
        return out
    }

    /**
     * [c] and its parents up to the top-level comment, top first — the
     * chain a "Share as image" card shows (at most 8). Visible rows include
     * every ancestor of a visible comment.
     */
    fun chainTo(flat: List<Comment>, c: Comment): List<Comment> {
        val byName = flat.associateBy { it.fullname }
        val chain = ArrayDeque<Comment>().apply { add(c) }
        var parent = byName[c.parentId]
        while (parent != null && chain.size < 8) {
            chain.addFirst(parent)
            parent = byName[parent.parentId]
        }
        return chain.toList()
    }

    /** Splices [reply] under [parentFullname] (newest first), at its parent's depth + 1. */
    fun insertReply(nodes: List<Comment>, parentFullname: String, reply: Comment): List<Comment> = nodes.map { n ->
        if (n.fullname == parentFullname) n.copy(replies = listOf(reply.copy(depth = n.depth + 1)) + n.replies)
        else if (n.replies.isEmpty()) n
        else n.copy(replies = insertReply(n.replies, parentFullname, reply))
    }

    /**
     * Applies [change] to one comment. Vote and save state live in the tree
     * rather than the row, which the list disposes as it scrolls off-screen —
     * so they survive scrolling away and back. Untouched subtrees keep their
     * identity (cheap, and rows don't recompose needlessly).
     */
    fun update(nodes: List<Comment>, fullname: String, change: (Comment) -> Comment): List<Comment> = nodes.map { n ->
        when {
            n.fullname == fullname -> change(n)
            n.replies.isEmpty() -> n
            else -> {
                val r = update(n.replies, fullname, change)
                if (r.zip(n.replies).all { (a, b) -> a === b }) n else n.copy(replies = r)
            }
        }
    }

    /**
     * After deleting a comment: drop it, or — if it has replies — keep the
     * replies under a "[deleted]" placeholder, as Reddit does.
     */
    fun remove(nodes: List<Comment>, fullname: String): List<Comment> = nodes.mapNotNull { n ->
        when {
            n.fullname != fullname -> if (n.replies.isEmpty()) n else n.copy(replies = remove(n.replies, fullname))
            n.replies.isNotEmpty() -> n.copy(author = "[deleted]", body = "[deleted]", media = emptyMap())
            else -> null
        }
    }

    /**
     * Re-nests a flat /api/morechildren result by parent_id and splices it in
     * place of [moreNode] (matched by fullname).
     */
    fun replaceMore(nodes: List<Comment>, moreNode: Comment, flat: List<Comment>): List<Comment> {
        val byParent = flat.groupBy { it.parentId }
        fun attach(c: Comment, depth: Int): Comment =
            c.copy(depth = depth, replies = (byParent[c.fullname] ?: emptyList()).map { attach(it, depth + 1) })
        val roots = (byParent[moreNode.parentId] ?: emptyList()).map { attach(it, moreNode.depth) }

        fun replace(list: List<Comment>): List<Comment> {
            val out = ArrayList<Comment>(list.size + roots.size)
            for (n in list) {
                when {
                    n.isMore && n.fullname == moreNode.fullname -> out.addAll(roots)
                    n.replies.isNotEmpty() -> out.add(n.copy(replies = replace(n.replies)))
                    else -> out.add(n)
                }
            }
            return out
        }
        return replace(nodes)
    }

    /** "Hide usernames" on a share image: "Commenter 1, 2…", consistent within the image. */
    fun shareNames(chain: List<Comment>, hide: Boolean): List<String> {
        val names = LinkedHashMap<String, String>()
        return chain.map { c ->
            if (hide) names.getOrPut(c.author) { "Commenter ${names.size + 1}" } else "u/${c.author}"
        }
    }
}
