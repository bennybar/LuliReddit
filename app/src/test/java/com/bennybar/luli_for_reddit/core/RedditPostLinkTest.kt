package com.bennybar.luli_for_reddit.core

import com.bennybar.luli_for_reddit.nav.Route
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
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
}
