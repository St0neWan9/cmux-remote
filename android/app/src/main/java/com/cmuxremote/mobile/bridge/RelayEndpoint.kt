package com.cmuxremote.mobile.bridge

import com.cmuxremote.mobile.protocol.Identity
import com.cmuxremote.mobile.protocol.Json
import com.cmuxremote.mobile.protocol.ProtocolException
import com.cmuxremote.mobile.protocol.Signer
import com.cmuxremote.mobile.protocol.SignedJson
import com.cmuxremote.mobile.protocol.int
import com.cmuxremote.mobile.protocol.long
import com.cmuxremote.mobile.protocol.signedBytes
import com.cmuxremote.mobile.protocol.string
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import java.util.Base64
import java.util.UUID

/**
 * Public admission to one relay origin. It grants transport reachability only;
 * the host's grant still authorizes every resource.
 */
data class RelayEndpoint(
    val origin: String,
    val admission: SignedJson,
) {
    val permit: JsonObject get() = admission.value as? JsonObject
        ?: throw ProtocolException("invalid_identity", "The relay permit is malformed.", 401)

    /** Canonical `https://host[:port]`, no path, no credentials, no query. */
    fun validate(hostID: String, clientPublicKey: String?, now: Long = System.currentTimeMillis() / 1000) {
        val hpke = permit
        val version = hpke.int("version") ?: 0
        val permitOrigin = hpke.string("origin") ?: ""
        val permitHost = hpke.string("hostID") ?: ""
        val permitID = hpke.string("permitID") ?: ""
        val kind = hpke.string("kind") ?: ""
        if (version != 3 || permitHost != hostID || permitOrigin != origin || permitID.isEmpty() || permitID.length > 128) {
            throw ProtocolException("invalid_identity", "Invalid relay admission identity.", 401)
        }
        if (kind == "enrollment") {
            val expiry = hpke.long("expiresAt") ?: 0
            if (clientPublicKey != null || hpke.string("clientPublicKey") != null || expiry <= now || expiry - now > 600) {
                throw ProtocolException("enrollment_expired", "The relay enrollment window expired.", 401)
            }
        } else if (kind == "approved") {
            if (hpke.long("expiresAt") != null) {
                throw ProtocolException("invalid_identity", "An approved permit has no expiry.", 401)
            }
            val identity = hpke.string("clientPublicKey")
                ?: throw ProtocolException("invalid_identity", "The relay permit names no device.", 401)
            if (clientPublicKey != null && identity != clientPublicKey) {
                throw ProtocolException("invalid_identity", "The relay permit belongs to another device.", 401)
            }
            Identity.identityId(identity)
        } else {
            throw ProtocolException("invalid_identity", "Unknown relay permit kind.", 401)
        }
    }

    /** Verifies the host's signature over the permit. */
    fun verify(hostPublicKey: String) {
        Signer.verify(admission, "relay3-permit", hostPublicKey)
    }

    /** The socket this device dials, and the two headers that admit it. */
    fun connect(hostID: String, clientPublicKey: String, privateKey: ByteArray): RelayConnection {
        val join = buildJsonObject {
            put("version", JsonPrimitive(3))
            put("hostID", JsonPrimitive(hostID))
            put("clientPublicKey", JsonPrimitive(clientPublicKey))
            put("permitDigest", JsonPrimitive(Identity.digest(signedBytes("relay3-permit-envelope", admission.toJson()))))
            put("nonce", JsonPrimitive(UUID.randomUUID().toString()))
            put("timestamp", JsonPrimitive(System.currentTimeMillis() / 1000))
        }
        val signedJoin = Signer.sign(join, "relay3-join", privateKey)
        val encoder = Base64.getEncoder()
        return RelayConnection(
            url = socketURL(hostID),
            headers = mapOf(
                "X-Cmux-Relay-Permit" to encoder.encodeToString(Json.bytes(admission.toJson())),
                "X-Cmux-Relay-Join" to encoder.encodeToString(Json.bytes(signedJoin.toJson())),
            ),
        )
    }

    fun socketURL(hostID: String): String {
        if (hostID.length != 64 || !hostID.all { it.isDigit() || it.lowercaseChar() in 'a'..'f' }) {
            throw ProtocolException("invalid_endpoint", "Invalid relay route.", 400)
        }
        val parts = java.net.URI(origin)
        val scheme = "wss"
        val port = if (parts.port == -1) "" else ":${parts.port}"
        return "$scheme://${parts.host.lowercase()}$port/v3/relay/${hostID.lowercase()}?role=client"
    }

    companion object {
        /** Reads the relay a bootstrap or saved connection carries. */
        fun from(json: JsonElement?): RelayEndpoint? {
            val object_ = json as? JsonObject ?: return null
            val origin = object_.string("origin") ?: return null
            val admissionJson = object_["admission"] as? JsonObject ?: return null
            val value = admissionJson["value"] ?: return null
            val signature = admissionJson.string("signature") ?: return null
            val endpoint = RelayEndpoint(origin, SignedJson(value, signature))
            return endpoint
        }

        fun canonicalOrigin(value: String): String {
            val uri = try {
                java.net.URI(value)
            } catch (_: Exception) {
                throw ProtocolException("invalid_endpoint", "Use an HTTPS relay origin without credentials or a path.")
            }
            if (uri.scheme?.lowercase() != "https" || uri.host.isNullOrEmpty() || uri.userInfo != null ||
                uri.query != null || uri.fragment != null || (uri.path?.isNotEmpty() == true && uri.path != "/") ||
                value.length > 512
            ) {
                throw ProtocolException("invalid_endpoint", "Use an HTTPS relay origin without credentials or a path.")
            }
            val defaultPort = uri.port == -1 || uri.port == 443
            val port = if (defaultPort) "" else ":${uri.port}"
            val canonical = "https://${uri.host.lowercase()}$port"
            if (canonical != value.removeSuffix("/")) {
                throw ProtocolException("invalid_endpoint", "Use the canonical HTTPS relay origin.")
            }
            return canonical
        }
    }
}

/** Where one relayed dial goes, and what admits it. */
data class RelayConnection(val url: String, val headers: Map<String, String>)

/** A relay origin the phone has learned, for its own listing. */
data class RelayOriginRecord(val origin: String)
