package com.bennybar.luli_for_reddit.settings

import org.junit.Assert.assertTrue
import org.junit.Test

/** Recently visited stays on for everyone who never touched its switch. */
class HistorySettingsTest {
    @Test
    fun `recently visited shows by default`() {
        val d = Settings()
        assertTrue(d.trackHistory)
        assertTrue(d.showRecentlyVisited)
    }
}
