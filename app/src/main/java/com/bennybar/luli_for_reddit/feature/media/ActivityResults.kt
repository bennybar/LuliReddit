package com.bennybar.luli_for_reddit.feature.media

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContract
import androidx.compose.runtime.LaunchedEffect
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.ui.Overlays
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

private class ResultBox<O>(val value: O)

/**
 * Runs an activity-result contract from anywhere (a module, a click handler)
 * and suspends for its result — the replacement for the Flutter build's
 * method-channel / plugin round-trips. The launcher is registered by an
 * invisible entry in the app's [Overlays] host, so MainActivity needs no
 * per-feature code. Null when there's no activity (background) or the
 * launch failed.
 */
suspend fun <I, O> launchForResult(contract: ActivityResultContract<I, O>, input: I): O? =
    withContext(Dispatchers.Main) {
        if (app.navigatorOrNull == null) return@withContext null
        Overlays.show<ResultBox<O>> { done ->
            val launcher = rememberLauncherForActivityResult(contract) { done(ResultBox(it)) }
            LaunchedEffect(Unit) {
                try {
                    launcher.launch(input)
                } catch (_: Exception) {
                    done(null) // e.g. no app handles the intent
                }
            }
        }?.value
    }
