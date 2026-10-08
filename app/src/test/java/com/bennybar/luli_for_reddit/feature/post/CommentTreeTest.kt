package com.bennybar.luli_for_reddit.feature.post

import com.bennybar.luli_for_reddit.core.AppJson
import com.bennybar.luli_for_reddit.model.Comment
import com.bennybar.luli_for_reddit.model.Post
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

private fun c(id: String, author: String, body: String, parent: String, depth: Int = 0, replies: List<Comment> = emptyList()) =
    Comment.fromChild(
        AppJson.parseToJsonElement(
            """{"kind":"t1","data":{"id":"$id","name":"t1_$id","author":"$author","body":"$body","score":42,
               "parent_id":"$parent","created_utc":1700000000}}""",
        ),
        depth,
    ).copy(replies = replies)

private fun more(id: String, parent: String, depth: Int, children: List<String>) = Comment(
    id = id, fullname = "t1_$id", parentId = parent, author = "", body = "", score = 0, createdUtc = 0,
    depth = depth, isMore = true, moreCount = children.size, moreChildren = children,
)

/** Port of test/share_comment_image_test.dart (the testable logic) plus the tree operations. */
class CommentTreeTest {
    private val chain = listOf(
        c("a", "alice", "Top comment", "t3_p"),
        c("b", "bob", "A reply", "t1_a", 1),
        c("c", "alice", "Back to you", "t1_b", 2),
    )

    @Test
    fun `share image names, hidden consistently`() {
        assertEquals(listOf("u/alice", "u/bob", "u/alice"), CommentTree.shareNames(chain, hide = false))
        // Same author, same placeholder.
        assertEquals(listOf("Commenter 1", "Commenter 2", "Commenter 1"), CommentTree.shareNames(chain, hide = true))
    }

    @Test
    fun `chain runs from the top-level ancestor to the comment`() {
        val flat = listOf(c("x", "x", "other", "t3_p")) + chain
        assertEquals(listOf("a", "b", "c"), CommentTree.chainTo(flat, chain[2]).map { it.id })
        assertEquals(listOf("a"), CommentTree.chainTo(flat, chain[0]).map { it.id })
    }

    @Test
    fun `flatten skips collapsed and more subtrees`() {
        val tree = listOf(c("a", "u", "", "t3_p", 0, listOf(c("b", "u", "", "t1_a", 1, listOf(c("c", "u", "", "t1_b", 2))))))
        assertEquals(listOf("a", "b", "c"), CommentTree.flatten(tree, emptySet()).map { it.id })
        assertEquals(listOf("a", "b"), CommentTree.flatten(tree, setOf("b")).map { it.id })
    }

    @Test
    fun `insert, update and remove keep the tree consistent`() {
        val tree = listOf(c("a", "u", "", "t3_p", 0, listOf(c("b", "u", "", "t1_a", 1))), c("z", "u", "", "t3_p"))
        val inserted = CommentTree.insertReply(tree, "t1_b", c("n", "me", "new", "t1_b"))
        assertEquals(2, inserted[0].replies[0].replies[0].depth)
        // Untouched subtrees keep their identity.
        val updated = CommentTree.update(tree, "t1_b") { it.copy(score = 1) }
        assertEquals(1, updated[0].replies[0].score)
        assertSame(tree[1], updated[1])
        // A deleted comment with replies stays as "[deleted]".
        val removed = CommentTree.remove(tree, "t1_a")
        assertEquals("[deleted]", removed[0].author)
        assertEquals(listOf("z"), CommentTree.remove(tree, "t1_a").drop(1).map { it.id })
        assertEquals(listOf("a"), CommentTree.remove(tree, "t1_z").map { it.id })
    }

    @Test
    fun `load more re-nests the flat result in place of the stub`() {
        val stub = more("m", "t1_a", 1, listOf("x", "y"))
        val tree = listOf(c("a", "u", "", "t3_p", 0, listOf(c("b", "u", "", "t1_a", 1), stub)))
        val fetched = listOf(c("x", "u", "", "t1_a"), c("y", "u", "", "t1_x"))
        val out = CommentTree.replaceMore(tree, stub, fetched)
        val replies = out[0].replies
        assertEquals(listOf("b", "x"), replies.map { it.id })
        assertEquals(1, replies[1].depth)
        assertEquals("y", replies[1].replies.single().id)
        assertEquals(2, replies[1].replies.single().depth)
        assertTrue(CommentTree.flatten(out, emptySet()).none { it.isMore })
    }

    @Test
    fun `thread text ranks comments by score within the budget`() {
        val post = Post.fromData(
            AppJson.parseToJsonElement(
                """{"id":"p","title":"A big post","subreddit":"test","author":"op","url":"","is_self":true,
                   "selftext":"Body","score":10,"num_comments":2}""",
            ),
        )
        val low = c("l", "low", "meh", "t3_p").copy(score = 1)
        val high = c("h", "high", "x", "t3_p").copy(score = 99, body = "great\nline")
        val text = AiService.buildThreadText(post, listOf(low, high, more("m", "t3_p", 0, listOf("q"))), 100_000)
        assertTrue(text.startsWith("POST in r/test by u/op — score 10, 2 comments\nTITLE: A big post\nBODY: Body\n"))
        assertTrue(text.indexOf("[99] u/high: great line") < text.indexOf("[1] u/low: meh"))
        assertTrue(text.endsWith("(Included 2 of 2 comments, highest-scored first.)"))
        val tight = AiService.buildThreadText(post, listOf(low, high), 120)
        assertTrue(tight.endsWith("(Included 0 of 2 comments, highest-scored first.)"))
    }
}
