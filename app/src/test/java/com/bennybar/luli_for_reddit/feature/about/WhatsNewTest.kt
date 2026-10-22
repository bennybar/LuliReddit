package com.bennybar.luli_for_reddit.feature.about

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WhatsNewTest {
    @Test
    fun `versions compare by number, not text`() {
        assertTrue(newer("2.0.30", "2.0.29"))
        assertTrue(newer("2.0.10", "2.0.9"))
        assertTrue(newer("2.1.0", "2.0.99"))
        assertFalse(newer("2.0.29", "2.0.29"))
        assertFalse(newer("2.0.8", "2.0.29"))
    }

    /** Guards the release step: the newest entry must be this build's version. */
    @Test
    fun `newest release first, and it is this build`() {
        assertEquals(com.bennybar.luli_for_reddit.BuildConfig.VERSION_NAME, CHANGELOG.first().version)
        CHANGELOG.zipWithNext().forEach { (a, b) ->
            assertTrue("${a.version} before ${b.version}", newer(a.version.substringAfterLast(' '), b.version.substringAfterLast(' ')))
        }
    }
}
