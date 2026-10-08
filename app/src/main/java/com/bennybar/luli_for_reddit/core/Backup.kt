package com.bennybar.luli_for_reddit.core

import com.bennybar.luli_for_reddit.core.storage.Prefs
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

/**
 * Exports / imports all local prefs — settings, the on-device For You model,
 * history, mutes, content filters, etc. Same file format as the Flutter
 * build, so backups move between them. API credentials and tokens live in
 * secure storage and are intentionally NOT included.
 */
object Backup {
    private fun skip(key: String) = key.startsWith("draft_") || key.startsWith("__")

    fun export(p: Prefs): String {
        val data = buildJsonObject {
            for ((k, v) in p.all()) {
                if (skip(k)) continue
                when (v) {
                    is Boolean -> put(k, buildJsonObject { put("t", "b"); put("v", v) })
                    is Long -> put(k, buildJsonObject { put("t", "i"); put("v", v) })
                    is Double -> put(k, buildJsonObject { put("t", "d"); put("v", v) })
                    is String -> put(k, buildJsonObject { put("t", "s"); put("v", v) })
                    is List<*> -> put(k, buildJsonObject {
                        put("t", "l"); put("v", JsonArray(v.map { JsonPrimitive(it.toString()) }))
                    })
                }
            }
        }
        val root = buildJsonObject {
            put("app", "ilay_for_reddit")
            put("version", 1)
            put("data", data)
        }
        return PrettyJson.encodeToString(JsonElement.serializer(), root)
    }

    /** Restores from a backup [json] string. Returns the number of keys written. */
    fun import(p: Prefs, json: String): Int {
        val decoded = runCatching { AppJson.parseToJsonElement(json).jsonObject }.getOrNull()
        val data = decoded?.get("data") as? kotlinx.serialization.json.JsonObject
            ?: throw IllegalArgumentException("Not a valid Ilay backup file.")
        var n = 0
        for ((key, m) in data) {
            val o = m as? kotlinx.serialization.json.JsonObject ?: continue
            val v = o["v"] ?: continue
            when (o["t"]?.jsonPrimitive?.content) {
                "b" -> v.bool()?.let { p.setBool(key, it); n++ }
                "i" -> v.long()?.let { p.setLong(key, it); n++ }
                "d" -> v.double()?.let { p.setDouble(key, it); n++ }
                "s" -> v.str()?.let { p.setString(key, it); n++ }
                "l" -> { p.setStringList(key, v.jsonArray.map { it.jsonPrimitive.content }); n++ }
            }
        }
        return n
    }

    private val PrettyJson = kotlinx.serialization.json.Json { prettyPrint = true; prettyPrintIndent = "  " }
}
