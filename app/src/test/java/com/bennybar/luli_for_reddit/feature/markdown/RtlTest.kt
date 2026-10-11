package com.bennybar.luli_for_reddit.feature.markdown

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Mostly-Hebrew/Arabic text lays out right-to-left (summaries, comments). */
class RtlTest {
    @Test
    fun `a Hebrew summary is RTL even with English words in it`() {
        assertTrue(isMostlyRtl("TL;DR: המשתמשים ב-Reddit חושבים שהעדכון של iOS 27 פוגע בסוללה, ורובם ממליצים לחכות לגרסה הבאה."))
    }

    @Test
    fun `Arabic is RTL`() {
        assertTrue(isMostlyRtl("يعتقد معظم المعلقين أن التحديث يستهلك البطارية"))
    }

    @Test
    fun `English with a Hebrew word stays LTR`() {
        assertFalse(isMostlyRtl("People in the thread say שלום means both hello and goodbye."))
    }

    @Test
    fun `no letters stays LTR`() {
        assertFalse(isMostlyRtl("123 — 456"))
    }
}
