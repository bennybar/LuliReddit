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
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.util.Locale
import kotlin.coroutines.resume

/**
 * On-device translation through Android's system translation service
 * (Android 12+; on Pixels it's Android System Intelligence). Free, private
 * and offline once a language is downloaded, but not every phone has the
 * service: then [canTranslate] is false and Ilay doesn't offer Translate.
 */
object Translate {
    /** The language posts are translated into: the phone's. */
    val target: String get() = Locale.getDefault().language

    private fun manager(context: Context) = context.getSystemService(TranslationManager::class.java)

    /** Whether the phone can translate [from] (a language code) into [target] here. */
    suspend fun canTranslate(context: Context, from: String): Boolean = withContext(Dispatchers.IO) {
        if (from == target) return@withContext false
        val caps = runCatching {
            manager(context)?.getOnDeviceTranslationCapabilities(TranslationSpec.DATA_FORMAT_TEXT, TranslationSpec.DATA_FORMAT_TEXT)
        }.getOrNull() ?: return@withContext false
        caps.any {
            it.sourceSpec.locale.language == from && it.targetSpec.locale.language == target &&
                it.state != TranslationCapability.STATE_NOT_AVAILABLE
        }
    }

    /** Whether [from] → [target] still has to be downloaded (the phone's Live Translate settings). */
    suspend fun needsDownload(context: Context, from: String): Boolean = withContext(Dispatchers.IO) {
        val caps = runCatching {
            manager(context)?.getOnDeviceTranslationCapabilities(TranslationSpec.DATA_FORMAT_TEXT, TranslationSpec.DATA_FORMAT_TEXT)
        }.getOrNull() ?: return@withContext false
        caps.any {
            it.sourceSpec.locale.language == from && it.targetSpec.locale.language == target &&
                it.state != TranslationCapability.STATE_ON_DEVICE && it.state != TranslationCapability.STATE_NOT_AVAILABLE
        }
    }

    /**
     * Where the phone downloads translation languages: Pixels' Live Translate
     * settings (Android has no API for an app to download one). Null elsewhere.
     */
    fun downloadSettings(context: Context): Intent? =
        Intent("com.android.settings.action.live_translate").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            .takeIf { it.resolveActivity(context.packageManager) != null }

    /** [code]'s name in the phone's language ("German"). */
    fun languageName(code: String): String = Locale(code).getDisplayLanguage(Locale.getDefault())

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
        best.language.takeIf { result.getConfidenceScore(best) >= 0.25f && result.getConfidenceScore(best) > next + 0.05f }
    }

    /**
     * [texts] from [from] into [target], in order; null when the phone
     * couldn't. Gives up after a minute: a service that can't run its model
     * (the emulator's) never answers.
     */
    suspend fun translate(context: Context, texts: List<String>, from: String): List<String>? =
        withTimeoutOrNull(60_000) { translateNow(context, texts, from) }

    private suspend fun translateNow(context: Context, texts: List<String>, from: String): List<String>? {
        if (texts.isEmpty()) return emptyList()
        val tm = manager(context) ?: return null
        val spec = TranslationContext.Builder(
            TranslationSpec(ULocale(from), TranslationSpec.DATA_FORMAT_TEXT),
            TranslationSpec(ULocale(target), TranslationSpec.DATA_FORMAT_TEXT),
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
}
