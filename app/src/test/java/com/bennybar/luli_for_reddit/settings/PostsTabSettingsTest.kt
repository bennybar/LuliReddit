package com.bennybar.luli_for_reddit.settings

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

/** The Posts tab stays the frontpage unless "Posts tab shows r/all" is on. */
class PostsTabSettingsTest {
    @Test
    fun `frontpage by default, r all when on`() {
        val d = Settings()
        assertFalse(d.postsTabAll)
        assertEquals("", d.postsTabKey)
        assertEquals("all", d.copy(postsTabAll = true).postsTabKey)
    }
}
