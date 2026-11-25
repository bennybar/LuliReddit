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
        // #254: Gemini's OpenAI-compatible base.
        assertEquals(
            "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
            chatUrl("https://generativelanguage.googleapis.com/v1beta/openai/"),
        )
    }

    @Test
    fun `a busy Gemini's error array reads as busy, with its message`() {
        // #267: Gemini's OpenAI-compatible endpoint answers 503 with a JSON array.
        val body = """[{"error": {"code": 503, "message": "The model is overloaded. Please try again later.", "status": "UNAVAILABLE"}}]"""
        assertEquals(
            "The AI service is busy: try again in a moment. AI request failed (503): The model is overloaded. Please try again later.",
            AiService.failureMessage(503, body),
        )
    }

    @Test
    fun `other failures keep the provider's message`() {
        assertEquals("AI request failed (401): Incorrect API key", AiService.failureMessage(401, """{"error": {"message": "Incorrect API key"}}"""))
        assertEquals("AI request failed (502): Bad gateway", AiService.failureMessage(502, " Bad gateway \n"))
        assertEquals(
            "The AI service is rate-limiting requests: try again in a moment. AI request failed (429): Slow down",
            AiService.failureMessage(429, """{"error": "Slow down"}"""),
        )
    }
}

/** #271: a search in someone's posts, split into its "From u/" tag and your own words. */
class SplitAuthorQueryTest {
    @Test
    fun `author anywhere in the query is split out`() {
        assertEquals("spez" to "", com.bennybar.luli_for_reddit.feature.feed.splitAuthorQuery("author:spez"))
        assertEquals("spez" to "cats dogs", com.bennybar.luli_for_reddit.feature.feed.splitAuthorQuery("cats author:spez  dogs"))
        assertEquals("Spez" to "cats", com.bennybar.luli_for_reddit.feature.feed.splitAuthorQuery("AUTHOR:Spez cats"))
    }

    @Test
    fun `no author leaves the words`() {
        assertEquals(null to "coauthor:x cats", com.bennybar.luli_for_reddit.feature.feed.splitAuthorQuery(" coauthor:x cats "))
    }
}
