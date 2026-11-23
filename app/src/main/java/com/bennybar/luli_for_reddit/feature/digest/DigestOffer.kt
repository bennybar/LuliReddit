package com.bennybar.luli_for_reddit.feature.digest

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Newspaper
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bennybar.luli_for_reddit.app
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch

/**
 * The Digest's one-time offer: a card at the top of Posts for people who haven't turned
 * it on, until they answer it. Not for a fresh install (it waits a day), not signed out,
 * and not without a favourite community (the digest would be empty).
 */
object DigestOffer {
    private const val DONE_KEY = "digestOfferDone"
    private const val DAY = 24 * 60 * 60_000L

    /** Answered (either way): never shown again. */
    val done by lazy { MutableStateFlow(app.prefs.getBool(DONE_KEY) == true) }

    fun answer() {
        app.prefs.setBool(DONE_KEY, true)
        done.value = true
    }

    internal fun installedADay(context: android.content.Context): Boolean {
        val info = runCatching { context.packageManager.getPackageInfo(context.packageName, 0) }.getOrNull() ?: return false
        return System.currentTimeMillis() - info.firstInstallTime >= DAY
    }
}

/** Whether Posts shows the offer now. */
@Composable
fun rememberDigestOffer(): Boolean {
    val context = LocalContext.current
    val done by DigestOffer.done.collectAsStateWithLifecycle()
    val enabled = app.settings.state.collectAsStateWithLifecycle().value.digestEnabled
    val session by app.session.state.collectAsStateWithLifecycle()
    val signedIn = app.session.session?.anonymous == false
    val eligible = !done && !enabled && signedIn
    // Asked only when everything else says yes (the subscription list is usually loaded already).
    val hasFavourites by produceState(false, eligible, session) {
        value = eligible && DigestOffer.installedADay(context) && runCatching { app.digest.favourites().isNotEmpty() }.getOrDefault(false)
    }
    return eligible && hasFavourites
}

/** The card: what Digest is, Try it (the explainer, with Turn on) or No thanks. */
@Composable
fun DigestOfferCard() {
    val cs = MaterialTheme.colorScheme
    val scope = rememberCoroutineScope()
    Surface(
        Modifier.fillMaxWidth().padding(horizontal = 4.dp),
        shape = RoundedCornerShape(28.dp),
        color = cs.secondaryContainer,
    ) {
        Column(Modifier.padding(start = 18.dp, top = 16.dp, end = 10.dp, bottom = 6.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Outlined.Newspaper, null, Modifier.size(20.dp), tint = cs.onSecondaryContainer)
                Spacer(Modifier.width(8.dp))
                Text("New: Digest", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, color = cs.onSecondaryContainer)
            }
            Spacer(Modifier.height(6.dp))
            Text(
                "The posts that stood out today in your favourite communities, in one short list.",
                Modifier.padding(end = 8.dp),
                style = MaterialTheme.typography.bodyMedium,
                color = cs.onSecondaryContainer,
            )
            Row(Modifier.fillMaxWidth().padding(top = 4.dp), horizontalArrangement = Arrangement.End) {
                TextButton(onClick = DigestOffer::answer) { Text("No thanks") }
                Spacer(Modifier.width(4.dp))
                Button(onClick = {
                    scope.launch {
                        // How Digest works, with Turn on / Not now: either way, answered.
                        val on = showDigestExplainer(ask = true)
                        DigestOffer.answer()
                        if (!on) return@launch
                        app.prefs.setBool("digestExplained", true)
                        app.settings.setDigestEnabled(true)
                        DigestNotifications.reschedule(app.context)
                        // There it is: the chip's digest, when it's a chip.
                        if (app.settings.value.digestPlace == 0) app.digest.onPosts.value = true
                    }
                }) { Text("Try it") }
            }
        }
    }
}
