package com.bennybar.luli_for_reddit.settings

import com.bennybar.luli_for_reddit.ui.theme.TextScales
import org.junit.Assert.assertEquals
import org.junit.Test

/** #234: titles, post text and comments start at the app's size (100%), as before. */
class TextSizesTest {
    @Test
    fun `all at 100 percent by default`() {
        val s = Settings()
        assertEquals(1.0, s.titleTextScale, 0.0)
        assertEquals(1.0, s.postTextScale, 0.0)
        assertEquals(1.0, s.commentTextScale, 0.0)
        assertEquals(TextScales(), TextScales(1f, 1f, 1f))
    }
}
