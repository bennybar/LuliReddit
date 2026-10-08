package com.bennybar.luli_for_reddit.feature.inbox

import com.bennybar.luli_for_reddit.core.AppJson
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** The notification text + tap target built from one raw unread item (inbox_poller.dart parity). */
class InboxPollerParseTest {
    private fun parse(json: String) = InboxModule.parseUnread(AppJson.parseToJsonElement(json))!!

    @Test
    fun `comment reply deep-links to the comment`() {
        val u = parse(
            """{"name":"t1_c1","author":"bob","was_comment":true,"link_title":"A post","body":"hi\nthere",
               "subreddit":"pics","link_id":"t3_p1"}""",
        )
        assertEquals("u/bob replied · A post", u.title)
        assertEquals("hi there", u.body)
        assertEquals(Triple("pics", "p1", "c1"), u.post)
        assertNull(u.messageFullname)
    }

    @Test
    fun `message uses its subject and opens the conversation`() {
        val u = parse("""{"name":"t4_m2","author":"amy","subject":"Hello","body":"","first_message_name":"t4_m1"}""")
        assertEquals("Hello", u.title)
        assertEquals("Open Ilay to read", u.body)
        assertNull(u.post)
        assertEquals("t4_m1", u.messageFullname)
    }

    @Test
    fun `long bodies are cut at 140 chars`() {
        val u = parse("""{"name":"t4_m3","author":"amy","subject":"","body":"${"x".repeat(200)}"}""")
        assertEquals("Message from u/amy", u.title)
        assertEquals("x".repeat(140) + "…", u.body)
        assertEquals("t4_m3", u.messageFullname)
    }
}
