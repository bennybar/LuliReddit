package com.bennybar.luli_for_reddit.feature.about

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.FileProvider
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ProcessLifecycleOwner
import com.bennybar.luli_for_reddit.app
import com.bennybar.luli_for_reddit.core.UpdateInfo
import com.bennybar.luli_for_reddit.core.net.Http
import com.bennybar.luli_for_reddit.core.net.await
import com.bennybar.luli_for_reddit.ui.Overlays
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import okhttp3.Request
import java.io.File
import kotlin.coroutines.coroutineContext

/** The update notice's button: "Update" when Ilay installs it itself, else "Download". */
fun updateButtonLabel(): String = if (app.settings.value.installUpdatesInApp) "Update" else "Download"

/**
 * The update notice's button. With "Install updates in the app" on, Ilay
 * downloads the release's APK and hands it to Android's installer (its own
 * "Update this app?" confirm); otherwise, without an APK or without the
 * install permission, the download opens in the browser as before.
 */
suspend fun getUpdate(context: Context, info: UpdateInfo) {
    val apk = info.apkUrl
    if (!app.settings.value.installUpdatesInApp || apk == null) return openInBrowser(context, info)
    val pm = context.packageManager
    if (!pm.canRequestPackageInstalls()) {
        // Android asks once per app: send them to the switch and carry on when they're back.
        val opened = runCatching {
            context.startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${context.packageName}"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        }.isSuccess
        if (opened) {
            val state = ProcessLifecycleOwner.get().lifecycle.currentStateFlow
            withTimeoutOrNull(10 * 60_000L) {
                state.first { !it.isAtLeast(Lifecycle.State.RESUMED) }
                state.first { it.isAtLeast(Lifecycle.State.RESUMED) }
            }
        }
        if (!pm.canRequestPackageInstalls()) {
            app.navigatorOrNull?.showSnackbar("Ilay can't install apps, so the update opens in your browser")
            return openInBrowser(context, info)
        }
    }
    val file = Overlays.show<File> { done -> DownloadDialog(context, apk, info.version, done) } ?: return
    // Only ever hand Android this app's own next version.
    val archive = pm.getPackageArchiveInfo(file.path, 0)
    if (archive?.packageName != context.packageName || archive.versionName != info.version) {
        file.delete()
        app.navigatorOrNull?.showSnackbar("The download didn't look right, so it opens in your browser instead")
        return openInBrowser(context, info)
    }
    val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", file)
    runCatching {
        context.startActivity(
            Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK),
        )
    }.onFailure { openInBrowser(context, info) }
}

private fun openInBrowser(context: Context, info: UpdateInfo) {
    runCatching {
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(info.apkUrl ?: info.url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}

/** Downloads [url] into the cache with a progress bar; the file, or null when cancelled or failed. */
@Composable
private fun DownloadDialog(context: Context, url: String, version: String, done: (File?) -> Unit) {
    var progress by remember { mutableStateOf<Float?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(url) {
        val file = runCatching { download(context, url) { progress = it } }
            .onFailure { error = it.message ?: "The download failed" }
            .getOrNull()
        if (file != null) done(file)
    }
    AlertDialog(
        onDismissRequest = {},
        properties = DialogProperties(dismissOnClickOutside = false),
        title = { Text("Updating to v$version") },
        text = {
            Column {
                if (error != null) {
                    Text(error!!, color = MaterialTheme.colorScheme.error)
                } else {
                    Text("Downloading…")
                    Spacer(Modifier.height(16.dp))
                    val p = progress
                    if (p == null) LinearProgressIndicator(Modifier.fillMaxWidth())
                    else LinearProgressIndicator(progress = { p }, modifier = Modifier.fillMaxWidth())
                }
            }
        },
        confirmButton = { TextButton(onClick = { done(null) }) { Text(if (error != null) "Close" else "Cancel") } },
    )
}

private suspend fun download(context: Context, url: String, onProgress: (Float?) -> Unit): File {
    val dir = File(context.cacheDir, "updates").apply { mkdirs() }
    dir.listFiles()?.forEach { it.delete() } // an older update or a cancelled one
    val file = File(dir, "ilay-update.apk")
    Http.client.await(Request.Builder().url(url).build()).use { res ->
        if (!res.isSuccessful) throw Exception("The download failed (${res.code})")
        withContext(Dispatchers.IO) {
            val total = res.body.contentLength()
            res.body.byteStream().use { input ->
                file.outputStream().use { out ->
                    val buf = ByteArray(64 * 1024)
                    var read = 0L
                    while (true) {
                        coroutineContext.ensureActive()
                        val n = input.read(buf)
                        if (n < 0) break
                        out.write(buf, 0, n)
                        read += n
                        if (total > 0) onProgress(read.toFloat() / total)
                    }
                }
            }
        }
    }
    return file
}
