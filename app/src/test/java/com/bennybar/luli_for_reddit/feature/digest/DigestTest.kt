package com.bennybar.luli_for_reddit.feature.digest

import com.bennybar.luli_for_reddit.model.Post
import com.bennybar.luli_for_reddit.model.PostType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DigestTest {
    private val now = 1_800_000_000_000L
    private val hour = 3_600_000L
    private var n = 0

    private fun p(sub: String, score: Int, comments: Int = 10, title: String? = null, hoursOld: Int = 3, url: String? = null, stickied: Boolean = false): Post {
        val id = "p${n++}"
        return Post(
            id = id, fullname = "t3_$id", title = title ?: "Post $id about something unique $id", subreddit = sub,
            subredditPrefixed = "r/$sub", author = "a", score = score, numComments = comments, upvoteRatio = 0.9,
            createdUtc = now - hoursOld * hour, permalink = "/r/$sub/comments/$id/",
            url = url ?: "https://www.reddit.com/r/$sub/comments/$id/", domain = "",
            type = if (url == null) PostType.SELF else PostType.LINK, isSelf = url == null, stickied = stickied,
        )
    }

    /** A community's ordinary day: [count] posts around [typical] points. */
    private fun ordinary(sub: String, typical: Int, count: Int = 6) = List(count) { p(sub, typical) }

    private fun build(candidates: List<Post>, size: DigestSize = DigestSize.STANDARD, read: Set<String> = emptySet(), prev: DigestDay? = null, at: Long = now) =
        mergeDigest(prev, "2027-01-15", candidates, read, size, at)

    @Test
    fun `notability is relative to the post's own community`() {
        // A small community's big day beats a big community's ordinary post.
        val smallHit = p("small", 300)
        val bigUsual = p("big", 9000)
        val r = build(ordinary("small", 30) + smallHit + ordinary("big", 9000) + bigUsual)
        val ids = r.items.map { it.post.id }
        assertTrue(smallHit.id in ids)
        assertEquals(smallHit.id, ids.first())
    }

    @Test
    fun `a quiet day gives a short digest, never padded`() {
        // Nothing stands out: only each community's top post counts.
        val r = build(ordinary("a", 100) + ordinary("b", 50), size = DigestSize.STANDARD)
        assertEquals(2, r.items.size)
        assertEquals(setOf("a", "b"), r.items.map { it.post.subreddit }.toSet())
    }

    @Test
    fun `sizes cap the total and each community`() {
        val hits = List(10) { p("a", 1000 + it) } + ordinary("a", 10, 20)
        val brief = build(hits, size = DigestSize.BRIEF)
        assertEquals(2, brief.items.size) // at most 2 from a community
        val standard = build(hits, size = DigestSize.STANDARD)
        assertEquals(3, standard.items.size)
        val many = (0 until 10).flatMap { c -> listOf(p("c$c", 5000), p("c$c", 4000)) + ordinary("c$c", 10) }
        assertEquals(5, build(many, size = DigestSize.BRIEF).items.size)
        assertEquals(12, build(many, size = DigestSize.STANDARD).items.size)
        assertEquals(20, build(many, size = DigestSize.EVERYTHING).items.size)
    }

    @Test
    fun `old, stickied and already read posts are left out`() {
        val old = p("a", 9000, hoursOld = 30)
        val pinned = p("a", 9000, stickied = true)
        val read = p("a", 8000)
        val fresh = p("a", 7000)
        val r = build(listOf(old, pinned, read, fresh) + ordinary("a", 10), read = setOf(read.id))
        val ids = r.items.map { it.post.id }
        assertFalse(old.id in ids)
        assertFalse(pinned.id in ids)
        assertFalse(read.id in ids)
        assertTrue(fresh.id in ids)
    }

    @Test
    fun `one copy of a link or a story`() {
        val a = p("a", 5000, url = "https://example.com/story?utm_source=x")
        val b = p("b", 4000, url = "https://www.example.com/story")
        val c = p("c", 5000, title = "Volcano erupts near Reykjavik airport tonight")
        val d = p("d", 4000, title = "Reykjavik airport closed as volcano erupts tonight")
        val r = build(listOf(a, b, c, d) + ordinary("a", 10) + ordinary("b", 10) + ordinary("c", 10) + ordinary("d", 10), size = DigestSize.EVERYTHING)
        val ids = r.items.map { it.post.id }
        assertTrue(a.id in ids)
        assertFalse(b.id in ids)
        assertTrue(c.id in ids)
        assertFalse(d.id in ids)
    }

    @Test
    fun `a refresh keeps what's shown and only judges new posts`() {
        val hit = p("a", 5000)
        val base = ordinary("a", 10)
        val first = build(listOf(hit) + base)
        assertEquals(listOf(hit.id), first.items.map { it.post.id })
        // Later the same posts plus a new hit; the first one's points changed.
        val later = now + 2 * hour
        val newHit = p("a", 6000)
        val second = build(listOf(hit.copy(score = 5500), newHit) + base, prev = first, at = later)
        assertEquals(listOf(hit.id, newHit.id), second.items.map { it.post.id })
        assertEquals(5500, second.items[0].post.score) // numbers refreshed
        assertEquals(first.items[0].why, second.items[0].why) // verdict kept
        assertEquals(later, second.judged[newHit.id]!!.at)
        assertEquals(first.judged[base[0].id]!!.at, second.judged[base[0].id]!!.at) // not judged again
        assertTrue(second.isNew(second.items[1]))
        assertFalse(second.isNew(second.items[0]))
    }

    @Test
    fun `nothing shown is removed, even when it leaves Reddit's top`() {
        val hit = p("a", 5000)
        val first = build(listOf(hit) + ordinary("a", 10))
        val second = build(ordinary("a", 10) + p("a", 20), prev = first, at = now + hour)
        assertTrue(hit.id in second.items.map { it.post.id })
    }

    @Test
    fun `a post that doubled gets one second look`() {
        val base = ordinary("a", 100)
        val top = p("a", 3000)
        val grower = p("a", 150)
        val first = build(base + top + grower)
        assertFalse(grower.id in first.items.map { it.post.id })
        val second = build(base + top + grower.copy(score = 900), prev = first, at = now + hour)
        assertTrue(grower.id in second.items.map { it.post.id })
        assertTrue(second.judged[grower.id]!!.secondLook)
        // Doubled but still not notable: not picked on its second look, and never judged again.
        val bBase = ordinary("b", 10)
        val bTop = p("b", 900)
        val quiet = p("b", 5, comments = 1)
        val b1 = build(bBase + bTop + quiet)
        val b2 = build(bBase + bTop + quiet.copy(score = 12), prev = b1, at = now + hour)
        assertTrue(b2.judged[quiet.id]!!.secondLook)
        assertFalse(quiet.id in b2.items.map { it.post.id })
        val b3 = build(bBase + bTop + quiet.copy(score = 80), prev = b2, at = now + 2 * hour)
        assertEquals(b2.judged[quiet.id], b3.judged[quiet.id])
        assertFalse(quiet.id in b3.items.map { it.post.id })
    }

    @Test
    fun `a new day starts a new digest`() {
        val first = build(listOf(p("a", 5000)) + ordinary("a", 10))
        val next = mergeDigest(first, "2027-01-16", listOf(p("a", 4000)) + ordinary("a", 10), emptySet(), DigestSize.STANDARD, now + 20 * hour)
        assertEquals("2027-01-16", next.day)
        assertEquals(1, next.items.size)
        assertFalse(next.isNew(next.items[0]))
    }

    @Test
    fun `later refreshes add up to the community cap, beyond the first build's size`() {
        val many = (0 until 6).flatMap { c -> listOf(p("c$c", 5000)) + ordinary("c$c", 10) }
        val first = build(many, size = DigestSize.BRIEF)
        assertEquals(5, first.items.size)
        val second = build(many + p("c0", 6000), prev = first, size = DigestSize.BRIEF, at = now + hour)
        assertEquals(6, second.items.size)
    }

    @Test
    fun `why lines say how a post stands out`() {
        val hit = p("pics", 3000, comments = 240)
        val r = build(listOf(hit) + ordinary("pics", 100))
        assertTrue(r.items[0].why, r.items[0].why.startsWith("Top post today in r/pics"))
        assertTrue(r.items[0].why, r.items[0].why.contains("240 comments"))
    }

    @Test
    fun `items group by community in the order they first appear`() {
        val r = build(listOf(p("a", 5000), p("b", 9000), p("a", 4000)) + ordinary("a", 10) + ordinary("b", 10))
        assertEquals(listOf("b", "a"), groupByCommunity(r.items).map { it.first })
    }
}
