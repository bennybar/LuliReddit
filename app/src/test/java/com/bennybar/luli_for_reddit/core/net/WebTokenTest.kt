package com.bennybar.luli_for_reddit.core.net

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Base64

class WebTokenTest {
    private val now = 1_800_000_000_000L

    private fun jwt(expMillis: Long): String {
        fun part(s: String) = Base64.getUrlEncoder().withoutPadding().encodeToString(s.toByteArray())
        return "${part("""{"alg":"RS256"}""")}.${part("""{"exp":${expMillis / 1000},"lid":"t2_x"}""")}.sig"
    }

    @Test
    fun `reads, replaces, adds and removes cookies in a header`() {
        val h = "loid=1; token_v2=old; reddit_session=s"
        assertEquals("old", cookieValue(h, "token_v2"))
        assertNull(cookieValue(h, "csrf_token"))
        assertEquals("loid=1; token_v2=new; reddit_session=s", withCookie(h, "token_v2", "new"))
        assertEquals("loid=1; reddit_session=s", withCookie(h, "token_v2", null))
        assertEquals("loid=1; token_v2=old; reddit_session=s; csrf_token=c", withCookie(h, "csrf_token", "c"))
    }

    @Test
    fun `a token expiring soon, missing or unreadable needs renewing`() {
        fun header(exp: Long) = "reddit_session=s; token_v2=${jwt(exp)}"
        assertFalse(needsNewToken(header(now + 20 * 3_600_000), now))
        assertTrue(needsNewToken(header(now + 2 * 60_000), now))
        assertTrue(needsNewToken(header(now - 3 * 86_400_000), now))
        assertTrue(needsNewToken("reddit_session=s", now))
        assertTrue(needsNewToken("token_v2=garbage", now))
    }

    @Test
    fun `Reddit's expiry has a fraction of a second`() {
        fun part(s: String) = Base64.getUrlEncoder().withoutPadding().encodeToString(s.toByteArray())
        val token = "${part("{}")}.${part("""{"exp":1793307492.7951}""")}.sig"
        assertEquals(1_793_307_492_795L, tokenExpiry(token))
    }

    @Test
    fun `Set-Cookie headers update the header and deleted cookies drop out`() {
        assertEquals(
            "reddit_session=s; token_v2=fresh; csrf_token=c",
            mergeSetCookies(
                "loid=1; reddit_session=s",
                listOf(
                    "token_v2=fresh; Domain=.reddit.com; Path=/; Max-Age=86400; Secure",
                    "csrf_token=c; Path=/",
                    "loid=; Max-Age=0",
                ),
            ),
        )
    }

    @Test
    fun `reads the account a reddit_session belongs to`() {
        fun part(s: String) = Base64.getUrlEncoder().withoutPadding().encodeToString(s.toByteArray())
        val session = "${part("""{"alg":"RS256"}""")}.${part("""{"sub":"t2_abc","exp":1}""")}.sig"
        assertEquals("t2_abc", sessionAccount("loid=1; reddit_session=$session"))
        assertNull(sessionAccount("loid=1; reddit_session=opaque"))
        assertNull(sessionAccount("loid=1"))
    }
}
