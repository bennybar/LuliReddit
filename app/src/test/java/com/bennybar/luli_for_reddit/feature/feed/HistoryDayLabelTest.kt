package com.bennybar.luli_for_reddit.feature.feed

import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.LocalDate
import java.util.Locale

// #159: History's day headers.
class HistoryDayLabelTest {
    private val today = LocalDate.of(2026, 11, 11) // a Wednesday

    private fun label(day: LocalDate?) = historyDayLabel(day, today, Locale.US)

    @Test fun recentDaysByName() {
        assertEquals("Today", label(today))
        assertEquals("Yesterday", label(today.minusDays(1)))
        assertEquals("Monday", label(today.minusDays(2)))
        assertEquals("Thursday", label(today.minusDays(6)))
    }

    @Test fun olderDaysByDate() {
        assertEquals("Wed, Nov 4", label(today.minusDays(7)))
        assertEquals("Dec 31, 2025", label(LocalDate.of(2025, 12, 31)))
        assertEquals("Earlier", label(null))
    }
}
