package com.bennybar.luli_for_reddit.feature.foryou

import com.bennybar.luli_for_reddit.model.Post
import com.bennybar.luli_for_reddit.model.PostType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneOffset
import java.time.ZonedDateTime

/** Port of the Flutter build's test/for_you_ranker_test.dart. */
class ForYouRankerTest {
    private val now = ZonedDateTime.of(2026, 10, 8, 12, 0, 0, 0, ZoneOffset.UTC).toInstant().toEpochMilli()
    private var n = 0

    private fun p(sub: String, title: String, score: Int = 500, hoursOld: Double = 3.0, url: String? = null, ratio: Double = 0.9): Post {
        val id = "p${n++}"
        // created_utc is whole seconds, as Reddit sends it.
        val created = (now - Math.round(hoursOld * 60) * 60_000L) / 1000 * 1000
        return Post(
            id = id,
            fullname = "t3_$id",
            title = title,
            subreddit = sub,
            subredditPrefixed = "r/$sub",
            author = "a",
            score = score,
            numComments = 0,
            upvoteRatio = ratio,
            createdUtc = created,
            permalink = "/r/$sub/comments/$id/",
            url = url ?: "https://www.reddit.com/r/$sub/comments/$id/",
            domain = "",
            type = if (url == null) PostType.SELF else PostType.LINK,
            isSelf = url == null,
        )
    }

    private fun c(ps: List<Post>, src: String = "best") = ps.map { Candidate(it, src) }

    @Test
    fun `B5 - a strongly disliked topic never flips the ordering`() {
        val fav = p("formula1", "Election chaos in the paddock election votes", hoursOld = 72.0)
        val disc = p("random", "Some unrelated discovery post", hoursOld = 72.0)
        val r = rankForYou(
            c(listOf(fav, disc)),
            RankInputs(
                favourites = setOf("formula1"),
                subscribed = setOf("formula1"),
                keywordScore = { t -> if (t.contains("Election")) -6.0 else 0.0 },
                now = now,
            ),
        )
        assertEquals("favourite × 4 must still beat discovery × 0.4", fav.id, r.ranked.first().id)
    }

    @Test
    fun `B5 - an opened post ranks below an unopened twin`() {
        val opened = p("a", "Twin post one")
        val fresh = p("a", "Twin post two")
        val r = rankForYou(
            c(listOf(opened, fresh)),
            RankInputs(
                subscribed = setOf("a"),
                keywordScore = { -6.0 },
                openedAt = mapOf(opened.id to now - 3600 * 1000L),
                now = now,
            ),
        )
        assertEquals(fresh.id, r.ranked.first().id)
    }

    @Test
    fun `B1 - negative interest and less-from actually demote`() {
        // Distinct titles, or the same-story rule would merge them.
        val words = listOf("alpha", "bravo", "charlie", "delta", "echo", "foxtrot")
        val news = words.map { p("news", "Report $it") }
        val pics = words.map { p("pics", "Photo $it") }
        fun newsInTop6(i: RankInputs) = rankForYou(c(news + pics), i).ranked.take(6).count { it.subreddit == "news" }
        val subs = setOf("news", "pics")
        val neutral = newsInTop6(RankInputs(subscribed = subs, now = now))
        val learnedLess = newsInTop6(RankInputs(subscribed = subs, interest = mapOf("news" to -8.0), now = now))
        val askedLess = newsInTop6(RankInputs(subscribed = subs, explicit = ExplicitPrefs(subs = mapOf("news" to -1)), now = now))
        assertTrue(learnedLess < neutral)
        assertTrue(askedLess < neutral)
    }

    @Test
    fun `same link in two places is kept once`() {
        val a = p("tech", "Big article", url = "https://www.example.com/x?utm_source=r")
        val b = p("news", "Big article again", url = "https://example.com/x")
        val r = rankForYou(c(listOf(a, b)), RankInputs(subscribed = setOf("tech", "news"), now = now))
        assertEquals(1, r.ranked.size)
    }

    @Test
    fun `same story - second copy spaced out, third dropped`() {
        val story = listOf("a", "b", "c").map { p(it, "Starship launch succeeds orbital flight test today") }
        val filler = (0 until 30).map { p("f$it", "Filler post about thing$it") }
        val r = rankForYou(
            c(story + filler),
            RankInputs(subscribed = setOf("a", "b", "c") + (0 until 30).map { "f$it" }, now = now),
        )
        val pos = r.ranked.indices.filter { r.ranked[it].title.startsWith("Starship") }
        assertEquals(2, pos.size)
        assertTrue(pos[1] - pos[0] >= 15)
    }

    @Test
    fun `diversity - no long runs from one subreddit, overflow carries over`() {
        // One subreddit with the strongest posts, and plenty of alternatives.
        val big = (0 until 20).map { p("big", "Big item $it", score = 5000 + it * 100) }
        val small = (0 until 20).map { p("s$it", "Small item $it", score = 50) }
        val r = rankForYou(
            c(big + small),
            RankInputs(subscribed = setOf("big") + (0 until 20).map { "s$it" }, now = now),
            pageSize = 20,
        )
        var run = 1
        var longest = 1
        for (i in 1 until r.ranked.size) {
            run = if (r.ranked[i].subreddit == r.ranked[i - 1].subreddit) run + 1 else 1
            if (run > longest) longest = run
        }
        assertTrue(longest <= 2)
        assertTrue(r.leftovers.isNotEmpty())
    }

    @Test
    fun `explanations come from what drove the score`() {
        val post = p("formula1", "Verstappen wins again")
        val r = rankForYou(
            c(listOf(post)),
            RankInputs(subscribed = setOf("formula1"), explicit = ExplicitPrefs(topics = mapOf("verstappen" to 1)), now = now),
        )
        assertTrue(r.ranked.single().feedReason!!.contains("verstappen"))
        assertTrue(r.meta[post.id]!!.why.isNotEmpty())
    }

    @Test
    fun `tokenizer - Hebrew, acronyms, accents`() {
        assertTrue(titleKeywords("הבחירות לכנסת בשבוע הבא").contains("בחירות"))
        assertTrue(titleKeywords("F1 and NBA news on PS5").containsAll(listOf("f1", "nba", "ps5")))
        assertTrue(titleKeywords("New Pokémon game announced").contains("pokémon"))
        assertFalse(titleKeywords("this is just the help").contains("this"))
    }
}
