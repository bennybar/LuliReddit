package com.bennybar.luli_for_reddit.core.storage

import android.content.Context
import android.util.Base64
import android.util.Log
import com.bennybar.luli_for_reddit.core.AppJson
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonPrimitive
import java.io.ByteArrayInputStream
import java.io.ObjectInputStream
import java.math.BigInteger

/**
 * One-time import of everything the Flutter build (≤ v1.0.51) kept in its
 * SharedPreferences — settings, the For You model, history, mutes, filters,
 * drafts — into [Prefs], so updating to the Kotlin app keeps it all.
 *
 * Flutter's legacy store is the `FlutterSharedPreferences` file with every
 * key prefixed `flutter.`; doubles and string lists are encoded as strings
 * with fixed base64 prefixes (see shared_preferences_android's
 * LegacySharedPreferencesPlugin). Logins need no import: the Flutter
 * secure-storage file is read in place by [SecureStore].
 *
 * The Flutter file is left untouched (a harmless few KB), so a failed
 * migration can simply be retried on the next launch.
 */
object FlutterMigration {
    private const val TAG = "FlutterMigration"
    private const val FLUTTER_FILE = "FlutterSharedPreferences"
    private const val KEY_PREFIX = "flutter."
    private const val LIST_PREFIX = "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIGxpc3Qu"
    private const val JSON_LIST_PREFIX = "$LIST_PREFIX!"
    private const val BIG_INTEGER_PREFIX = "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBCaWdJbnRlZ2Vy"
    private const val DOUBLE_PREFIX = "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBEb3VibGUu"

    /** Set once the import has run (successfully). */
    const val DONE_KEY = "__migrated_from_flutter"

    fun runIfNeeded(context: Context, prefs: Prefs) {
        if (prefs.getBool(DONE_KEY) == true) return
        val flutter = context.getSharedPreferences(FLUTTER_FILE, Context.MODE_PRIVATE)
        var n = 0
        for ((rawKey, v) in flutter.all) {
            if (!rawKey.startsWith(KEY_PREFIX)) continue
            val key = rawKey.removePrefix(KEY_PREFIX)
            // Never clobber a value the Kotlin app already wrote.
            if (prefs.contains(key)) continue
            try {
                when (v) {
                    is Boolean -> prefs.setBool(key, v)
                    is Long -> prefs.setLong(key, v)
                    is Int -> prefs.setLong(key, v.toLong())
                    is Float -> prefs.setDouble(key, v.toDouble())
                    is String -> when {
                        v.startsWith(JSON_LIST_PREFIX) -> prefs.setStringList(
                            key,
                            AppJson.parseToJsonElement(v.removePrefix(JSON_LIST_PREFIX))
                                .jsonArray.map { it.jsonPrimitive.content },
                        )
                        v.startsWith(LIST_PREFIX) -> prefs.setStringList(key, decodeLegacyList(v.removePrefix(LIST_PREFIX)))
                        v.startsWith(DOUBLE_PREFIX) ->
                            v.removePrefix(DOUBLE_PREFIX).toDoubleOrNull()?.let { prefs.setDouble(key, it) }
                        v.startsWith(BIG_INTEGER_PREFIX) ->
                            prefs.setLong(key, BigInteger(v.removePrefix(BIG_INTEGER_PREFIX), 36).toLong())
                        else -> prefs.setString(key, v)
                    }
                    is Set<*> -> prefs.setStringList(key, v.map { it.toString() })
                }
                n++
            } catch (e: Exception) {
                Log.w(TAG, "Skipped $key", e)
            }
        }
        prefs.setBool(DONE_KEY, true)
        Log.i(TAG, "Imported $n Flutter preferences")
    }

    /** Pre-2.3 shared_preferences: a base64 Java-serialized ArrayList<String>. */
    @Suppress("UNCHECKED_CAST")
    private fun decodeLegacyList(encoded: String): List<String> {
        val bytes = Base64.decode(encoded, Base64.DEFAULT)
        ObjectInputStream(ByteArrayInputStream(bytes)).use { stream ->
            return (stream.readObject() as List<*>).map { it.toString() }
        }
    }
}
