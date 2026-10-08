package com.bennybar.luli_for_reddit.core.storage

import android.content.Context
import android.content.SharedPreferences
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonPrimitive
import com.bennybar.luli_for_reddit.core.AppJson

/**
 * The app's plain key/value store — the Kotlin counterpart of Flutter's
 * SharedPreferences. Keys and value types are identical to the Flutter build
 * (`themeMode` int, `history_<user>` string list, …) so a backup made by
 * either app restores into the other.
 *
 * Android SharedPreferences has no double or ordered-list type, so those are
 * stored as tagged strings ([DOUBLE_TAG] / [LIST_TAG]); [all] decodes the
 * tags so callers (backup) see the real types.
 */
class Prefs(context: Context) {
    val sp: SharedPreferences = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    private val _changes = MutableSharedFlow<String>(extraBufferCapacity = 64)

    /** Emits the key of every write (put/remove). */
    val changes: SharedFlow<String> = _changes

    fun contains(key: String): Boolean = sp.contains(key)

    fun getBool(key: String): Boolean? = (sp.all[key] as? Boolean)

    /** Ints are stored as Long (Dart ints are 64-bit; e.g. ARGB seed colours). */
    fun getLong(key: String): Long? = when (val v = sp.all[key]) {
        is Long -> v
        is Int -> v.toLong()
        else -> null
    }

    fun getInt(key: String): Int? = getLong(key)?.toInt()

    fun getDouble(key: String): Double? =
        (sp.all[key] as? String)?.takeIf { it.startsWith(DOUBLE_TAG) }
            ?.removePrefix(DOUBLE_TAG)?.toDoubleOrNull()

    fun getString(key: String): String? =
        (sp.all[key] as? String)?.takeIf { !it.startsWith(DOUBLE_TAG) && !it.startsWith(LIST_TAG) }

    fun getStringList(key: String): List<String>? {
        val raw = (sp.all[key] as? String)?.takeIf { it.startsWith(LIST_TAG) } ?: return null
        return try {
            AppJson.parseToJsonElement(raw.removePrefix(LIST_TAG)).jsonArray.map { it.jsonPrimitive.content }
        } catch (_: Exception) {
            null
        }
    }

    fun setBool(key: String, v: Boolean) = edit(key) { putBoolean(key, v) }
    fun setLong(key: String, v: Long) = edit(key) { putLong(key, v) }
    fun setInt(key: String, v: Int) = setLong(key, v.toLong())
    fun setDouble(key: String, v: Double) = edit(key) { putString(key, DOUBLE_TAG + v.toString()) }
    fun setString(key: String, v: String) = edit(key) { putString(key, v) }
    fun setStringList(key: String, v: List<String>) =
        edit(key) { putString(key, LIST_TAG + JsonArray(v.map { JsonPrimitive(it) }).toString()) }

    fun remove(key: String) = edit(key) { remove(key) }

    /** Every key with its decoded value (Boolean, Long, Double, String or List<String>). */
    fun all(): Map<String, Any> {
        val out = LinkedHashMap<String, Any>()
        for ((k, v) in sp.all) {
            when (v) {
                is Boolean -> out[k] = v
                is Int -> out[k] = v.toLong()
                is Long -> out[k] = v
                is Float -> out[k] = v.toDouble()
                is String -> when {
                    v.startsWith(DOUBLE_TAG) -> v.removePrefix(DOUBLE_TAG).toDoubleOrNull()?.let { out[k] = it }
                    v.startsWith(LIST_TAG) -> getStringList(k)?.let { out[k] = it }
                    else -> out[k] = v
                }
            }
        }
        return out
    }

    fun keys(): Set<String> = sp.all.keys

    private inline fun edit(key: String, block: SharedPreferences.Editor.() -> Unit) {
        sp.edit().apply(block).apply()
        _changes.tryEmit(key)
    }

    companion object {
        const val FILE = "ilay_prefs"
        const val DOUBLE_TAG = "ilay.double:"
        const val LIST_TAG = "ilay.list:"
    }
}
