package com.bennybar.luli_for_reddit.model

import org.junit.Assert.assertEquals
import org.junit.Test

class InboxEntitiesTest {
    @Test
    fun inboxTitlesAreDecoded() {
        assertEquals("Hi 👋", decodeEntities("Hi &amp;#128075;"))
        assertEquals("Tom & Jerry <3", decodeEntities("Tom &amp; Jerry &lt;3"))
        assertEquals("it's \"x\"", decodeEntities("it&#39;s &quot;x&quot;"))
        assertEquals("😀", decodeEntities("&#x1F600;"))
        // Not an entity, or a plain ampersand: left alone.
        assertEquals("R&D &copy &bogus;", decodeEntities("R&D &copy &bogus;"))
    }
}
