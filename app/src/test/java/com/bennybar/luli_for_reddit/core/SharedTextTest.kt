package com.bennybar.luli_for_reddit.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SharedTextTest {
    @Test
    fun `a bare post link`() {
        val url = "https://www.reddit.com/r/Android/comments/abc123/some_title/"
        assertEquals(url, redditUrlInText(url))
    }

    @Test
    fun `a title before the link, and trailing punctuation`() {
        assertEquals(
            "https://reddit.com/r/apple/s/AbCdEf",
            redditUrlInText("Check this out: https://reddit.com/r/apple/s/AbCdEf."),
        )
    }

    @Test
    fun `skips links that aren't reddit`() {
        assertEquals(
            "https://redd.it/xyz",
            redditUrlInText("via https://example.com/a then https://redd.it/xyz"),
        )
    }

    @Test
    fun `no reddit link`() {
        assertNull(redditUrlInText("just some text https://example.com"))
        assertNull(redditUrlInText(null))
    }
}
