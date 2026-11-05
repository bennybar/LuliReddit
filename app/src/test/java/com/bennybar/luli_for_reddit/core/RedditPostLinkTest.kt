package com.bennybar.luli_for_reddit.core

import com.bennybar.luli_for_reddit.nav.Route
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Links to Reddit posts open in Ilay rather than as an external link card. */
class RedditPostLinkTest {
    @Test
    fun `relative permalinks are posts`() {
        assertEquals(Route.Post("pics", "abc"), redditPostRoute("/r/pics/comments/abc/a_title/"))
        assertEquals(Route.Post("_", "1xoodhe"), redditPostRoute("/user/jackal-molotov/comments/1xoodhe/deserved/"))
    }

    @Test
    fun `absolute permalinks and short links are posts`() {
        assertEquals(Route.Post("pics", "abc"), redditPostRoute("https://www.reddit.com/r/pics/comments/abc/a_title/"))
        assertEquals(Route.Post("_", "1xoodhe"), redditPostRoute("https://reddit.com/user/jackal-molotov/comments/1xoodhe/deserved/"))
        assertEquals(Route.Post("_", "abc"), redditPostRoute("https://old.reddit.com/comments/abc"))
        assertEquals(Route.Post("_", "abc"), redditPostRoute("https://redd.it/abc"))
    }

    @Test
    fun `other links are not`() {
        assertNull(redditPostRoute("https://www.reddit.com/r/pics/"))
        assertNull(redditPostRoute("https://i.redd.it/abc.jpg"))
        assertNull(redditPostRoute("https://v.redd.it/abc"))
        assertNull(redditPostRoute("https://example.com/r/pics/comments/abc/"))
        assertNull(redditPostRoute(""))
    }

    @Test
    fun `an unresolved share link is a Reddit post opened via openLink`() {
        val share = com.bennybar.luli_for_reddit.model.Post.fromData(
            AppJson.parseToJsonElement(
                """{ "id": "y7", "title": "Dumb prize indeed...", "is_self": false, "domain": "reddit.com",
                     "url": "https://www.reddit.com/u/jackal-molotov/s/EsXFnpHs3G" }""",
            ),
        )
        assertTrue(share.shareLink)
        // No route of its own (must be resolved first), so taps go through openLink, which resolves it.
        assertNull(redditPostRoute(share.url))
        assertEquals("Reddit post", com.bennybar.luli_for_reddit.feature.feed.redditLinkLabel(share))
        assertNull(com.bennybar.luli_for_reddit.feature.feed.redditLinkLabel(share.copy(url = "https://example.com/a")))
    }
}
