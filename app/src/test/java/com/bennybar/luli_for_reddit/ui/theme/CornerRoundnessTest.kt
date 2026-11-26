package com.bennybar.luli_for_reddit.ui.theme

import androidx.compose.ui.unit.dp
import com.bennybar.luli_for_reddit.settings.CornerRoundness
import com.bennybar.luli_for_reddit.settings.Settings
import org.junit.Assert.assertEquals
import org.junit.Test

/** Settings › Appearance › Corner roundness (#283). */
class CornerRoundnessTest {
    @Test
    fun `round is the default and keeps today's corners`() {
        assertEquals(CornerRoundness.ROUND, Settings().cornerRoundness)
        assertEquals(28.dp, scaleCorner(28.dp, CornerRoundness.ROUND.factor))
        assertEquals(16.dp, scaleCorner(16.dp, CornerRoundness.ROUND.factor))
    }

    @Test
    fun `medium and small scale down but never under 4dp`() {
        assertEquals(28.dp * 0.6f, scaleCorner(28.dp, CornerRoundness.MEDIUM.factor))
        assertEquals(28.dp * 0.3f, scaleCorner(28.dp, CornerRoundness.SMALL.factor))
        assertEquals(4.dp, scaleCorner(6.dp, CornerRoundness.SMALL.factor))
        assertEquals(4.dp, scaleCorner(10.dp, CornerRoundness.SMALL.factor))
        // A corner already under 4dp isn't rounded more.
        assertEquals(3.dp, scaleCorner(3.dp, CornerRoundness.SMALL.factor))
    }

    @Test
    fun `square has no rounding`() {
        assertEquals(0.dp, scaleCorner(28.dp, CornerRoundness.SQUARE.factor))
    }

    @Test
    fun `persisted by index, never reordered`() {
        assertEquals(listOf("ROUND", "MEDIUM", "SMALL", "SQUARE"), CornerRoundness.entries.map { it.name })
    }
}
