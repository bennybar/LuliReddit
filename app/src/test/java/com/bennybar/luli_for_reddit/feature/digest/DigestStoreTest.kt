package com.bennybar.luli_for_reddit.feature.digest

import com.bennybar.luli_for_reddit.core.AppJson
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDateTime

/** The digest file (both apps read and write it: the iOS DigestStoreTests reads this same fixture). */
class DigestStoreTest {
    @Test
    fun `reads the shared fixture`() {
        val days = decodeDigestDays(AppJson.parseToJsonElement(DIGEST_FIXTURE))
        assertEquals(1, days.size)
        val d = days[0]
        assertEquals("2027-01-15", d.day)
        assertEquals(1000L, d.builtAt)
        assertEquals(2000L, d.refreshedAt)
        assertEquals(1500L, d.seenAt)
        assertEquals("Calm.", d.overview)
        assertTrue(d.aiFailed)
        assertEquals(2000L, d.aiAt)
        val item = d.items.single()
        assertEquals("abc", item.post.id)
        assertEquals("Hello", item.post.title)
        assertEquals(42, item.post.score)
        assertEquals("Why.", item.why)
        assertEquals(2.5, item.notability, 0.0)
        assertEquals(1000L, item.addedAt)
        assertEquals(4, item.importance)
        assertEquals(Judged(true, 2.5, 1000, false), d.judged["abc"])
        assertEquals(Judged(false, 1.1, 1000, true), d.judged["def"])
    }

    @Test
    fun `round trip`() {
        val raws = HashMap<String, kotlinx.serialization.json.JsonElement>()
        val days = decodeDigestDays(AppJson.parseToJsonElement(DIGEST_FIXTURE)) { id, r -> raws[id] = r }
        val again = decodeDigestDays(AppJson.parseToJsonElement(encodeDigestDays(days) { raws[it] }))
        assertEquals(days, again)
    }

    @Test
    fun `a post with no saved JSON is left out, not written broken`() {
        val days = decodeDigestDays(AppJson.parseToJsonElement(DIGEST_FIXTURE))
        val again = decodeDigestDays(AppJson.parseToJsonElement(encodeDigestDays(days) { null }))
        assertTrue(again[0].items.isEmpty())
        assertEquals(days[0].judged, again[0].judged)
    }

    @Test
    fun `the next notification is today's time, or tomorrow's once it has passed`() {
        val morning = LocalDateTime.of(2027, 1, 15, 7, 0)
        assertEquals(60 * 60_000L, DigestNotifications.delayUntil(8 * 60, morning))
        val later = LocalDateTime.of(2027, 1, 15, 9, 0)
        assertEquals(23 * 60 * 60_000L, DigestNotifications.delayUntil(8 * 60, later))
        // Within half a minute of it: tomorrow's, not a second one now.
        assertFalse(DigestNotifications.delayUntil(8 * 60, LocalDateTime.of(2027, 1, 15, 7, 59, 50)) < 60_000L)
    }

    companion object {
        /** Also in swift/IlayTests/Core/DigestStoreTests.swift: keep them the same. */
        const val DIGEST_FIXTURE = """{"days":[{"day":"2027-01-15","built":1000,"refreshed":2000,"seen":1500,"overview":"Calm.","aiFailed":1,"aiAt":2000,"items":[{"raw":{"id":"abc","name":"t3_abc","title":"Hello","subreddit":"swift","subreddit_name_prefixed":"r/swift","author":"a","score":42,"num_comments":7,"created_utc":1800000000,"permalink":"/r/swift/comments/abc/","url":"https://www.reddit.com/r/swift/comments/abc/","is_self":true},"why":"Why.","n":2.5,"at":1000,"imp":4}],"judged":{"abc":[1,2.5,1000,0],"def":[0,1.1,1000,1]}}]}"""
    }
}
