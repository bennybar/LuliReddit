package com.bennybar.luli_for_reddit.feature.settings

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

class ColorPickerTest {
    @Test
    fun `primaries and greys convert both ways`() {
        assertArrayEquals(floatArrayOf(0f, 1f, 1f), argbToHsv(0xFFFF0000), 0.001f)
        assertArrayEquals(floatArrayOf(120f, 1f, 1f), argbToHsv(0xFF00FF00), 0.001f)
        assertArrayEquals(floatArrayOf(240f, 1f, 1f), argbToHsv(0xFF0000FF), 0.001f)
        assertArrayEquals(floatArrayOf(0f, 0f, 0f), argbToHsv(0xFF000000), 0.001f)
        assertEquals(0xFFFF0000, hsvToArgb(0f, 1f, 1f))
        assertEquals(0xFF00FF00, hsvToArgb(120f, 1f, 1f))
        assertEquals(0xFF0000FF, hsvToArgb(240f, 1f, 1f))
        assertEquals(0xFFFFFFFF, hsvToArgb(200f, 0f, 1f))
        assertEquals(0xFF808080, hsvToArgb(0f, 0f, 128 / 255f))
    }

    @Test
    fun `every accent preset survives a round trip through the picker`() {
        for (c in listOf(0xFF6750A4, 0xFFEA4335, 0xFFFF7043, 0xFFFFB300, 0xFF34A853, 0xFF00897B, 0xFF1E88E5, 0xFF8E24AA, 0xFFD81B60)) {
            val (h, s, v) = argbToHsv(c).toList()
            assertEquals("%08X".format(c), "%08X".format(hsvToArgb(h, s, v)))
        }
    }

    @Test
    fun `the end of the hue bar is red again, and the result is always opaque`() {
        assertEquals(0xFFFF0000, hsvToArgb(360f, 1f, 1f))
        assertEquals(0xFF000000, hsvToArgb(359.9f, 1f, 0f))
        // Alpha in the input is ignored.
        assertArrayEquals(argbToHsv(0xFF1E88E5), argbToHsv(0x001E88E5), 0.001f)
    }
}
