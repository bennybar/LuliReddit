package com.bennybar.luli_for_reddit.feature.post

import com.bennybar.luli_for_reddit.core.AppJson
import com.bennybar.luli_for_reddit.core.get
import com.bennybar.luli_for_reddit.core.net.Http
import com.bennybar.luli_for_reddit.core.net.await
import com.bennybar.luli_for_reddit.core.obj
import com.bennybar.luli_for_reddit.core.str
import com.bennybar.luli_for_reddit.model.Comment
import com.bennybar.luli_for_reddit.model.Post
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.util.concurrent.TimeUnit

/** Summary styles for AI thread summaries. Persisted by index (`aiSummaryStyle`). */
enum class SummaryStyle(val label: String, val instruction: String) {
    TLDR("TL;DR", "Give a tight 2-4 sentence TL;DR of the discussion."),
    POINTS(
        "Key points",
        "Summarize as concise markdown bullet points: the post in one line, " +
            "then the main takeaways, notable opinions, and any useful facts " +
            "or links raised in the comments.",
    ),
    DEBATE(
        "Consensus & disagreements",
        "Summarize what the commenters broadly agree on, then the main points " +
            "of disagreement or debate, as short markdown sections.",
    ),
    ELI5(
        "Explain like I'm 5",
        "Explain the post and what people are saying in simple, plain language " +
            "anyone could understand.",
    ),
}

/** One chat turn in "Ask about this thread". */
data class AiMessage(val fromUser: Boolean, val text: String)

/**
 * Minimal client for an OpenAI-compatible /v1/chat/completions endpoint.
 * Works with OpenAI or any compatible gateway (e.g. LiteLLM) via baseUrl.
 */
object AiService {
    private val client by lazy {
        Http.client.newBuilder()
            .connectTimeout(20, TimeUnit.SECONDS)
            .readTimeout(90, TimeUnit.SECONDS)
            .build()
    }

    /** Returns the assistant's summary text, or throws with a readable message. */
    suspend fun summarize(baseUrl: String, apiKey: String, model: String, style: SummaryStyle, threadText: String): String {
        val system = "You summarize Reddit threads accurately and neutrally. Do not invent details. ${style.instruction}"
        return chat(baseUrl, apiKey, model, listOf("system" to system, "user" to threadText))
    }

    /**
     * Answers [question] about the thread in [threadText], continuing the
     * conversation in [history] (alternating user / assistant turns, oldest
     * first). Answers only from the thread, and says so when it can't tell.
     */
    suspend fun ask(
        baseUrl: String,
        apiKey: String,
        model: String,
        threadText: String,
        history: List<AiMessage>,
        question: String,
    ): String {
        val system = "You answer questions about one Reddit thread: the post and its " +
            "comments, given in the first user message. Use only what the thread " +
            "says. If it doesn't answer the question, say so plainly instead of " +
            "guessing. Mention the u/username when a point comes from a specific " +
            "comment. Be concise and use markdown."
        val messages = buildList {
            add("system" to system)
            add("user" to "THE THREAD:\n$threadText")
            add("assistant" to "Got it. Ask me anything about this thread.")
            history.forEach { add((if (it.fromUser) "user" else "assistant") to it.text) }
            add("user" to question)
        }
        return chat(baseUrl, apiKey, model, messages)
    }

    /** One /v1/chat/completions call; returns the reply text or throws with a readable message. */
    private suspend fun chat(baseUrl: String, apiKey: String, model: String, messages: List<Pair<String, String>>): String {
        val url = "${baseUrl.replace(Regex("/+$"), "")}/v1/chat/completions"
        val body = buildJsonObject {
            put("model", model)
            put("messages", JsonArray(messages.map { (role, content) -> buildJsonObject { put("role", role); put("content", content) } }))
        }.toString()
        val req = try {
            Request.Builder().url(url)
                .header("Authorization", "Bearer $apiKey")
                .header("Content-Type", "application/json")
                .post(body.toRequestBody("application/json".toMediaType()))
                .build()
        } catch (e: IllegalArgumentException) {
            throw Exception("Could not reach the AI endpoint: ${e.message}")
        }
        val (code, text) = try {
            client.await(req).use { r -> r.code to withContext(Dispatchers.IO) { r.body.string() } }
        } catch (e: IOException) {
            throw Exception("Could not reach the AI endpoint: ${e.message}")
        }
        val data: JsonElement? = runCatching { AppJson.parseToJsonElement(text) }.getOrNull()
        if (code != 200) {
            val msg = if (data is JsonObject) {
                val err = data["error"]
                (err["message"].str() ?: err?.let { if (it is JsonPrimitive) it.content else it.toString() } ?: data.toString())
            } else {
                text
            }
            throw Exception("AI request failed ($code): $msg")
        }
        val content = data["choices"][0]["message"].obj()?.get("content")?.let { (it as? JsonPrimitive)?.content }
        val out = content?.trim() ?: ""
        if (out.isEmpty()) throw Exception("The AI returned an empty answer.")
        return out
    }

    /**
     * Builds the thread text to summarize: the post, then comments ordered by
     * score (most upvoted first) until [maxChars] is reached.
     */
    fun buildThreadText(post: Post, comments: List<Comment>, maxChars: Int): String {
        val sb = StringBuilder()
        sb.append("POST in r/${post.subreddit} by u/${post.author} — score ${post.score}, ${post.numComments} comments\n")
        sb.append("TITLE: ${post.title}\n")
        if (post.isSelf && post.selftext.isNotBlank()) sb.append("BODY: ${post.selftext.trim()}\n")
        sb.append("\nTOP COMMENTS (most upvoted first):\n")

        val ranked = comments.filter { !it.isMore && it.body.isNotBlank() }.sortedByDescending { it.score }
        var included = 0
        for (c in ranked) {
            val line = "\n[${c.score}] u/${c.author}: ${c.body.replace('\n', ' ').trim()}"
            if (sb.length + line.length > maxChars) break
            sb.append(line)
            included++
        }
        sb.append("\n\n(Included $included of ${ranked.size} comments, highest-scored first.)")
        return sb.toString()
    }
}
