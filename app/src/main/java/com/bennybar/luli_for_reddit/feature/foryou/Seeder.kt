package com.bennybar.luli_for_reddit.feature.foryou

import android.content.Context
import com.bennybar.luli_for_reddit.core.AppJson
import com.bennybar.luli_for_reddit.core.get
import com.bennybar.luli_for_reddit.core.str
import com.bennybar.luli_for_reddit.model.Post
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import java.io.File

// ---------------------------------------------------------------------------
// Last ranked page, for an instant first paint
// ---------------------------------------------------------------------------

// [feed] is "foryou" or "home" (Reddit Home): each keeps its own last page.
// Same file as the Flutter build (getApplicationSupportDirectory = filesDir).
private fun cacheFile(context: Context, user: String, feed: String) =
    File(context.filesDir, "${feed}_${user.lowercase()}.json")

/** Saves the first page (raw post data + each post's reason). */
suspend fun saveForYouPage(
    context: Context,
    user: String,
    posts: List<Post>,
    raw: (String) -> JsonElement?,
    feed: String = "foryou",
) {
    try {
        val rows = posts.take(40).mapNotNull { p ->
            val r = raw(p.id) ?: return@mapNotNull null
            buildJsonObject {
                put("raw", r)
                put("reason", p.feedReason?.let { JsonPrimitive(it) } ?: JsonNull)
            }
        }
        withContext(Dispatchers.IO) { cacheFile(context, user, feed).writeText(JsonArray(rows).toString()) }
    } catch (_: Exception) { /* best effort */ }
}

/** When the saved page was written, or null if there is none. */
suspend fun savedPageTime(context: Context, user: String, feed: String = "foryou"): Long? =
    withContext(Dispatchers.IO) { cacheFile(context, user, feed).takeIf { it.exists() }?.lastModified() }

/** The saved page, minus posts opened since (they'd only be demoted now). */
suspend fun loadForYouPage(context: Context, user: String, opened: Set<String>, feed: String = "foryou"): List<Post>? =
    try {
        withContext(Dispatchers.IO) {
            val f = cacheFile(context, user, feed)
            if (!f.exists()) return@withContext null
            val rows = AppJson.parseToJsonElement(f.readText()).jsonArray
            val posts = rows.map { r ->
                Post.fromData(r["raw"]!!).copy(feedReason = r["reason"].str())
            }.filter { it.id !in opened }
            posts.ifEmpty { null }
        }
    } catch (e: kotlinx.coroutines.CancellationException) {
        throw e
    } catch (_: Exception) {
        null
    }
