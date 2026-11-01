package com.cmuxremote.mobile.protocol

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject

/** Public host trust, bound to a TLS leaf certificate and independent of its address. */
data class HostIdentity(
    val id: String,
    val publicKey: String,
    val certificateSHA256: String,
    val name: String,
) {
    fun toJson(): JsonObject = buildJsonObject {
        put("id", JsonPrimitive(id))
        put("publicKey", JsonPrimitive(publicKey))
        put("certificateSHA256", JsonPrimitive(certificateSHA256))
        put("name", JsonPrimitive(name))
    }

    fun validate() {
        if (Identity.identityId(publicKey) != id) {
            throw ProtocolException("invalid_identity", "The host identity is inconsistent.")
        }
        if (certificateSHA256.length != 64 || certificateSHA256.any { !it.isDigit() && it.lowercaseChar() !in 'a'..'f' }) {
            throw ProtocolException("invalid_identity", "The host certificate pin is invalid.")
        }
        if (name.isEmpty() || name.toByteArray().size > 128) {
            throw ProtocolException("invalid_identity", "The host name is invalid.")
        }
    }

    companion object {
        fun from(json: JsonObject): HostIdentity = HostIdentity(
            id = json.requireString("id"),
            publicKey = json.requireString("publicKey"),
            certificateSHA256 = json.requireString("certificateSHA256"),
            name = json.string("name") ?: "",
        )
    }
}

/** Reachability only; the saved host identity supplies trust. */
data class BridgeEndpoint(
    val host: String,
    val port: Int,
    /** A relay the host signed for this endpoint, when one was offered. */
    val relay: com.cmuxremote.mobile.bridge.RelayEndpoint? = null,
) {
    fun toJson(): JsonObject = buildJsonObject {
        put("host", JsonPrimitive(host))
        put("port", JsonPrimitive(port))
        relay?.let { put("relay", buildJsonObject {
            put("origin", JsonPrimitive(it.origin))
            put("admission", it.admission.toJson())
        }) }
    }

    companion object {
        fun from(json: JsonObject): BridgeEndpoint = BridgeEndpoint(
            host = json.requireString("host"),
            port = json.int("port") ?: throw ProtocolException("invalid_response", "The endpoint has no port."),
            relay = com.cmuxremote.mobile.bridge.RelayEndpoint.from(json["relay"]),
        )
    }
}

/** Host-signed bootstrap for one short-lived enrollment window; it carries no permanent credential. */
data class EnrollmentBootstrap(
    val host: HostIdentity,
    val endpoint: BridgeEndpoint,
    val workspaces: List<String>,
    val windowID: String,
    val expiresAt: Long,
    val version: Int,
) {
    fun validate(now: Long = System.currentTimeMillis() / 1000) {
        host.validate()
        if (version != 2) throw ProtocolException("invalid_pairing", "This Bridge speaks another protocol version.")
        if (expiresAt <= now || expiresAt - now > 600) {
            throw ProtocolException("enrollment_expired", "Open a new enrollment window on the Mac.")
        }
    }

    companion object {
        fun from(json: JsonObject): EnrollmentBootstrap = EnrollmentBootstrap(
            host = HostIdentity.from(json.objectValue("host") ?: throw ProtocolException("invalid_response", "The bootstrap has no host.")),
            endpoint = BridgeEndpoint.from(json.objectValue("endpoint") ?: throw ProtocolException("invalid_response", "The bootstrap has no endpoint.")),
            workspaces = json.array("workspaces")?.strings() ?: emptyList(),
            windowID = json.requireString("windowID"),
            expiresAt = json.long("expiresAt") ?: 0L,
            version = json.int("version") ?: 0,
        )
    }
}

/** Capabilities a device may request; the owner can only narrow them. */
enum class ClientCapability(val raw: String) {
    WorkspaceRead("workspaceRead"),
    ConversationRead("conversationRead"),
    ProjectRead("projectRead"),
    ConversationControl("conversationControl"),
    FeedRead("feedRead"),
    FeedReply("feedReply"),
    ConversationStart("conversationStart"),
    TerminalRead("terminalRead"),
    TerminalInput("terminalInput");

    companion object {
        fun from(raw: String): ClientCapability? = entries.firstOrNull { it.raw == raw }
    }
}

/** Explicit workspace UUIDs plus the capabilities granted on them. */
data class ClientScope(val workspaces: List<String>, val capabilities: List<ClientCapability>) {
    fun toJson(): JsonObject = buildJsonObject {
        put("workspaces", JsonArray(workspaces.map { JsonPrimitive(it) }))
        put("capabilities", JsonArray(capabilities.map { JsonPrimitive(it.raw) }))
    }

    fun has(capability: ClientCapability): Boolean = capabilities.contains(capability)

    companion object {
        /** Same normalization as `ClientScope.init`: lowercase, sorted. */
        fun of(workspaces: List<String>, capabilities: List<ClientCapability>): ClientScope =
            ClientScope(
                workspaces = workspaces.map { it.lowercase() }.sorted(),
                capabilities = capabilities.sortedBy { it.raw },
            )

        fun from(json: JsonObject): ClientScope = ClientScope(
            workspaces = json.array("workspaces")?.strings() ?: emptyList(),
            capabilities = (json.array("capabilities")?.strings() ?: emptyList()).mapNotNull(ClientCapability::from),
        )
    }
}

/** The phone asks to be enrolled for one exact window and scope. */
data class EnrollmentRequest(
    val hostID: String,
    val windowID: String,
    val requestID: String,
    val clientID: String,
    val clientPublicKey: String,
    val clientName: String,
    val clientKind: String,
    val nonce: String,
    val scope: ClientScope,
    val expiresAt: Long,
) {
    fun toJson(): JsonObject = buildJsonObject {
        put("hostID", JsonPrimitive(hostID))
        put("windowID", JsonPrimitive(windowID))
        put("requestID", JsonPrimitive(requestID))
        put("clientID", JsonPrimitive(clientID))
        put("clientPublicKey", JsonPrimitive(clientPublicKey))
        put("clientName", JsonPrimitive(clientName))
        put("clientKind", JsonPrimitive(clientKind))
        put("nonce", JsonPrimitive(nonce))
        put("scope", scope.toJson())
        put("expiresAt", JsonPrimitive(expiresAt))
    }
}

/** The owner's approval, signed by the host. */
data class EnrollmentGrant(
    val hostID: String,
    val clientID: String,
    val requestID: String,
    val nonce: String,
    val scope: ClientScope,
    val issuedAt: Long,
) {
    fun toJson(): JsonObject = buildJsonObject {
        put("hostID", JsonPrimitive(hostID))
        put("clientID", JsonPrimitive(clientID))
        put("requestID", JsonPrimitive(requestID))
        put("nonce", JsonPrimitive(nonce))
        put("scope", scope.toJson())
        put("issuedAt", JsonPrimitive(issuedAt))
    }

    companion object {
        fun from(json: JsonObject): EnrollmentGrant = EnrollmentGrant(
            hostID = json.requireString("hostID"),
            clientID = json.requireString("clientID"),
            requestID = json.requireString("requestID"),
            nonce = json.string("nonce") ?: "",
            scope = ClientScope.from(json.objectValue("scope") ?: JsonObject(emptyMap())),
            issuedAt = json.long("issuedAt") ?: 0L,
        )
    }
}

/** One enrollment poll result. */
data class EnrollmentStatus(
    val hostID: String,
    val clientID: String,
    val requestID: String,
    val nonce: String,
    val state: String,
    val grant: EnrollmentGrant?,
    val grantSignature: String?,
) {
    companion object {
        fun from(json: JsonObject): EnrollmentStatus {
            val grantJson = json["grant"] as? JsonObject
            return EnrollmentStatus(
                hostID = json.string("hostID") ?: "",
                clientID = json.string("clientID") ?: "",
                requestID = json.string("requestID") ?: "",
                nonce = json.string("nonce") ?: "",
                state = json.string("state") ?: "unknown",
                grant = grantJson?.objectValue("value")?.let(EnrollmentGrant::from),
                grantSignature = grantJson?.string("signature"),
            )
        }
    }
}

/** What the Bridge signs to prove its runtime epoch. */
data class HostAnnouncement(val host: HostIdentity, val epoch: String, val version: Int) {
    companion object {
        fun from(json: JsonObject): HostAnnouncement = HostAnnouncement(
            host = HostIdentity.from(json.objectValue("host") ?: throw ProtocolException("invalid_response", "The announcement has no host.")),
            epoch = json.requireString("epoch"),
            version = json.int("version") ?: 0,
        )
    }
}

/** A device signs the exact method, raw URI and body digest for every request. */
data class RequestProof(
    val epoch: String,
    val hostID: String,
    val clientID: String,
    val method: String,
    val uri: String,
    val bodySHA256: String,
    val nonce: String,
    val timestamp: Long,
) {
    fun toJson(): JsonObject = buildJsonObject {
        put("epoch", JsonPrimitive(epoch))
        put("hostID", JsonPrimitive(hostID))
        put("clientID", JsonPrimitive(clientID))
        put("method", JsonPrimitive(method))
        put("uri", JsonPrimitive(uri))
        put("bodySHA256", JsonPrimitive(bodySHA256))
        put("nonce", JsonPrimitive(nonce))
        put("timestamp", JsonPrimitive(timestamp))
    }
}

/** Saved host trust, device private identity and the host-signed grant. */
data class AuthorizedConnection(
    val host: HostIdentity,
    val endpoint: BridgeEndpoint,
    val privateKey: ByteArray,
    val clientID: String,
    val scope: ClientScope,
    val grantSignature: String,
    val grant: EnrollmentGrant,
    /** The Bridge epoch the last read used; only routing state, not authority. */
    val epoch: String = "",
) {
    fun toJson(): JsonObject = buildJsonObject {
        put("host", host.toJson())
        put("endpoint", endpoint.toJson())
        put("privateKey", JsonPrimitive(Identity.base64(privateKey)))
        put("clientID", JsonPrimitive(clientID))
        put("scope", scope.toJson())
        put("grantSignature", JsonPrimitive(grantSignature))
        put("grant", grant.toJson())
    }

    /** Re-checks everything that could have been tampered with on disk. */
    fun validate() {
        host.validate()
        if (Identity.identityId(Identity.publicKeyBase64(privateKey)) != clientID) {
            throw ProtocolException("invalid_identity", "Saved host and device identities do not match.")
        }
        if (grant.clientID != clientID || grant.hostID != host.id) {
            throw ProtocolException("invalid_identity", "The saved grant belongs to another device.")
        }
        if (!Identity.verify(signedBytes("grant", grant.toJson()), decodeSignature(grantSignature), host.publicKey)) {
            throw ProtocolException("invalid_grant", "The saved grant could not be verified.")
        }
    }

    private fun decodeSignature(value: String): ByteArray = try {
        Identity.decodeBase64(value, 64)
    } catch (_: IllegalArgumentException) {
        throw ProtocolException("invalid_grant", "The saved grant has no valid signature.")
    }

    companion object {
        fun from(json: JsonObject): AuthorizedConnection = AuthorizedConnection(
            host = HostIdentity.from(json.objectValue("host") ?: throw ProtocolException("invalid_identity", "The saved connection has no host.")),
            endpoint = BridgeEndpoint.from(json.objectValue("endpoint") ?: throw ProtocolException("invalid_identity", "The saved connection has no endpoint.")),
            privateKey = Identity.decodeBase64(json.requireString("privateKey"), 32),
            clientID = json.requireString("clientID"),
            scope = ClientScope.from(json.objectValue("scope") ?: JsonObject(emptyMap())),
            grantSignature = json.requireString("grantSignature"),
            grant = EnrollmentGrant.from(json.objectValue("grant") ?: throw ProtocolException("invalid_identity", "The saved connection has no grant.")),
        )
    }
}

@Suppress("unused")
private fun jsonNull(): JsonNull = JsonNull

@Suppress("unused")
private fun stringArray(values: List<String>): JsonArray = buildJsonArray { values.forEach { add(JsonPrimitive(it)) } }
