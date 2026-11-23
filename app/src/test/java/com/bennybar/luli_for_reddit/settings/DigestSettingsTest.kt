package com.bennybar.luli_for_reddit.settings

import com.bennybar.luli_for_reddit.feature.digest.DigestSize
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

/** The Digest is off until turned on, Standard-sized, shown as a chip on Posts. */
class DigestSettingsTest {
    @Test
    fun `defaults`() {
        val d = Settings()
        assertFalse(d.digestEnabled)
        assertEquals(DigestSize.STANDARD, DigestSize.of(d.digestSize))
        assertEquals(0, d.digestPlace)
        assertFalse(d.digestShowRead)
    }

    @Test
    fun `an unknown size reads as Standard`() {
        assertEquals(DigestSize.BRIEF, DigestSize.of(0))
        assertEquals(DigestSize.EVERYTHING, DigestSize.of(2))
        assertEquals(DigestSize.STANDARD, DigestSize.of(7))
        assertEquals(DigestSize.STANDARD, DigestSize.of(-1))
    }
}
