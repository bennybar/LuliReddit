package com.bennybar.luli_for_reddit.feature.home

import com.bennybar.luli_for_reddit.settings.Settings
import org.junit.Assert.assertEquals
import org.junit.Test

/** The bottom bar's tabs (by their fixed index): 0 Posts, 1 Explore, 2 Inbox, 3 Profile, 4 Digest. */
class TabOrderTest {
    @Test
    fun `the usual four`() = assertEquals(listOf(0, 1, 2, 3), tabOrder(Settings(), signedIn = true))

    @Test
    fun `the Digest's tab goes after Explore, only signed in and when it's on`() {
        val tab = Settings(digestEnabled = true, digestPlace = 1)
        assertEquals(listOf(0, 1, 4, 2, 3), tabOrder(tab, signedIn = true))
        assertEquals(listOf(0, 1, 2, 3), tabOrder(tab, signedIn = false))
        assertEquals(listOf(0, 1, 2, 3), tabOrder(tab.copy(digestEnabled = false), signedIn = true))
        assertEquals(listOf(0, 1, 2, 3), tabOrder(tab.copy(digestPlace = 0), signedIn = true))
    }

    @Test
    fun `Inbox in Profile drops its tab`() {
        assertEquals(listOf(0, 1, 3), tabOrder(Settings(inboxInProfile = true), signedIn = true))
        assertEquals(listOf(0, 1, 4, 3), tabOrder(Settings(inboxInProfile = true, digestEnabled = true, digestPlace = 1), signedIn = true))
    }
}
