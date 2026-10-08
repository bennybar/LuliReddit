package com.bennybar.luli_for_reddit.core.net

import com.bennybar.luli_for_reddit.core.AppJson
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonElement
import java.io.File
import java.security.MessageDigest

/**
 * Tiny on-disk JSON cache for GET responses: painted instantly on open and
 * used as a fallback when the network is unavailable. Same directory and
 * key hashing as the Flutter build (cacheDir/luli_cache/<md5>.json), so its
 * cache carries over.
 */
class ResponseCache(private val cacheDir: File) {
    private val dir: File get() = File(cacheDir, "luli_cache").apply { if (!exists()) mkdirs() }

    private fun file(key: String): File {
        val md5 = MessageDigest.getInstance("MD5").digest(key.toByteArray())
            .joinToString("") { "%02x".format(it) }
        return File(dir, "$md5.json")
    }

    suspend fun write(key: String, json: String) = withContext(Dispatchers.IO) {
        try {
            file(key).writeText(json)
        } catch (_: Exception) { /* best-effort */ }
    }

    suspend fun read(key: String): JsonElement? = withContext(Dispatchers.IO) {
        try {
            val f = file(key)
            if (!f.exists()) null else AppJson.parseToJsonElement(f.readText())
        } catch (_: Exception) {
            null
        }
    }

    suspend fun clear() = withContext(Dispatchers.IO) {
        try {
            dir.deleteRecursively()
        } catch (_: Exception) {}
        Unit
    }
}
