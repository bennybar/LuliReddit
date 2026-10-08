package com.bennybar.luli_for_reddit.nav

import androidx.compose.runtime.saveable.SaverScope
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** The media-viewer overlay stack: open/close bookkeeping and surviving recreation. */
class ViewerStackTest {
    @Test
    fun `close fades out the top viewer only`() {
        val s = ViewerStack()
        assertFalse(s.closeTop())
        s.open(MediaViewer.Image("https://i.redd.it/a.jpg"))
        s.open(MediaViewer.Video("https://v.redd.it/x/HLSPlaylist.m3u8", externalUrl = "https://reddit.com/x"))
        assertTrue(s.isOpen)
        assertTrue(s.closeTop())
        assertTrue(s.entries[1].closing)
        assertFalse(s.entries[0].closing)
        assertTrue(s.closeTop())
        assertFalse(s.isOpen)
        assertFalse(s.closeTop())
    }

    @Test
    fun `open viewers survive save and restore`() {
        val s = ViewerStack()
        val gallery = MediaViewer.Gallery(listOf("a", "b"), listOf(1, 2), listOf(3, 4), "t", 1)
        s.open(gallery)
        s.open(MediaViewer.Image("closing"))
        s.closeTop()
        val saved = with(ViewerStack.Saver) { SaverScope { true }.save(s) }!!
        val restored = ViewerStack.Saver.restore(saved)!!
        assertEquals(listOf<MediaViewer>(gallery), restored.entries.map { it.viewer })
        // Restored viewers are shown at once, without fading in again.
        assertTrue(restored.entries[0].visibility.currentState)
    }
}
