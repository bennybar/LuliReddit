package com.bennybar.luli_for_reddit.feature.foryou

import com.bennybar.luli_for_reddit.core.AppJson
import com.bennybar.luli_for_reddit.model.Post
import com.bennybar.luli_for_reddit.model.SubredditIconMap
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException
import java.util.Collections

/** Reddit Home's first paint: subreddit icons remembered, and full posts asked for early. No network. */
class HomeLoadingTest {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    @After fun tearDown() = scope.cancel()

    private fun post(id: String): Post = Post.fromData(AppJson.parseToJsonElement("""{"id":"$id","name":"t3_$id","title":"T"}"""))

    @Test
    fun `an icon is remembered by name in any case, and a post's wins over the subscription list's`() {
        val m = SubredditIconMap()
        assertTrue(m.remember("Pics", "https://a/1.png"))
        assertEquals("https://a/1.png", m.icon("pics"))
        assertFalse("the same URL changes nothing", m.remember("pics", "https://a/1.png"))
        assertFalse("the subscription list doesn't replace a post's", m.remember("pics", "https://a/2.png", overwrite = false))
        assertTrue(m.remember("pics", "https://a/2.png"))
        assertEquals("https://a/2.png", m.icon("PICS"))
        assertFalse(m.remember("pics", null))
        assertFalse(m.remember("pics", ""))
        assertFalse(m.remember("", "https://a/3.png"))
    }

    @Test
    fun `icons are stored and loaded in order`() {
        val m = SubredditIconMap()
        m.remember("a", "https://x/a.png")
        m.remember("b", "https://x/b.png?width=64&s=1")
        m.remember("a", "https://x/a2.png") // changed: now the newest
        assertEquals(listOf("b\thttps://x/b.png?width=64&s=1", "a\thttps://x/a2.png"), m.entries)
        assertEquals(m.entries, SubredditIconMap(m.entries).entries)
        assertEquals("https://x/c.png", SubredditIconMap(listOf("broken", "c\thttps://x/c.png")).icon("c"))
    }

    @Test
    fun `past the cap the oldest go, down to 90 percent`() {
        val m = SubredditIconMap()
        for (i in 0..SubredditIconMap.CAP) m.remember("s$i", "https://x/$i.png")
        assertEquals(SubredditIconMap.CAP - SubredditIconMap.CAP / 10, m.size)
        assertNull(m.icon("s0"))
        assertEquals("https://x/${SubredditIconMap.CAP}.png", m.icon("s${SubredditIconMap.CAP}"))
    }

    @Test
    fun `the page's Reddit icon loses its query like the API's`() {
        assertEquals(
            "https://styles.redditmedia.com/t5_1/styles/communityIcon_x.png",
            PagePost.apiStyleIcon("https://styles.redditmedia.com/t5_1/styles/communityIcon_x.png?width=48&s=abc"),
        )
        assertEquals("https://b.thumbs.redditmedia.com/i.png?x=1", PagePost.apiStyleIcon("https://b.thumbs.redditmedia.com/i.png?x=1"))
    }

    @Test
    fun `full posts all in within the deadline`() = runBlocking {
        val batches = Collections.synchronizedList(ArrayList<List<String>>())
        val early = EarlyFullPosts(scope) { ids ->
            batches.add(ids)
            delay(30)
            ids.filter { it != "t3_gone" }.map { post(it.removePrefix("t3_")) }
        }
        early.add(listOf("t3_a", "t3_b"))
        early.add(listOf("t3_c", "t3_a")) // a: already asked
        early.add(listOf("t3_gone"))
        val got = early.wait(listOf("t3_a", "t3_b", "t3_c", "t3_gone"), 2_000)
        assertTrue(got.complete)
        assertEquals("one the API leaves out is just absent", setOf("t3_a", "t3_b", "t3_c"), got.posts.keys)
        assertEquals("each new id asked for once, at once while there's room", setOf(listOf("t3_a", "t3_b"), listOf("t3_c"), listOf("t3_gone")), batches.toSet())
    }

    @Test
    fun `a big batch goes out in parallel chunks`() = runBlocking {
        // The page shows ~25 posts at once: one request for all of them was too slow.
        val batches = Collections.synchronizedList(ArrayList<List<String>>())
        val early = EarlyFullPosts(scope) { ids ->
            batches.add(ids)
            delay(100)
            ids.map { post(it.removePrefix("t3_")) }
        }
        val ids = (1..30).map { "t3_p$it" }
        early.add(ids)
        delay(40)
        assertEquals("three at once, nine each", listOf(9, 9, 9), batches.map { it.size }.sorted())
        val got = early.wait(ids, 2_000)
        assertTrue(got.complete)
        assertEquals(30, got.posts.size)
        assertEquals("the rest once one is back", listOf(3, 9, 9, 9), batches.map { it.size }.sorted())
    }

    @Test
    fun `too slow or a failure is incomplete`() = runBlocking {
        val slow = EarlyFullPosts(scope) { ids ->
            delay(400)
            ids.map { post(it.removePrefix("t3_")) }
        }
        val late = slow.wait(listOf("t3_a"), 50)
        assertFalse(late.complete)
        assertTrue(late.posts.isEmpty())
        val failing = EarlyFullPosts(scope) { throw IOException("offline") }
        assertFalse(failing.wait(listOf("t3_a"), 1_000).complete)
    }

    @Test
    fun `a cancelled one is incomplete`() = runBlocking {
        val early = EarlyFullPosts(scope) { ids -> ids.map { post(it.removePrefix("t3_")) } }
        early.cancel()
        assertFalse(early.wait(listOf("t3_a"), 200).complete)
    }

    @Test
    fun `what's in by the deadline comes back when the rest is late`() = runBlocking {
        // Reddit's page shows its first few posts well before the rest: those are in.
        val early = EarlyFullPosts(scope) { ids ->
            if ("t3_late" in ids) delay(5_000)
            ids.map { post(it.removePrefix("t3_")) }
        }
        early.add(listOf("t3_a"))
        delay(100)
        val got = early.wait(listOf("t3_a", "t3_late"), 100)
        assertFalse(got.complete)
        assertEquals(setOf("t3_a"), got.posts.keys)
    }
}
