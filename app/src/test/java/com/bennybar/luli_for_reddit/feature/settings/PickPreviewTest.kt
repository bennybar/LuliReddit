package com.bennybar.luli_for_reddit.feature.settings

import org.junit.Assert.assertEquals
import org.junit.Test

/** Appearance's preview follows the group of options in view, without flickering at a boundary. */
class PickPreviewTest {
    private val inf = Float.POSITIVE_INFINITY
    private val line = 400f
    private val slack = 48f

    private fun page(vararg tops: Float) = listOf(
        PreviewSection(PreviewKind.POST, tops[0]),
        PreviewSection(PreviewKind.POST, tops[1]),
        PreviewSection(PreviewKind.COMMENTS, tops[2]),
        PreviewSection(PreviewKind.CHIPS, tops[3]),
        PreviewSection(PreviewKind.NONE, tops[4]),
    )

    @Test
    fun `at the top of the page the post shows`() {
        assertEquals(PreviewKind.POST, pickPreview(page(380f, 900f, inf, inf, inf), line, slack, PreviewKind.POST))
    }

    @Test
    fun `a group whose first row is well past the line takes the preview`() {
        val tops = page(Float.NEGATIVE_INFINITY, -200f, 300f, 700f, inf)
        assertEquals(PreviewKind.COMMENTS, pickPreview(tops, line, slack, PreviewKind.POST))
    }

    @Test
    fun `near the line the current preview stays, either way`() {
        // The comments group's first row sits just above the line: still the post…
        assertEquals(PreviewKind.POST, pickPreview(page(-500f, -100f, 380f, inf, inf), line, slack, PreviewKind.POST))
        // …and just below it, coming back up: still the comments.
        assertEquals(PreviewKind.COMMENTS, pickPreview(page(-500f, -100f, 420f, inf, inf), line, slack, PreviewKind.COMMENTS))
    }

    @Test
    fun `the last group hides the preview, and scrolling back brings it`() {
        val atEnd = page(Float.NEGATIVE_INFINITY, Float.NEGATIVE_INFINITY, -300f, 100f, 300f)
        assertEquals(PreviewKind.NONE, pickPreview(atEnd, line, slack, PreviewKind.CHIPS))
        val back = page(Float.NEGATIVE_INFINITY, Float.NEGATIVE_INFINITY, -100f, 200f, 600f)
        assertEquals(PreviewKind.CHIPS, pickPreview(back, line, slack, PreviewKind.NONE))
    }

    @Test
    fun `no groups known keeps what shows`() {
        assertEquals(PreviewKind.CHIPS, pickPreview(emptyList(), line, slack, PreviewKind.CHIPS))
    }
}
