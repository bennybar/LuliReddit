package com.bennybar.luli_for_reddit.core

import android.content.Context
import android.content.Intent
import android.icu.util.ULocale
import android.view.textclassifier.TextClassificationManager
import android.view.textclassifier.TextLanguage
import android.view.translation.TranslationCapability
import android.view.translation.TranslationContext
import android.view.translation.TranslationManager
import android.view.translation.TranslationRequest
import android.view.translation.TranslationRequestValue
import android.view.translation.TranslationResponse
import android.view.translation.TranslationSpec
import android.view.translation.Translator
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.core.net.Http
import com.bennybar.luli_for_reddit.core.net.await
import com.bennybar.luli_for_reddit.feature.post.AiService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.util.Locale
import kotlin.coroutines.resume

/**
 * Translation into the phone's language and Settings → Second language.
 * On the phone first, through Android's system translation service
 * (Android 12+; on Pixels it's Android System Intelligence): free, private
 * and offline once a language is downloaded. Languages it can't do (Hebrew,
 * or a phone without the service) go to Settings → Translation service:
 * the OpenAI key summaries use, or Azure Translator.
 */
object Translate {
    /** A language code as everywhere else (Java still says "iw" for Hebrew, "in" for Indonesian). */
    fun norm(code: String): String = when (code) {
        "iw" -> "he"
        "in" -> "id"
        "ji" -> "yi"
        else -> code
    }

    /** The phone's language: the first thing posts are translated into. */
    val primary: String get() = norm(Locale.getDefault().language)

    /** [code]'s name in the phone's language ("German"). */
    fun languageName(code: String): String = Locale.forLanguageTag(code).getDisplayLanguage(Locale.getDefault())

    /**
     * The languages text in [from] can be translated into here: the phone's
     * and the second language, minus [from], each when the phone or the
     * translation service can do it.
     */
    suspend fun targets(context: Context, from: String): List<String> {
        val fallback = fallbackReady()
        return listOf(primary, app.settings.value.translateSecondLanguage).filter { it.isNotEmpty() && it != from }.distinct()
            .filter { fallback || deviceState(context, from, it) != null }
    }

    private suspend fun fallbackReady(): Boolean =
        if (app.settings.value.translateService == "azure") {
            !app.secureStore.azureTranslatorKey().isNullOrEmpty()
        } else {
            !app.secureStore.openaiKey().isNullOrEmpty()
        }

    private fun manager(context: Context) = context.getSystemService(TranslationManager::class.java)

    /** The phone's own translator's state for [from] → [to], or null when it can't. */
    private suspend fun deviceState(context: Context, from: String, to: String): Int? = withContext(Dispatchers.IO) {
        val caps = runCatching {
            manager(context)?.getOnDeviceTranslationCapabilities(TranslationSpec.DATA_FORMAT_TEXT, TranslationSpec.DATA_FORMAT_TEXT)
        }.getOrNull() ?: return@withContext null
        caps.firstOrNull {
            norm(it.sourceSpec.locale.language) == from && norm(it.targetSpec.locale.language) == to &&
                it.state != TranslationCapability.STATE_NOT_AVAILABLE
        }?.state
    }

    /** Whether the phone could translate [from] → [to] once the language is downloaded (its Live Translate settings). */
    suspend fun needsDownload(context: Context, from: String, to: String): Boolean =
        deviceState(context, from, to).let { it != null && it != TranslationCapability.STATE_ON_DEVICE }

    /**
     * Where the phone downloads translation languages: Pixels' Live Translate
     * settings (Android has no API for an app to download one). Null elsewhere.
     */
    fun downloadSettings(context: Context): Intent? =
        Intent("com.android.settings.action.live_translate").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            .takeIf { it.resolveActivity(context.packageManager) != null }

    /** The language [text] is in (a code like "de"), when the phone is fairly sure. */
    suspend fun detect(context: Context, text: String): String? = withContext(Dispatchers.Default) {
        if (text.isBlank()) return@withContext null
        val classifier = context.getSystemService(TextClassificationManager::class.java)?.textClassifier ?: return@withContext null
        val result = runCatching { classifier.detectLanguage(TextLanguage.Request.Builder(text.take(2000)).build()) }.getOrNull()
        if (result == null || result.localeHypothesisCount == 0) return@withContext null
        // Scores run low on short text ("de" 0.33 vs "en" 0.24 on a title):
        // take the best guess when it clearly leads.
        val best = result.getLocale(0)
        val next = if (result.localeHypothesisCount > 1) result.getConfidenceScore(result.getLocale(1)) else 0f
        norm(best.language).takeIf { result.getConfidenceScore(best) >= 0.25f && result.getConfidenceScore(best) > next + 0.05f }
    }

    /**
     * [texts] from [from] into [to], in order: on the phone when it can, else
     * (or when that fails) through the translation service. Null when
     * neither could; the service's error is thrown.
     */
    suspend fun translate(context: Context, texts: List<String>, from: String, to: String): List<String>? {
        if (texts.isEmpty()) return emptyList()
        if (deviceState(context, from, to) != null) {
            // Gives up after a minute: a service that can't run its model (the emulator's) never answers.
            withTimeoutOrNull(60_000) { onPhone(context, texts, from, to) }?.let { return it }
        }
        if (!fallbackReady()) return null
        val s = app.settings.value
        return if (s.translateService == "azure") {
            azure(texts, from, to, app.secureStore.azureTranslatorKey()!!, s.azureRegion)
        } else {
            val base = if (s.aiUseCustomUrl) s.aiBaseUrl else "https://api.openai.com"
            AiService.translate(base, app.secureStore.openaiKey()!!, s.aiModel, texts, Locale.forLanguageTag(to).getDisplayLanguage(Locale.ENGLISH))
        }
    }

    private suspend fun onPhone(context: Context, texts: List<String>, from: String, to: String): List<String>? {
        val tm = manager(context) ?: return null
        val spec = TranslationContext.Builder(
            TranslationSpec(ULocale(from), TranslationSpec.DATA_FORMAT_TEXT),
            TranslationSpec(ULocale(to), TranslationSpec.DATA_FORMAT_TEXT),
        ).build()
        val translator = suspendCancellableCoroutine<Translator?> { cont ->
            runCatching { tm.createOnDeviceTranslator(spec, Runnable::run) { cont.resume(it) } }
                .onFailure { cont.resume(null) }
        } ?: return null
        try {
            // One request for a whole thread's comments.
            val request = TranslationRequest.Builder()
                .setTranslationRequestValues(texts.map { TranslationRequestValue.forText(it) })
                .build()
            val response = suspendCancellableCoroutine<TranslationResponse?> { cont ->
                runCatching { translator.translate(request, null, Runnable::run) { cont.resume(it) } }
                    .onFailure { cont.resume(null) }
            } ?: return null
            if (response.translationStatus != TranslationResponse.TRANSLATION_STATUS_SUCCESS) return null
            val values = response.translationResponseValues
            return texts.indices.map { i -> values.get(i)?.text?.toString() ?: texts[i] }
        } finally {
            translator.destroy()
        }
    }

    /**
     * Azure Translator (Settings → Translation service): [key] and the
     * resource's [region] (empty for a global resource). Up to 1000 texts
     * and 50k characters a request, so a big thread goes in batches.
     */
    private suspend fun azure(texts: List<String>, from: String, to: String, key: String, region: String): List<String> {
        val out = ArrayList<String>(texts.size)
        for (batch in batches(texts, 40_000, 900)) {
            val url = "https://api.cognitive.microsofttranslator.com/translate".toHttpUrl().newBuilder()
                .addQueryParameter("api-version", "3.0")
                .addQueryParameter("from", from)
                .addQueryParameter("to", to)
                .build()
            val body = JsonArray(batch.map { buildJsonObject { put("Text", it) } }).toString()
            val req = Request.Builder().url(url)
                .header("Ocp-Apim-Subscription-Key", key)
                .apply { if (region.isNotEmpty()) header("Ocp-Apim-Subscription-Region", region) }
                .post(body.toRequestBody("application/json".toMediaType()))
                .build()
            val (code, text) = try {
                Http.client.await(req).use { r -> r.code to withContext(Dispatchers.IO) { r.body.string() } }
            } catch (e: IOException) {
                throw Exception("Couldn't reach Azure Translator: ${e.message}")
            }
            val json = runCatching { AppJson.parseToJsonElement(text) }.getOrNull()
            if (code != 200) throw Exception("Azure Translator refused it ($code): ${json["error"]["message"].str() ?: text}")
            batch.indices.mapTo(out) { i -> json[i]["translations"][0]["text"].str() ?: batch[i] }
        }
        return out
    }

    /** [texts] in order, in groups of at most [maxChars] characters and [maxCount] texts. */
    fun batches(texts: List<String>, maxChars: Int, maxCount: Int): List<List<String>> {
        val out = mutableListOf<MutableList<String>>()
        var chars = 0
        for (t in texts) {
            val last = out.lastOrNull()
            if (last == null || last.size >= maxCount || chars + t.length > maxChars) {
                out += mutableListOf(t)
                chars = t.length
            } else {
                last += t
                chars += t.length
            }
        }
        return out
    }
}
