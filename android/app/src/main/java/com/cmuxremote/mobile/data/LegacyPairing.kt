package com.cmuxremote.mobile.data

import com.cmuxremote.mobile.protocol.ProtocolException
import com.cmuxremote.mobile.protocol.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonPrimitive
import java.util.Base64

/**
 * The opt-in legacy shared-token pairing: host, port, token and certificate pin.
 *
 * It is kept deliberately separate from v2 enrollment: a legacy connection has
 * one shared authority with no per-device grant, so the reader must choose it
 * explicitly and is warned that the Mac has to run with `--legacy`.
 */
data class LegacyPairing(
    val host: String,
    val port: Int,
    val token: String,
    val certificateSHA256: String,
) {
    fun validate(): LegacyPairing {
        if (host.isEmpty() || host.contains("/") || host.contains("@") ||
            host.any { it.isWhitespace() } || host.toByteArray().size > 253 ||
            port !in 1..65535 || token.toByteArray().size < 32 ||
            certificateSHA256.length != 64 ||
            certificateSHA256.any { !it.isDigit() && it.lowercaseChar() !in 'a'..'f' }
        ) {
            throw ProtocolException("invalid_pairing", "Check the host, port, token and certificate fingerprint.")
        }
        return copy(certificateSHA256 = certificateSHA256.lowercase())
    }
}

/** Decodes `cmux-remote://pair?v=1&payload=<base64url(JSON)>`. */
object LegacyPairingCodec {
    fun decode(text: String): LegacyPairing? {
        if (text.length > 4096 || !text.startsWith("cmux-remote://pair?")) return null
        val query = text.substringAfter('?').split('&').mapNotNull { part ->
            val index = part.indexOf('=')
            if (index <= 0) null else part.substring(0, index) to part.substring(index + 1)
        }.toMap()
        if (query["v"] != "1") return null
        val payload = query["payload"] ?: return null
        val decoded = payload.replace('-', '+').replace('_', '/')
        val padded = decoded + "=".repeat((4 - decoded.length % 4) % 4)
        val json = runCatching {
            Json.parse(String(Base64.getDecoder().decode(padded), Charsets.UTF_8)) as? JsonObject
        }.getOrNull() ?: return null
        return runCatching {
            LegacyPairing(
                host = json["host"]?.jsonPrimitive?.contentOrNull ?: return null,
                port = json["port"]?.jsonPrimitive?.intOrNull ?: return null,
                token = json["token"]?.jsonPrimitive?.contentOrNull ?: return null,
                certificateSHA256 = json["certificateSHA256"]?.jsonPrimitive?.contentOrNull ?: return null,
            ).validate()
        }.getOrNull()
    }
}
