package com.bennybar.luli_for_reddit.feature.inbox

import com.bennybar.luli_for_reddit.model.InboxItem
import com.bennybar.luli_for_reddit.model.InboxKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneId
import java.time.ZonedDateTime

/** The Inbox redesign's grouping (#315): rows by day, messages by person, one chat per person. */
class InboxGroupingTest {
    private val zone = ZoneId.of("Asia/Jerusalem")
    private fun at(day: Int, hour: Int) = ZonedDateTime.of(2026, 11, day, hour, 0, 0, 0, zone).toInstant().toEpochMilli()
    private val now = at(28, 12)

    private fun msg(id: String, author: String, at: Long, dest: String? = null, new: Boolean = false, sub: String? = null, replies: List<InboxItem> = emptyList(), subject: String = "Hi") =
        InboxItem("t4_$id", InboxKind.MESSAGE, author, subject, "body $id", at, isNew = new, dest = dest, subreddit = sub, replies = replies, authorFullname = "t2_$author")

    private fun reply(id: String, at: Long) = InboxItem("t1_$id", InboxKind.COMMENT_REPLY, "someone", "", "r", at, subreddit = "pics")

    @Test
    fun rowsSplitIntoTodayAndEarlier() {
        val items = listOf(reply("a", at(28, 9)), reply("b", at(28, 0)), reply("c", at(27, 23)), reply("d", at(20, 10)))
        val days = byDay(items, now, zone)
        assertEquals(listOf(InboxDay.TODAY, InboxDay.EARLIER), days.map { it.first })
        assertEquals(listOf("t1_a", "t1_b"), days[0].second.map { it.fullname })
        assertEquals(listOf("t1_c", "t1_d"), days[1].second.map { it.fullname })
    }

    @Test
    fun onlyEarlierWhenNothingToday() {
        val days = byDay(listOf(reply("c", at(27, 23))), now, zone)
        assertEquals(listOf(InboxDay.EARLIER), days.map { it.first })
    }

    @Test
    fun threadsGroupByTheOtherPerson() {
        val a1 = msg("1", "Alice", at(20, 10), dest = "me", replies = listOf(msg("2", "me", at(20, 11), dest = "Alice")))
        // One you started: grouped by where it went.
        val a2 = msg("3", "me", at(27, 9), dest = "alice", replies = listOf(msg("4", "alice", at(28, 8), dest = "me", new = true)))
        val b = msg("5", "Bob", at(26, 9), dest = "me", new = true)
        val mods = msg("6", "SomeMod", at(25, 9), dest = "me", sub = "Android")
        val convs = conversations(listOf(a1, b, a2, mods), "Me")
        assertEquals(listOf("alice", "bob", "r/android"), convs.map { it.with.key })
        val alice = convs[0]
        assertEquals(listOf("t4_1", "t4_3"), alice.threads.map { it.fullname }) // oldest activity first
        assertEquals("t4_4", alice.latest.fullname)
        assertEquals(1, alice.unread)
        assertEquals("t2_Alice", alice.accountId)
        assertTrue(convs[2].with.isSubreddit)
    }

    @Test
    fun aMessageToASubredditsModsIsTheSubreddit() {
        val c = correspondent(msg("1", "me", at(27, 9), dest = "#Android"), "me")
        assertEquals(Correspondent("r/android", "Android", true), c)
    }

    @Test
    fun yourOwnUnreadDoesNotCount() {
        val t = msg("1", "bob", at(27, 9), dest = "me", replies = listOf(msg("2", "me", at(27, 10), new = true)))
        assertEquals(0, conversations(listOf(t), "me").single().unread)
        assertEquals(emptyList<String>(), unreadIn(listOf(t), "me"))
    }

    @Test
    fun chatIsOldestFirstWithThreadStartsAndANewLine() {
        val old = msg("1", "bob", at(10, 9), dest = "me", replies = listOf(msg("2", "me", at(10, 10), dest = "bob")), subject = "First")
        val recent = msg("3", "bob", at(28, 9), dest = "me", new = true, subject = "Second", replies = listOf(msg("4", "bob", at(28, 10), new = true)))
        val entries = chatEntries(listOf(old, recent), "me", dividers = true)
        assertEquals(
            listOf("start_t4_1", "t4_1", "t4_2", "start_t4_3", "new", "t4_3", "t4_4"),
            entries.map { it.key },
        )
        assertEquals(2, (entries[4] as ChatEntry.NewFrom).count)
        assertEquals(listOf("t4_3", "t4_4"), unreadIn(listOf(old, recent), "me"))
    }

    @Test
    fun aSingleThreadHasNoDividers() {
        val t = msg("1", "bob", at(27, 9), dest = "me", replies = listOf(msg("2", "me", at(27, 10))))
        assertEquals(listOf("t4_1", "t4_2"), chatEntries(listOf(t), "me", dividers = false).map { it.key })
    }
}
