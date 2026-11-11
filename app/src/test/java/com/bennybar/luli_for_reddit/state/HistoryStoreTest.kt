package com.bennybar.luli_for_reddit.state

import android.content.SharedPreferences
import com.bennybar.luli_for_reddit.core.AppJson
import com.bennybar.luli_for_reddit.core.storage.Prefs
import com.bennybar.luli_for_reddit.model.Comment
import com.bennybar.luli_for_reddit.model.Post
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.*
import org.junit.Test
import java.lang.reflect.Proxy
import sun.misc.Unsafe

class HistoryStoreTest {
    // In-memory Android interface double; the production Prefs and store execute unchanged.
    private fun prefs(): Prefs {
        val data = mutableMapOf<String, Any?>()
        val editor = Proxy.newProxyInstance(javaClass.classLoader, arrayOf(SharedPreferences.Editor::class.java)) { proxy, method, args ->
            when {
                method.name.startsWith("put") -> { data[args!![0] as String] = args[1]; proxy }
                method.name == "remove" -> { data.remove(args!![0]); proxy }
                method.name == "clear" -> { data.clear(); proxy }
                method.name == "commit" -> true
                else -> null
            }
        }
        val sp = Proxy.newProxyInstance(javaClass.classLoader, arrayOf(SharedPreferences::class.java)) { _, method, args ->
            when (method.name) {
                "contains" -> data.containsKey(args!![0])
                "getAll" -> data.toMap()
                "edit" -> editor
                else -> if (method.name.startsWith("get")) data[args!![0]] ?: args[1] else null
            }
        }
        val field = Unsafe::class.java.getDeclaredField("theUnsafe").apply { isAccessible = true }
        val p = (field.get(null) as Unsafe).allocateInstance(Prefs::class.java) as Prefs
        Prefs::class.java.getDeclaredField("sp").apply { isAccessible = true }.set(p, sp)
        Prefs::class.java.getDeclaredField("_changes").apply { isAccessible = true }.set(p, MutableSharedFlow<String>(extraBufferCapacity = 64))
        return p
    }

    private fun post(id: String, nsfw: Boolean = false) = Post.fromData(
        AppJson.parseToJsonElement("""{"id":"$id","name":"t3_$id","title":"T","subreddit":"pics","author":"a","permalink":"/p","over_18":$nsfw}"""),
    )

    // `nsfw` is optional both ways: older entries (and older app versions, which ignore
    // it) read as shown; it's written only when set, the same shape as the Swift app.
    @Test fun nsfwFlagRoundTripsAndOldEntriesReadAsShown() {
        val p = prefs()
        p.setStringList("history_bob", listOf("""{"id":"old","sub":"pics","title":"T","permalink":"/p","ts":1}"""))
        val history = HistoryStore(p)
        history.onUserChanged("bob")
        assertFalse(history.state.value[0].nsfw)
        history.markViewed(post("n", nsfw = true))
        history.markViewed(post("s"))
        val rows = p.getStringList("history_bob")!!.map { AppJson.parseToJsonElement(it).jsonObject }
        assertEquals(listOf("s", "n", "old"), rows.map { it["id"].toString().trim('"') })
        assertFalse("SFW entries keep the old shape", "nsfw" in rows[0])
        assertEquals("true", rows[1]["nsfw"].toString())
        assertFalse("nsfw" in rows[2])
        val again = HistoryStore(p)
        again.onUserChanged("bob")
        assertEquals(listOf(false, true, false), again.state.value.map { it.nsfw })
    }

    @Test fun savedCommentReadsItsPostsNsfwFlag() {
        val c = Comment.fromChild(AppJson.parseToJsonElement("""{"kind":"t1","data":{"id":"x","body":"b","over_18":true}}"""), 0)
        assertTrue(c.over18)
    }

    // #148: History shows the newest 500, but posts read longer ago still count
    // as read, across restarts; removing or clearing forgets them too.
    @Test fun readIdsOutliveTheHistoryCap() {
        val p = prefs()
        p.setStringList("history_bob", listOf("""{"id":"old","sub":"pics","title":"T","permalink":"/p","ts":1}"""))
        val h = HistoryStore(p)
        h.onUserChanged("bob")
        assertTrue("seeded from history", h.contains("old"))
        for (i in 0 until 700) h.markViewed(post("p$i"))
        assertEquals(500, h.state.value.size)
        assertTrue(h.contains("p0"))
        assertTrue(h.contains("old"))
        val again = HistoryStore(p)
        again.onUserChanged("bob")
        assertTrue(again.contains("p0"))
        assertTrue(again.contains("p699"))
        again.removeViewed("p0")
        assertFalse(again.contains("p0"))
        again.clearOlderThan(60_000)
        assertFalse("legacy entries count as old", again.contains("old"))
        assertTrue(again.contains("p1"))
        again.clear()
        assertFalse(again.contains("p1"))
        val other = HistoryStore(p)
        other.onUserChanged("alice")
        assertTrue(other.ids.value.isEmpty())
    }

    // #154: Undo puts a removed entry back where it was, read again.
    @Test fun restorePutsAnEntryBackInPlace() {
        val h = HistoryStore(prefs())
        h.onUserChanged("bob")
        for (id in listOf("a", "b", "c")) { h.markViewed(post(id)); Thread.sleep(2) }
        val b = h.state.value.first { it.id == "b" }
        h.removeViewed("b")
        assertFalse(h.contains("b"))
        h.restore(b)
        h.restore(b)
        assertEquals(listOf("c", "b", "a"), h.state.value.map { it.id })
        assertTrue(h.contains("b"))
    }
}
