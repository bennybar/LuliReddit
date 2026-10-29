package com.bennybar.luli_for_reddit.feature.post

import com.bennybar.luli_for_reddit.core.AppJson
import com.bennybar.luli_for_reddit.core.Translate
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
    suspend fun summarize(baseUrl: String, apiKey: String, model: String, style: SummaryStyle, threadText: String, language: String = ""): String {
        // Settings → AI summaries → Summary language ("" = the thread's own).
        val lang = if (language.isEmpty()) "Write the summary in the same language as the thread."
        else "Write the summary in $language, whatever language the thread is in."
        val system = "You summarize Reddit threads accurately and neutrally. Do not invent details. ${style.instruction} $lang"
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
            "guessing. When a point comes from a specific comment, cite it with " +
            "that comment's tag right after the point, like [c3] (several: [c3] [c7]); " +
            "don't write the tags any other way. Be concise and use markdown."
        val messages = buildList {
            add("system" to system)
            add("user" to "THE THREAD:\n$threadText")
            add("assistant" to "Got it. Ask me anything about this thread.")
            history.forEach { add((if (it.fromUser) "user" else "assistant") to it.text) }
            add("user" to question)
        }
        return chat(baseUrl, apiKey, model, messages)
    }

    /**
     * [texts] translated into [language] (its English name), in order: the
     * fallback for languages the phone can't translate (Translate.kt). Sent
     * as JSON arrays, in batches so a long thread fits a reply.
     */
    suspend fun translate(baseUrl: String, apiKey: String, model: String, texts: List<String>, language: String): List<String> {
        val system = "Translate each string in the JSON array the user sends into $language. Keep Markdown, " +
            "links, line breaks, u/ and r/ names as they are. Reply with only a JSON array of the " +
            "translations: the same number of strings, in the same order."
        val out = ArrayList<String>(texts.size)
        for (batch in Translate.batches(texts, 6_000, 60)) {
            val reply = chat(baseUrl, apiKey, model, listOf("system" to system, "user" to JsonArray(batch.map(::JsonPrimitive)).toString()))
            // Some models wrap it in a ```json fence.
            val json = reply.substringAfter("[", "").substringBeforeLast("]", "")
            val list = runCatching { AppJson.parseToJsonElement("[$json]") as JsonArray }.getOrNull()
            if (list == null || list.size != batch.size) throw Exception("The AI's translation didn't come back whole. Try again.")
            list.mapTo(out) { (it as? JsonPrimitive)?.content ?: "" }
        }
        return out
    }

    /** One /v1/chat/completions call; returns the reply text or throws with a readable message. */
    private suspend fun chat(baseUrl: String, apiKey: String, model: String, messages: List<Pair<String, String>>): String {
        val url = chatUrl(baseUrl)
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
     * The thread for Ask: like [buildThreadText], but each comment is tagged
     * [c1], [c2]… so answers can cite them, plus [refs] (tag → comment) to turn
     * those citations into links, and how many comments went in.
     */
    class CitedThread(val text: String, val refs: Map<String, Comment>, val included: Int, val loaded: Int)

    fun buildCitedThread(post: Post, comments: List<Comment>, maxChars: Int): CitedThread {
        val sb = StringBuilder()
        sb.append("POST in r/${post.subreddit} by u/${post.author} — score ${post.score}, ${post.numComments} comments\n")
        sb.append("TITLE: ${post.title}\n")
        if (post.isSelf && post.selftext.isNotBlank()) sb.append("BODY: ${post.selftext.trim()}\n")
        sb.append("\nTOP COMMENTS (most upvoted first), each with its tag:\n")
        val ranked = comments.filter { !it.isMore && it.body.isNotBlank() }.sortedByDescending { it.score }
        val refs = LinkedHashMap<String, Comment>()
        for (c in ranked) {
            val tag = "c${refs.size + 1}"
            val line = "\n[$tag] [${c.score}] u/${c.author}: ${c.body.replace('\n', ' ').trim()}"
            if (sb.length + line.length > maxChars) break
            sb.append(line)
            refs[tag] = c
        }
        sb.append("\n\n(Included ${refs.size} of ${ranked.size} comments, highest-scored first.)")
        return CitedThread(sb.toString(), refs, refs.size, ranked.size)
    }

    private val CITATION = Regex("""\[(c\d+)]""")

    /** Turns the answer's [c12] citations into links to those comments (`ilay-comment:<fullname>`). */
    fun linkCitations(answer: String, refs: Map<String, Comment>): String =
        CITATION.replace(answer) { m ->
            val c = refs[m.groupValues[1]] ?: return@replace ""
            "[u/${c.author}]($COMMENT_LINK${c.fullname})"
        }

    const val COMMENT_LINK = "ilay-comment:"

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

/**
 * The chat endpoint under [baseUrl]. Providers document their base either
 * without the version (api.openai.com, a LiteLLM host) or with it
 * (api.groq.com/openai/v1): don't add a second /v1.
 */
internal fun chatUrl(baseUrl: String): String {
    val base = baseUrl.trim().replace(Regex("/+$"), "")
    return if (Regex("/v\\d+$").containsMatchIn(base)) "$base/chat/completions" else "$base/v1/chat/completions"
}
