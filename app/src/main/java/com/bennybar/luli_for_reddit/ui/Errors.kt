@file:OptIn(androidx.compose.material3.ExperimentalMaterial3ExpressiveApi::class)

package com.bennybar.luli_for_reddit.ui

import androidx.compose.material3.ButtonDefaults
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CloudOff
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.core.net.RedditApiException
import java.io.IOException

/** Turns raw exceptions into friendly, human copy. */
fun friendlyError(e: Any?): String {
    if (e is RedditApiException) {
        when (e.reason) {
            "private" -> return "This community is private."
            "banned" -> return "This community has been banned by Reddit."
            "quarantined" -> return "This community is quarantined: it may have shocking or highly offensive content."
            "gated" -> return "This community may have sensitive content, such as mature themes or graphic images."
            "gold_only" -> return "This community is for premium members only."
        }
        when (e.statusCode) {
            403 -> return "You don't have permission to do that."
            404 -> return "Not found — it may have been removed."
            429 -> return rateLimited()
            in 500..599 -> return "Reddit is having problems right now. Try again later."
        }
    }
    if (e is IOException) return "You appear to be offline. Check your connection and try again."
    val s = (if (e is Throwable) e.message ?: e.toString() else e.toString()).removePrefix("Exception: ")
    val lower = s.lowercase()
    return when {
        "socket" in lower || "connection" in lower || "unable to resolve host" in lower ->
            "You appear to be offline. Check your connection and try again."
        "403" in lower -> "You don't have permission to do that."
        "404" in lower -> "Not found — it may have been removed."
        "429" in lower -> rateLimited()
        "500" in lower || "502" in lower || "503" in lower -> "Reddit is having problems right now. Try again later."
        else -> s
    }
}

/** Rate-limited: when Reddit said the window resets, say how long to wait. */
private fun rateLimited(): String {
    val left = runCatching { app.rateLimit.value?.secondsLeft() }.getOrNull() ?: 0
    return when {
        left <= 0 -> "You're going a bit fast — Reddit is rate-limiting. Try again shortly."
        left < 60 -> "Reddit is rate-limiting for a moment. Try again in ${left}s."
        else -> "Reddit is rate-limiting. Try again in about ${(left + 59) / 60} min."
    }
}

/** Consistent empty / error state with an optional retry. */
@Composable
fun ErrorView(
    message: Any?,
    modifier: Modifier = Modifier,
    onRetry: (() -> Unit)? = null,
    icon: ImageVector = Icons.Rounded.CloudOff,
    retryLabel: String = "Retry",
) {
    Column(
        modifier.fillMaxSize().padding(32.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(icon, null, Modifier.size(48.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(12.dp))
        Text(if (message is String) message else friendlyError(message), textAlign = TextAlign.Center)
        if (onRetry != null) {
            Spacer(Modifier.height(16.dp))
            FilledTonalButton(onClick = onRetry, shapes = ButtonDefaults.shapes()) { Text(retryLabel) }
        }
    }
}
