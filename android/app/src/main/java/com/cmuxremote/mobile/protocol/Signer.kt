package com.cmuxremote.mobile.protocol

import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject

/** A domain-separated signature over one JSON value, as carried on the wire. */
data class SignedJson(val value: JsonElement, val signature: String) {
    fun toJson(): JsonObject = buildJsonObject {
        put("value", value)
        put("signature", JsonPrimitive(signature))
    }
}

/** Signs and verifies DTOs the same way `IdentityCryptography` does on the Mac. */
object Signer {
    fun sign(value: JsonElement, domain: String, privateKey: ByteArray): SignedJson =
        SignedJson(value, Identity.base64(Identity.sign(signedBytes(domain, value), privateKey)))

    fun verify(signed: SignedJson, domain: String, publicKeyBase64: String) {
        val message = signedBytes(domain, signed.value)
        val signature = try {
            Identity.decodeBase64(signed.signature, 64)
        } catch (_: IllegalArgumentException) {
            throw ProtocolException("invalid_signature", "The identity proof could not be verified.", 401)
        }
        if (!Identity.verify(message, signature, publicKeyBase64)) {
            throw ProtocolException("invalid_signature", "The identity proof could not be verified.", 401)
        }
    }
}

/** A short-lived signature envelope decoded without knowing the payload type. */
fun decodeSignedJson(text: String): SignedJson {
    val root = Json.parse(text) as? JsonObject
        ?: throw ProtocolException("invalid_response", "The signed value is not an object.")
    val value = root["value"] ?: throw ProtocolException("invalid_response", "The signed value has no payload.")
    val signature = (root["signature"] as? JsonPrimitive)?.content
        ?: throw ProtocolException("invalid_response", "The signed value has no signature.")
    return SignedJson(value, signature)
}
