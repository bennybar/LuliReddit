package com.bennybar.luli_for_reddit.core

import org.junit.Assert.assertEquals
import org.junit.Test

class TranslateTest {
    @Test
    fun `batches keep order and respect both limits`() {
        val texts = listOf("aaaa", "bb", "cccccc", "d", "ee")
        assertEquals(listOf(listOf("aaaa", "bb"), listOf("cccccc"), listOf("d", "ee")), Translate.batches(texts, 6, 10))
        assertEquals(listOf(listOf("aaaa", "bb"), listOf("cccccc", "d"), listOf("ee")), Translate.batches(texts, 100, 2))
        // A text longer than the limit goes alone.
        assertEquals(listOf(listOf("aaaa"), listOf("bb")), Translate.batches(listOf("aaaa", "bb"), 3, 10))
    }

    @Test
    fun `old Java language codes become the usual ones`() {
        assertEquals("he", Translate.norm("iw"))
        assertEquals("id", Translate.norm("in"))
        assertEquals("de", Translate.norm("de"))
    }
}
