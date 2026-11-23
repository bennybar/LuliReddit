package com.bennybar.luli_for_reddit.feature.digest

import com.bennybar.luli_for_reddit.model.Post
import com.bennybar.luli_for_reddit.model.PostType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The Digest's AI step with canned replies (no real AI calls), and the screen's orders. */
class DigestAiTest {
    private val now = 1_800_000_000_000L
    private val hour = 3_600_000L
    private var n = 0

    private fun p(sub: String, score: Int, comments: Int = 10, hoursOld: Int = 3): Post {
        val id = "p${n++}"
        return Post(
            id = id, fullname = "t3_$id", title = "Post $id about something unique $id", subreddit = sub,
            subredditPrefixed = "r/$sub", author = "a", score = score, numComments = comments, upvoteRatio = 0.9,
            createdUtc = now - hoursOld * hour, permalink = "/r/$sub/comments/$id/",
            url = "https://www.reddit.com/r/$sub/comments/$id/", domain = "", type = PostType.SELF, isSelf = true,
        )
    }

    private val posts by lazy { listOf(p("a", 100), p("a", 50), p("b", 10)) }

    @Test
    fun `clean JSON`() {
        val r = parseDigestAi("""{"overview":"Big day.","items":[{"i":0,"importance":5,"why":"Huge."},{"i":2,"importance":1,"why":"Meh."}]}""", posts)!!
        assertEquals("Big day.", r.overview)
        assertEquals(AiVerdict(5, "Huge."), r.verdicts[posts[0].id])
        assertEquals(1, r.verdicts[posts[2].id]!!.importance)
        assertFalse(posts[1].id in r.verdicts)
    }

    @Test
    fun `fenced JSON with words around it`() {
        val r = parseDigestAi("Here you go:\n```json\n{\"items\":[{\"i\":1,\"importance\":3,\"why\":\"Ok.\"}]}\n```", posts)!!
        assertEquals(3, r.verdicts[posts[1].id]!!.importance)
        assertNull(r.overview)
    }

    @Test
    fun `garbage is a failure`() {
        assertNull(parseDigestAi("I can't help with that.", posts))
        assertNull(parseDigestAi("{not json", posts))
        assertNull(parseDigestAi("""{"overview":"x"}""", posts))
    }

    @Test
    fun `wrong indices are skipped, all wrong is a failure`() {
        val r = parseDigestAi("""{"items":[{"i":9,"importance":5,"why":"x"},{"i":0,"importance":9,"why":"y"}]}""", posts)!!
        assertEquals(1, r.verdicts.size)
        assertEquals(5, r.verdicts[posts[0].id]!!.importance) // clamped to 5
        assertNull(parseDigestAi("""{"items":[{"i":7,"importance":5,"why":"x"}]}""", posts))
    }

    @Test
    fun `the AI picks, most important first, with its why`() {
        val ordinary = List(6) { p("a", 10) }
        val big = p("a", 5000)
        val quiet = p("a", 12)
        val cands = ordinary + big + quiet
        val ai = DigestAi("Today…", mapOf(quiet.id to AiVerdict(5, "Quietly important."), big.id to AiVerdict(1, "Noise.")))
        val d = mergeDigest(null, "2027-01-15", cands, emptySet(), DigestSize.STANDARD, now, ai)
        assertEquals(listOf(quiet.id), d.items.map { it.post.id }) // the notable one rated 1 is out, unrated ones too
        assertEquals("Quietly important.", d.items[0].why)
        assertEquals(5, d.items[0].importance)
        assertEquals("Today…", d.overview)
        assertEquals(now, d.aiAt)
        assertFalse(d.judged[big.id]!!.picked)
    }

    @Test
    fun `a refresh sends only posts not judged yet, and keeps the overview`() {
        val first = mergeDigest(null, "2027-01-15", List(6) { p("a", 10) } + p("a", 5000), emptySet(), DigestSize.STANDARD, now, DigestAi("Morning.", emptyMap()))
        val cands = first.judged.keys.map { id -> p("a", 10).copy(id = id) }
        val fresh = p("a", 900)
        assertEquals(listOf(fresh.id), digestPending(first, "2027-01-15", cands + fresh, emptySet(), now + hour).map { it.id })
        assertTrue(digestPending(first, "2027-01-15", cands, emptySet(), now + hour).isEmpty())
        val second = mergeDigest(first, "2027-01-15", cands + fresh, emptySet(), DigestSize.STANDARD, now + hour, DigestAi("Evening.", mapOf(fresh.id to AiVerdict(3, "x"))))
        assertEquals("Morning.", second.overview)
    }

    @Test
    fun `posts read before they were judged aren't sent`() {
        val read = p("a", 900)
        val cands = List(6) { p("a", 10) } + read
        assertFalse(read.id in digestPending(null, "2027-01-15", cands, setOf(read.id), now).map { it.id })
    }

    @Test
    fun `a failed AI goes by the numbers and says so`() {
        val big = p("a", 5000)
        val d = mergeDigest(null, "2027-01-15", List(6) { p("a", 10) } + big, emptySet(), DigestSize.STANDARD, now, aiFailed = true)
        assertEquals(listOf(big.id), d.items.map { it.post.id })
        assertTrue(d.aiFailed)
    }

    @Test
    fun `orders`() {
        fun item(sub: String, score: Int, hoursOld: Int, notability: Double, importance: Int) =
            DigestItem(p(sub, score, hoursOld = hoursOld), "", notability, now, importance)
        val a1 = item("a", 100, 1, 5.0, 2)
        val a2 = item("a", 900, 9, 2.0, 4)
        val b1 = item("b", 500, 5, 9.0, 1)
        val all = listOf(a1, a2, b1)
        fun ids(o: DigestOrder) = orderDigest(all, o).flatMap { (_, l) -> l.map { it.post.id } }
        assertEquals(listOf(b1, a1, a2).map { it.post.id }, ids(DigestOrder.NOTABLE))
        assertEquals(listOf(a2, a1, b1).map { it.post.id }, ids(DigestOrder.UPVOTED))
        assertEquals(listOf(a1, a2, b1).map { it.post.id }, ids(DigestOrder.NEWEST))
        assertEquals(listOf(a2, a1, b1).map { it.post.id }, ids(DigestOrder.AI))
    }
}
