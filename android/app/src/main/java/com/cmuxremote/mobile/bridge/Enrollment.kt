package com.cmuxremote.mobile.bridge

import com.cmuxremote.mobile.protocol.EnrollmentBootstrap
import com.cmuxremote.mobile.protocol.EnrollmentGrant
import com.cmuxremote.mobile.protocol.EnrollmentRequest
import com.cmuxremote.mobile.protocol.EnrollmentStatus
import com.cmuxremote.mobile.protocol.ClientCapability
import com.cmuxremote.mobile.protocol.ClientScope
import com.cmuxremote.mobile.protocol.HostIdentity
import com.cmuxremote.mobile.protocol.Identity
import com.cmuxremote.mobile.protocol.Json
import com.cmuxremote.mobile.protocol.ProtocolException
import com.cmuxremote.mobile.protocol.Signer
import com.cmuxremote.mobile.protocol.decodeSignedJson
import com.cmuxremote.mobile.protocol.jsonStringList
import com.cmuxremote.mobile.protocol.objectValue
import com.cmuxremote.mobile.protocol.string
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.Base64
import java.util.UUID

/** Decodes the expiring v2 enrollment QR; it carries host trust, never a bearer token. */
object EnrollmentQr {
    private const val Scheme = "cmux-remote://enroll"

    fun decode(text: String): com.cmuxremote.mobile.protocol.SignedJson {
        val trimmed = text.trim()
        if (trimmed.isEmpty() || trimmed.toByteArray().size > 8192) {
            throw ProtocolException("invalid_pairing", "The pairing code is too large.")
        }
        // The Mac's "import enrollment" action copies the signed bootstrap JSON; a
        // scanned code carries the same envelope inside its payload. Both are checked
        // for the host signature and window by `bootstrap`.
        if (!trimmed.startsWith(Scheme)) {
            if (!trimmed.startsWith("{")) {
                throw ProtocolException("invalid_pairing", "Scan a version 2 enrollment code from the Mac.")
            }
            return decodeSignedJson(trimmed)
        }
        val query = trimmed.substringAfter('?', "")
        val params = query.split('&').filter { it.isNotEmpty() }.mapNotNull { part ->
            val name = part.substringBefore('=', "")
            val value = part.substringAfter('=', "")
            if (name.isEmpty()) null else name to value
        }.toMap()
        if (params.size != 2 || params["v"] != "2") {
            throw ProtocolException("invalid_pairing", "Scan a version 2 enrollment code from the Mac.")
        }
        val payload = params["payload"] ?: throw ProtocolException("invalid_pairing", "The pairing code has no payload.")
        val standard = payload.replace('-', '+').replace('_', '/')
        val padded = standard + "=".repeat((4 - standard.length % 4) % 4)
        val data = try {
            Base64.getDecoder().decode(padded)
        } catch (_: IllegalArgumentException) {
            throw ProtocolException("invalid_pairing", "The pairing code is invalid.")
        }
        return decodeSignedJson(String(data, Charsets.UTF_8))
    }

    /** Verifies the host signature and the window before any request is sent. */
    fun bootstrap(text: String, now: Long = System.currentTimeMillis() / 1000): EnrollmentBootstrap {
        val signed = decode(text)
        val value = signed.value as? JsonObject ?: throw ProtocolException("invalid_pairing", "The pairing code is invalid.")
        val hostJson = value.objectValue("host") ?: throw ProtocolException("invalid_pairing", "The pairing code names no host.")
        val host = HostIdentity.from(hostJson)
        Signer.verify(signed, "bootstrap", host.publicKey)
        val bootstrap = EnrollmentBootstrap.from(value)
        bootstrap.validate(now)
        if (bootstrap.workspaces.isEmpty()) throw ProtocolException("invalid_pairing", "No workspace was shared for this window.")
        return bootstrap
    }
}

/** What the phone asks the owner for; the owner can only narrow it. */
val AndroidCapabilities: List<ClientCapability> = listOf(
    ClientCapability.WorkspaceRead,
    ClientCapability.ConversationRead,
    ClientCapability.ProjectRead,
    ClientCapability.ConversationControl,
    ClientCapability.FeedRead,
    ClientCapability.FeedReply,
    ClientCapability.ConversationStart,
)

/** A request awaiting the Mac owner's approval. */
class PendingEnrollment(
    val bootstrap: EnrollmentBootstrap,
    val request: EnrollmentRequest,
    val signedRequest: com.cmuxremote.mobile.protocol.SignedJson,
    private val http: PinnedHttpClient,
) {
    /** Sends the request once; later polls reuse the same signed request ID and nonce. */
    suspend fun submit(): EnrollmentStatus = exchange("request")

    suspend fun status(): EnrollmentStatus = exchange("status")

    suspend fun cancel() {
        runCatching { exchange("cancel") }
    }

    /** The grant, once the owner approved this exact request. */
    fun grant(status: EnrollmentStatus): EnrollmentGrant {
        if (status.state != "approved") {
            throw ProtocolException("enrollment_pending", "Approve this device on the Mac first.")
        }
        if (status.hostID != request.hostID || status.clientID != request.clientID ||
            status.requestID != request.requestID || status.nonce != request.nonce
        ) {
            throw ProtocolException("invalid_grant", "The enrollment response belongs to another host or device.")
        }
        val grant = status.grant ?: throw ProtocolException("invalid_grant", "The approval carried no grant.")
        val signature = status.grantSignature ?: throw ProtocolException("invalid_grant", "The approval is unsigned.")
        if (!Identity.verify(
                com.cmuxremote.mobile.protocol.signedBytes("grant", grantJson(grant)),
                Identity.decodeBase64(signature, 64),
                bootstrap.host.publicKey,
            )
        ) {
            throw ProtocolException("invalid_grant", "The approval does not belong to this host.")
        }
        val grantedWorkspaces = grant.scope.workspaces.toSet()
        val grantedCapabilities = grant.scope.capabilities.toSet()
        if (!grantedWorkspaces.all { it in request.scope.workspaces } ||
            !grantedCapabilities.all { it in request.scope.capabilities }
        ) {
            throw ProtocolException("invalid_grant", "Approval does not match the requested scope.")
        }
        if (grant.requestID != request.requestID || grant.nonce != request.nonce) {
            throw ProtocolException("invalid_grant", "The approval answers another request.")
        }
        return grant
    }

    private fun grantJson(grant: EnrollmentGrant): JsonObject = kotlinx.serialization.json.buildJsonObject {
        put("hostID", JsonPrimitive(grant.hostID))
        put("clientID", JsonPrimitive(grant.clientID))
        put("requestID", JsonPrimitive(grant.requestID))
        put("nonce", JsonPrimitive(grant.nonce))
        put("scope", grant.scope.toJson())
        put("issuedAt", JsonPrimitive(grant.issuedAt))
    }

    private suspend fun exchange(verb: String): EnrollmentStatus = withContext(Dispatchers.IO) {
        val body = Json.bytes(signedRequest.toJson())
        val request = Request.Builder()
            .url(http.baseUrl + "/v2/enrollment/$verb")
            .post(body.toRequestBody("application/json".toMediaType()))
            .build()
        http.newCall(request).execute().use { response ->
            val data = response.body?.bytes() ?: ByteArray(0)
            if (response.code != 200) {
                val code = runCatching {
                    (Json.parse(String(data, Charsets.UTF_8)) as? JsonObject)
                        ?.objectValue("error")?.string("code")
                }.getOrNull() ?: "enrollment_failed"
                val message = runCatching {
                    (Json.parse(String(data, Charsets.UTF_8)) as? JsonObject)
                        ?.objectValue("error")?.string("message")
                }.getOrNull() ?: "The Mac could not answer this request."
                com.cmuxremote.mobile.data.Diagnostics.log(
                    com.cmuxremote.mobile.data.Diagnostics.Level.Warning,
                    "enrollment",
                    "$verb rejected: $code (HTTP ${response.code})",
                )
                throw ProtocolException(code, message, response.code)
            }
            val signed = decodeSignedJson(String(data, Charsets.UTF_8))
            Signer.verify(signed, "enrollment-status", bootstrap.host.publicKey)
            val status = EnrollmentStatus.from(signed.value as? JsonObject ?: throw ProtocolException("invalid_response", "The status is not an object."))
            com.cmuxremote.mobile.data.Diagnostics.log(
                com.cmuxremote.mobile.data.Diagnostics.Level.Debug,
                "enrollment",
                "$verb -> ${status.state}",
            )
            status
        }
    }
}

object Enrollment {
    /**
     * Starts a pending enrollment for one scanned code.
     *
     * The device identity is generated once and kept: the same key must survive
     * the approval and sign every later request.
     */
    fun begin(
        code: String,
        privateKey: ByteArray,
        clientName: String = "cmux Android",
        clientKind: String = "android",
        now: Long = System.currentTimeMillis() / 1000,
    ): PendingEnrollment {
        val bootstrap = EnrollmentQr.bootstrap(code, now)
        return pending(bootstrap, privateKey, clientName, clientKind)
    }

    /**
     * Starts enrollment for a nearby Mac, without a scanned code.
     *
     * The address came from Bonjour, so the response is checked against the identity
     * the service advertised: the signed bootstrap must belong to that exact host,
     * public key and certificate before anything is sent to it.
     */
    suspend fun beginDiscovered(
        endpoint: com.cmuxremote.mobile.protocol.BridgeEndpoint,
        trustedHost: HostIdentity,
        privateKey: ByteArray,
        clientName: String = "cmux Android",
        clientKind: String = "android",
        now: Long = System.currentTimeMillis() / 1000,
    ): PendingEnrollment {
        val http = PinnedHttpClient(endpoint.host, endpoint.port, trustedHost.certificateSHA256)
        val signed = withContext(Dispatchers.IO) {
            val request = Request.Builder()
                .url(http.baseUrl + "/v2/enrollment/bootstrap")
                .get()
                .build()
            http.newCall(request).execute().use { response ->
                val data = response.body?.bytes() ?: ByteArray(0)
                if (response.code != 200) {
                    throw ProtocolException("discovery_failed", "The Mac did not offer an enrollment window.", response.code)
                }
                decodeSignedJson(String(data, Charsets.UTF_8))
            }
        }
        Signer.verify(signed, "bootstrap", trustedHost.publicKey)
        val bootstrap = EnrollmentBootstrap.from(
            signed.value as? JsonObject ?: throw ProtocolException("invalid_response", "The bootstrap is not an object."),
        )
        bootstrap.validate(now)
        if (bootstrap.host.id != trustedHost.id ||
            bootstrap.host.publicKey != trustedHost.publicKey ||
            bootstrap.host.certificateSHA256 != trustedHost.certificateSHA256
        ) {
            throw ProtocolException("host_changed", "The enrollment belongs to another Mac.")
        }
        return pending(bootstrap, privateKey, clientName, clientKind)
    }

    private fun pending(
        bootstrap: EnrollmentBootstrap,
        privateKey: ByteArray,
        clientName: String,
        clientKind: String,
    ): PendingEnrollment {
        val http = PinnedHttpClient(bootstrap.endpoint.host, bootstrap.endpoint.port, bootstrap.host.certificateSHA256)
        val publicKey = Identity.publicKeyBase64(privateKey)
        val request = EnrollmentRequest(
            hostID = bootstrap.host.id,
            windowID = bootstrap.windowID,
            requestID = UUID.randomUUID().toString(),
            clientID = Identity.identityId(publicKey),
            clientPublicKey = publicKey,
            clientName = clientName,
            clientKind = clientKind,
            nonce = UUID.randomUUID().toString(),
            scope = ClientScope.of(bootstrap.workspaces, AndroidCapabilities),
            expiresAt = bootstrap.expiresAt,
        )
        val signed = Signer.sign(request.toJson(), "enrollment-request", privateKey)
        return PendingEnrollment(bootstrap, request, signed, http)
    }

    @Suppress("unused")
    private fun scopes(workspaces: List<String>): List<String> = jsonStringList(workspaces).map { it.toString() }
}
