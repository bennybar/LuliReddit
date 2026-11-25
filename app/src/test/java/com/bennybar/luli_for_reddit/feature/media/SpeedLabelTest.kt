package com.bennybar.luli_for_reddit.feature.media

import org.junit.Assert.assertEquals
import org.junit.Test

/** The playback speed button's labels (#260), as the Swift app's. */
class SpeedLabelTest {
    @Test
    fun `whole speeds have no decimals, others no trailing zeros`() {
        assertEquals(listOf("0.5×", "1×", "1.25×", "1.5×", "2×", "4×"), VIDEO_SPEEDS.map(::speedLabel))
    }
}
