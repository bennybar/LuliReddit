package com.bennybar.luli_for_reddit.feature.post

import org.junit.Assert.assertEquals
import org.junit.Test

/** #22: a base that already ends in its version mustn't get a second /v1. */
class AiChatUrlTest {
    @Test
    fun `base without version gets v1`() {
        assertEquals("https://api.openai.com/v1/chat/completions", chatUrl("https://api.openai.com"))
        assertEquals("https://my-litellm:4000/v1/chat/completions", chatUrl("https://my-litellm:4000/"))
    }

    @Test
    fun `base with version is used as is`() {
        assertEquals("https://api.groq.com/openai/v1/chat/completions", chatUrl("https://api.groq.com/openai/v1"))
        assertEquals("https://openrouter.ai/api/v1/chat/completions", chatUrl(" https://openrouter.ai/api/v1/ "))
        assertEquals("https://example.com/v2/chat/completions", chatUrl("https://example.com/v2"))
    }
}
