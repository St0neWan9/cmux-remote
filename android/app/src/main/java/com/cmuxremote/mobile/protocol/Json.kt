package com.cmuxremote.mobile.protocol

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull

/** JSON parsing shared by the client; lenient about unknown fields, strict about size. */
object Json {
    const val MAX_BYTES = 8_388_608

    private val parser = Json {
        ignoreUnknownKeys = true
        isLenient = false
        allowTrailingComma = false
    }

    fun parse(text: String): JsonElement = parser.parseToJsonElement(text)

    fun bytes(value: JsonElement): ByteArray = CanonicalJson.bytes(value)

    fun text(value: JsonElement): String = value.toString()
}

fun JsonObject.string(key: String): String? = (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content
fun JsonObject.nonNullString(key: String): String? = this[key]?.let { if (it is JsonNull) null else (it as? JsonPrimitive)?.content }
fun JsonObject.int(key: String): Int? = (this[key] as? JsonPrimitive)?.intOrNull
fun JsonObject.double(key: String): Double? = (this[key] as? JsonPrimitive)?.doubleOrNull
fun JsonObject.long(key: String): Long? = (this[key] as? JsonPrimitive)?.longOrNull
fun JsonObject.bool(key: String): Boolean? = (this[key] as? JsonPrimitive)?.booleanOrNull
fun JsonObject.objectValue(key: String): JsonObject? = (this[key] as? JsonObject)
fun JsonObject.array(key: String): JsonArray? = (this[key] as? JsonArray)
fun JsonElement?.asObject(): JsonObject? = this as? JsonObject
fun JsonElement?.asArray(): JsonArray? = this as? JsonArray
fun JsonElement?.asString(): String? = (this as? JsonPrimitive)?.takeIf { it !is kotlinx.serialization.json.JsonNull }?.content
fun JsonElement?.asInt(): Int? = (this as? JsonPrimitive)?.intOrNull
fun JsonElement?.asBool(): Boolean? = (this as? JsonPrimitive)?.booleanOrNull

/** Decodes a JSON string array, ignoring non-strings. */
fun JsonArray.strings(): List<String> = mapNotNull { item -> (item as? JsonPrimitive)?.takeIf { it.isString }?.content }

fun jsonObjectOf(vararg pairs: Pair<String, JsonElement?>): JsonObject = buildMap {
    for ((key, value) in pairs) if (value != null) put(key, value)
}.let { JsonObject(it) }

fun jsonString(value: String): JsonPrimitive = JsonPrimitive(value)
fun jsonInt(value: Int): JsonPrimitive = JsonPrimitive(value)
fun jsonLong(value: Long): JsonPrimitive = JsonPrimitive(value)
fun jsonBool(value: Boolean): JsonPrimitive = JsonPrimitive(value)
fun jsonStringList(values: List<String>): JsonArray = JsonArray(values.map { JsonPrimitive(it) })

@Suppress("unused")
fun JsonObject.requireString(key: String): String =
    string(key) ?: throw ProtocolException("invalid_response", "The response is missing '$key'.")
