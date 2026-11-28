package com.bennybar.luli_for_reddit.feature.inbox

import org.junit.Assert.assertEquals
import org.junit.Test

class InboxSnippetTest {
    @Test
    fun aGifReplyReadsGif() {
        val s = InboxSnippet.of("![gif](giphy|i5xAvrneZZRX5satOp)")
        assertEquals(InboxMedia.GIF, s.media)
        assertEquals("GIF", s.text)
        assertEquals(InboxMedia.GIF, InboxSnippet.of(" ![gif](giphy|abc|downsized)\n").media)
        assertEquals(InboxMedia.GIF, InboxSnippet.of("https://media.giphy.com/media/abc/giphy.gif").media)
        assertEquals(InboxMedia.GIF, InboxSnippet.of("https://i.redd.it/abc123.gif").media)
    }

    @Test
    fun aPictureReplyReadsImage() {
        assertEquals(InboxMedia.IMAGE, InboxSnippet.of("![img](abc123xyz)").media)
        assertEquals(InboxMedia.IMAGE, InboxSnippet.of("https://preview.redd.it/abc.jpeg?width=640&auto=webp&s=1").media)
        assertEquals(InboxMedia.IMAGE, InboxSnippet.of("https://i.imgur.com/AbCd.png").media)
    }

    @Test
    fun textAroundMediaKeepsTheTextWithAWord() {
        val s = InboxSnippet.of("haha this\n![gif](giphy|xyz)")
        assertEquals(null, s.media)
        assertEquals("haha this GIF", s.text)
        assertEquals("look Image and GIF", InboxSnippet.of("look ![img](a1) and ![gif](giphy|b2)").text)
        assertEquals(null, InboxSnippet.of("![img](a1) ![gif](giphy|b2)").media)
    }

    @Test
    fun emotesAndPlainTextStayAsTheyAre() {
        assertEquals("nice one", InboxSnippet.of("nice ![img](emote|t5_2qh1i|1234) one").text)
        val plain = InboxSnippet.of("Thanks!\nSee https://example.com/page")
        assertEquals("Thanks! See https://example.com/page", plain.text)
        assertEquals(null, plain.media)
    }
}
