package com.bennybar.luli_for_reddit.settings

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Autoplay videos: Off / On Wi-Fi only / Always, from the old switch and the new pref. */
class AutoplayModeTest {
    @Test
    fun `the old switch keeps its meaning`() {
        // Before "On Wi-Fi only" there was no autoplayWifiOnly: it reads false.
        assertEquals(AutoplayMode.ALWAYS, autoplayMode(media = true, wifiOnly = false))
        assertEquals(AutoplayMode.OFF, autoplayMode(media = false, wifiOnly = false))
        assertEquals(AutoplayMode.OFF, autoplayMode(media = false, wifiOnly = true))
        assertEquals(AutoplayMode.WIFI, autoplayMode(media = true, wifiOnly = true))
    }

    @Test
    fun `wifi only plays on an unmetered network only`() {
        assertTrue(autoplayAllowed(AutoplayMode.WIFI, unmetered = true))
        assertFalse(autoplayAllowed(AutoplayMode.WIFI, unmetered = false))
        assertTrue(autoplayAllowed(AutoplayMode.ALWAYS, unmetered = false))
        assertFalse(autoplayAllowed(AutoplayMode.OFF, unmetered = true))
    }
}
