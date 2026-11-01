package com.cmuxremote.mobile.protocol

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.io.ByteArrayOutputStream

/**
 * Byte-for-byte the JSON that the Swift Bridge re-encodes before it verifies a
 * signature: sorted keys, no escaped slashes, raw UTF-8, no whitespace.
 *
 * Swift's `JSONEncoder(.sortedKeys, .withoutEscapingSlashes)` is the reference;
 * `CanonicalJsonTest` holds the vectors generated from it.
 */
object CanonicalJson {
    fun bytes(value: JsonElement): ByteArray = encode(value).encodeToByteArray()

    fun encode(value: JsonElement): String = buildString { write(value, this) }

    private fun write(value: JsonElement, out: StringBuilder) {
        when (value) {
            is JsonNull -> out.append("null")
            is JsonPrimitive -> writePrimitive(value, out)
            is JsonArray -> {
                out.append('[')
                value.forEachIndexed { index, item ->
                    if (index > 0) out.append(',')
                    write(item, out)
                }
                out.append(']')
            }
            is JsonObject -> {
                out.append('{')
                // Sorted by UTF-16 code unit, which matches Swift for the ASCII
                // and BMP keys these DTOs use.
                val keys = value.keys.sorted()
                keys.forEachIndexed { index, key ->
                    if (index > 0) out.append(',')
                    writeString(key, out)
                    out.append(':')
                    write(value.getValue(key), out)
                }
                out.append('}')
            }
        }
    }

    private fun writePrimitive(value: JsonPrimitive, out: StringBuilder) {
        if (value.isString) {
            writeString(value.content, out)
        } else {
            out.append(value.content)
        }
    }

    private fun writeString(value: String, out: StringBuilder) {
        out.append('"')
        for (character in value) {
            when (character) {
                '"' -> out.append("\\\"")
                '\\' -> out.append("\\\\")
                '\n' -> out.append("\\n")
                '\r' -> out.append("\\r")
                '\t' -> out.append("\\t")
                '\b' -> out.append("\\b")
                '\u000C' -> out.append("\\f")
                else -> if (character < ' ') {
                    out.append("\\u")
                    out.append(character.code.toString(16).padStart(4, '0'))
                } else {
                    out.append(character)
                }
            }
        }
        out.append('"')
    }
}

/** `"cmux-remote/2/" + domain + "\n"` followed by the canonical DTO bytes. */
fun signedBytes(domain: String, value: JsonElement): ByteArray {
    val prefix = "cmux-remote/2/$domain\n".encodeToByteArray()
    val body = CanonicalJson.bytes(value)
    val out = ByteArrayOutputStream(prefix.size + body.size)
    out.write(prefix)
    out.write(body)
    return out.toByteArray()
}
