package com.bennybar.luli_for_reddit.core

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull

/** Lenient JSON for Reddit responses and local stores. */
val AppJson = Json {
    ignoreUnknownKeys = true
    isLenient = true
    explicitNulls = false
}

/*
 * Safe accessors for Reddit's polymorphic fields (a value can be an object,
 * "", false or null depending on the post — never assume a shape).
 */
operator fun JsonElement?.get(key: String): JsonElement? = (this as? JsonObject)?.get(key)
operator fun JsonElement?.get(index: Int): JsonElement? = (this as? JsonArray)?.getOrNull(index)

fun JsonElement?.obj(): JsonObject? = this as? JsonObject
fun JsonElement?.arr(): JsonArray? = this as? JsonArray

/** A JSON string value (not a number/bool/null rendered as text). */
fun JsonElement?.str(): String? = (this as? JsonPrimitive)?.takeIf { it.isString }?.content

fun JsonElement?.double(): Double? =
    (this as? JsonPrimitive)?.takeIf { !it.isString }?.content?.toDoubleOrNull()

fun JsonElement?.long(): Long? = double()?.toLong()
fun JsonElement?.int(): Int? = double()?.toInt()

/** A JSON boolean (strict: "true" as a string is not a boolean). */
fun JsonElement?.bool(): Boolean? = (this as? JsonPrimitive)?.takeIf { !it.isString }?.booleanOrNull

fun JsonElement?.isTrue(): Boolean = bool() == true

fun parseJsonOrNull(text: String): JsonElement? =
    try {
        AppJson.parseToJsonElement(text)
    } catch (_: Exception) {
        null
    }
