package com.bennybar.luli_for_reddit.core

import com.bennybar.luli_for_reddit.core.net.Http
import com.bennybar.luli_for_reddit.core.net.await
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonElement
import okhttp3.Request

data class UpdateInfo(
    val version: String,
    val url: String, // release page
    val apkUrl: String?, // direct .apk asset if present
)

/**
 * Checks GitHub Releases for a newer version (distribution is GitHub-only).
 *
 * A stable build only looks at the latest stable release. A prerelease build
 * (e.g. 2.0.0-beta1) also considers newer prereleases, so beta testers get
 * the next beta — while the Flutter builds, which only read
 * `/releases/latest`, are never offered a beta.
 */
object UpdateChecker {
    suspend fun check(currentVersion: String = RedditConstants.APP_VERSION): UpdateInfo? = try {
        val isPre = currentVersion.contains('-')
        val url = "https://api.github.com/repos/${RedditConstants.GITHUB_REPO}/releases" +
            if (isPre) "?per_page=20" else "/latest"
        val text = Http.client.await(
            Request.Builder().url(url).header("Accept", "application/vnd.github+json").build(),
        ).use { withContext(Dispatchers.IO) { if (it.isSuccessful) it.body.string() else null } }
        val json = text?.let(::parseJsonOrNull)
        val releases: List<JsonElement> = if (isPre) json.arr() ?: emptyList() else listOfNotNull(json)
        val best = releases
            .filter { it["draft"].bool() != true }
            .maxWithOrNull { a, b -> compareVersions(tagOf(a), tagOf(b)) }
        val tag = best?.let(::tagOf).orEmpty()
        if (best == null || tag.isEmpty() || compareVersions(tag, currentVersion) <= 0) null
        else {
            // The LARGEST .apk is the universal build; the smaller ones are per-ABI splits.
            val apk = (best["assets"].arr() ?: emptyList())
                .filter { it["name"].str()?.lowercase()?.endsWith(".apk") == true }
                .maxByOrNull { it["size"].long() ?: 0 }?.get("browser_download_url").str()
            UpdateInfo(tag, best["html_url"].str() ?: "https://github.com/${RedditConstants.GITHUB_REPO}/releases", apk)
        }
    } catch (_: Exception) {
        null
    }

    private fun tagOf(release: JsonElement): String = (release["tag_name"].str() ?: "").removePrefix("v").trim()

    /**
     * Semver-ish: 1.0.51 < 2.0.0-beta1 < 2.0.0-beta2 < 2.0.0.
     * A prerelease sorts before the same version without a suffix.
     */
    fun compareVersions(a: String, b: String): Int {
        fun parts(v: String): Pair<List<Int>, String?> {
            val main = v.substringBefore('-')
            val pre = v.substringAfter('-', "").ifEmpty { null }
            return main.split('.').map { it.toIntOrNull() ?: 0 } to pre
        }
        val (ma, pa) = parts(a)
        val (mb, pb) = parts(b)
        for (i in 0 until 3) {
            val x = ma.getOrElse(i) { 0 }
            val y = mb.getOrElse(i) { 0 }
            if (x != y) return x.compareTo(y)
        }
        return when {
            pa == null && pb == null -> 0
            pa == null -> 1
            pb == null -> -1
            else -> {
                val na = pa.filter { it.isDigit() }.toIntOrNull() ?: 0
                val nb = pb.filter { it.isDigit() }.toIntOrNull() ?: 0
                val la = pa.filter { it.isLetter() }
                val lb = pb.filter { it.isLetter() }
                if (la != lb) la.compareTo(lb) else na.compareTo(nb)
            }
        }
    }
}
