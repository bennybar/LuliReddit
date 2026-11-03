package com.bennybar.luli_for_reddit.settings

import org.junit.Assert.assertEquals
import org.junit.Test

/** The floating-button settings are persisted by index (#90): old values must keep their meaning. */
class FabSettingsTest {
    @Test
    fun `existing Home button indices are unchanged`() {
        assertEquals(listOf("OFF", "NEW_POST", "SEARCH", "SCROLL_TOP", "REFRESH"), HomeFab.entries.map { it.name })
        assertEquals(listOf("NEW_COMMENT", "SCROLL_TOP", "OFF"), ThreadFab.entries.map { it.name })
    }

    @Test
    fun `defaults keep today's buttons`() {
        val d = Settings()
        // One button for Home and subreddits: never set, it's New post (subreddits' button until now).
        assertEquals(HomeFab.NEW_POST, d.homeFab)
        assertEquals(ThreadFab.NEW_COMMENT, d.threadFab)
        assertEquals(null, d.customSeedColor)
        assertEquals(Settings.DEFAULT_SEED, d.seedColor)
    }
}
