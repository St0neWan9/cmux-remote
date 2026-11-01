package com.cmuxremote.mobile.bridge

import com.cmuxremote.mobile.protocol.BridgeEndpoint
import com.cmuxremote.mobile.protocol.HostIdentity
import com.cmuxremote.mobile.protocol.HpkeSession
import com.cmuxremote.mobile.protocol.Identity
import com.cmuxremote.mobile.protocol.Json
import com.cmuxremote.mobile.protocol.ProtocolException
import com.cmuxremote.mobile.protocol.SealedPacket
import com.cmuxremote.mobile.protocol.Signer
import com.cmuxremote.mobile.protocol.decodeSignedJson
import com.cmuxremote.mobile.protocol.int
import com.cmuxremote.mobile.protocol.objectValue
import com.cmuxremote.mobile.protocol.signedBytes
import com.cmuxremote.mobile.protocol.string
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString.Companion.toByteString
import org.bouncycastle.crypto.AsymmetricCipherKeyPair
import java.security.cert.X509Certificate
import java.util.Base64
import java.util.UUID
import java.util.concurrent.TimeUnit
import javax.net.ssl.SSLContext
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** One authenticated link event: the resource named by [id] changed. */
data class LinkEvent(val id: String, val status: Int, val final: Boolean)

/**
 * The encrypted link (`/v3/link`), used only as a change-notification channel.
 *
 * Authorization stays on each resource request over HTTPS; this channel says
 * that a resource changed and the client re-reads it. One authorization path,
 * one place where scope and revocation are enforced.
 */
class LinkClient(
    private val host: HostIdentity,
    private val endpoint: BridgeEndpoint,
    private val privateKey: ByteArray,
    private val clientID: String,
    private val agreementKey: AsymmetricCipherKeyPair,
    private val onEvent: (LinkEvent) -> Unit,
) {
    private val failures = Channel<Exception>(Channel.CONFLATED)
    private var socket: WebSocket? = null
    private var sending: HpkeSession? = null
    private var receiving: HpkeSession? = null
    private var peerAgreementKey: ByteArray? = null
    private var receivingInfoText: String? = null
    private val proposalNonce = UUID.randomUUID().toString()
    /** Built and signed once: the acceptance answers this exact value, timestamp included. */
    private val signedProposal by lazy { Signer.sign(proposalValue(), "link3-proposal", privateKey) }
    @Volatile private var closed = false

    val isOpen: Boolean get() = socket != null && sending != null && !closed

    /**
     * Dials the Bridge, over the LAN first and then through its relay.
     *
     * A LAN identity or certificate failure is not a reason to try the relay: the
     * saved pin is the trust anchor, so a mismatch must fail closed.
     */
    suspend fun connect(enrollment: Boolean = false) {
        val lan = Request.Builder()
            .url("wss://${endpoint.host}:${endpoint.port}/v3/link")
            .header("Sec-WebSocket-Protocol", "cmux-remote.v3")
            .build()
        try {
            dial(lan, pinnedClient(), relayed = false)
            com.cmuxremote.mobile.data.Diagnostics.log(
                com.cmuxremote.mobile.data.Diagnostics.Level.Info,
                "link",
                "LAN link opened to ${endpoint.host}:${endpoint.port}",
            )
            return
        } catch (error: ProtocolException) {
            com.cmuxremote.mobile.data.Diagnostics.log(
                com.cmuxremote.mobile.data.Diagnostics.Level.Warning,
                "link",
                "LAN link failed: ${error.code}",
            )
            if (error.code == "host_changed" || error.code == "invalid_certificate") throw error
        }
        val relay = endpoint.relay ?: throw ProtocolException("link_failed", "The Mac cannot be reached.", 502)
        // An enrollment permit names no device yet; the link's own join signature binds this one.
        relay.validate(host.id, if (enrollment) null else Identity.publicKeyBase64(privateKey))
        relay.verify(host.publicKey)
        dial(relayRequest(relay), systemClient(), relayed = true)
        dialedViaRelay = true
    }

    /** Dials the relay only, for a Mac whose LAN address is unreachable. */
    suspend fun connectForcedRelay(relay: RelayEndpoint, enrollment: Boolean = false) {
        relay.validate(host.id, if (enrollment) null else Identity.publicKeyBase64(privateKey))
        relay.verify(host.publicKey)
        dial(relayRequest(relay), systemClient(), relayed = true)
        dialedViaRelay = true
        com.cmuxremote.mobile.data.Diagnostics.log(
            com.cmuxremote.mobile.data.Diagnostics.Level.Info,
            "link",
            "relay link opened through ${relay.origin}",
        )
    }

    private suspend fun dial(request: Request, client: OkHttpClient, relayed: Boolean) = suspendCancellableCoroutine<Unit> { continuation ->
        var settled = false
        val webSocket = client.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                webSocket.send(Json.text(signedProposal.toJson()).encodeToByteArray().toByteString())
            }

            override fun onMessage(webSocket: WebSocket, bytes: okio.ByteString) {
                val raw = bytes.toByteArray()
                if (raw.size > 2_100_000) {
                    fail(ProtocolException("too_large", "The link packet is too large.", 413))
                    webSocket.close(1009, "too large")
                    return
                }
                if (!settled) {
                    settled = true
                    try {
                        accept(raw)
                        continuation.resume(Unit)
                    } catch (error: Exception) {
                        continuation.resumeWithException(error)
                        webSocket.cancel()
                    }
                    return
                }
                deliver(raw)
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                // A refused handshake carries the relay's stable code in its body.
                val refused = runCatching { response?.body?.string() }.getOrNull()?.trim()?.take(200)
                val code = when {
                    // A revoked identity is refused by the relay before enrollment, so this
                    // is not a lost link: the device identity itself must be replaced.
                    refused == "revoked" -> "revoked"
                    response?.code == 401 || response?.code == 403 -> "unauthorized"
                    else -> "link_failed"
                }
                val error = ProtocolException(
                    code,
                    (t.message ?: "The link was lost.") +
                        (response?.let { " (HTTP ${it.code}${refused?.let { body -> " $body" } ?: ""})" } ?: ""),
                    response?.code ?: 502,
                )
                closed = true
                if (!settled) {
                    settled = true
                    continuation.resumeWithException(error)
                } else {
                    failures.trySend(error)
                }
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                closed = true
                if (!settled) {
                    settled = true
                    continuation.resumeWithException(ProtocolException("link_failed", "The link closed before it was authenticated.", 502))
                }
            }
        })
        socket = webSocket
        continuation.invokeOnCancellation { webSocket.cancel(); closed = true }
    }

    private class Pending(
        val method: String,
        val done: kotlinx.coroutines.CompletableDeferred<ByteArray>,
    )

    private val pending = java.util.concurrent.ConcurrentHashMap<String, Pending>()
    private val chunks = java.util.concurrent.ConcurrentHashMap<String, java.io.ByteArrayOutputStream>()

    /**
     * One resource request over the link, for a Bridge reachable only through a
     * relay. Chunks are acknowledged in order, exactly as the Mac expects.
     */
    suspend fun request(method: String, uri: String, authorization: String?, body: ByteArray? = null): ByteArray {
        val id = UUID.randomUUID().toString()
        if (sending == null || closed) {
            android.util.Log.w("cmux-relay", "request before link ready $method $uri")
            throw ProtocolException("link_failed", "The link is not ready.", 502)
        }
        val deferred = kotlinx.coroutines.CompletableDeferred<ByteArray>()
        pending[id] = Pending(method, deferred)
        android.util.Log.i("cmux-relay", "request $method $uri id=$id")
        try {
            val frame = buildJsonObject {
                put("kind", JsonPrimitive("request"))
                put("id", JsonPrimitive(id))
                put("method", JsonPrimitive(method))
                put("uri", JsonPrimitive(uri))
                if (authorization != null) put("authorization", JsonPrimitive(authorization))
                if (body != null) put("data", JsonPrimitive(Base64.getEncoder().encodeToString(body)))
            }
            send(frame)
            return kotlinx.coroutines.withTimeout(30_000) { deferred.await() }
        } finally {
            pending.remove(id)
        }
    }

    /** Waits for the next link failure, so a supervisor can redial. */
    suspend fun failure(): Exception? = failures.receiveCatching().getOrNull()

    /** Subscription id → the resource path it watches, so an event names a resource. */
    val subscriptionPaths: MutableMap<String, String> = java.util.concurrent.ConcurrentHashMap()

    fun subscribe(path: String, query: Map<String, String> = emptyMap()): String {
        val id = UUID.randomUUID().toString()
        val uri = BridgeClient.uri(path, query)
        // A subscription carries its own request proof, exactly like an HTTPS read.
        val proof = com.cmuxremote.mobile.protocol.RequestProof(
            epoch = epoch,
            hostID = host.id,
            clientID = clientID,
            method = "GET",
            uri = uri,
            bodySHA256 = Identity.digest(ByteArray(0)),
            nonce = UUID.randomUUID().toString(),
            timestamp = System.currentTimeMillis() / 1000,
        )
        val authorization = "CmuxV2 " + Identity.base64(Json.bytes(Signer.sign(proof.toJson(), "request", privateKey).toJson()))
        send(buildJsonObject {
            put("kind", JsonPrimitive("subscribe"))
            put("id", JsonPrimitive(id))
            put("method", JsonPrimitive("GET"))
            put("uri", JsonPrimitive(uri))
            put("authorization", JsonPrimitive(authorization))
        })
        subscriptionPaths[id] = path
        return id
    }

    /** The Bridge epoch is public routing state; the caller supplies the one its last read used. */
    var epoch: String = ""

    fun cancel(id: String) {
        runCatching {
            send(buildJsonObject {
                put("kind", JsonPrimitive("cancel"))
                put("id", JsonPrimitive(id))
            })
        }
    }

    fun close() {
        closed = true
        socket?.close(1000, null)
        failures.close()
    }

    private fun fail(error: ProtocolException) {
        closed = true
        failures.trySend(error)
    }

    private fun send(value: JsonObject) {
        val session = sending ?: return
        if (closed) return
        val sealed = session.seal(Json.bytes(value))
        val packet = buildJsonObject {
            sealed.encapsulatedKey?.let { put("encapsulatedKey", JsonPrimitive(Base64.getEncoder().encodeToString(it))) }
            put("ciphertext", JsonPrimitive(Base64.getEncoder().encodeToString(sealed.ciphertext)))
        }
        socket?.send(Json.text(packet).encodeToByteArray().toByteString())
    }

    private fun deliver(bytes: ByteArray) {
        try {
            val root = Json.parse(String(bytes, Charsets.UTF_8)) as? JsonObject
                ?: throw ProtocolException("invalid_response", "The link packet is not an object.", 502)
            val encapsulation = root.string("encapsulatedKey")?.let { Base64.getDecoder().decode(it) }
            val ciphertext = root.string("ciphertext")?.let { Base64.getDecoder().decode(it) }
                ?: throw ProtocolException("invalid_response", "The link packet has no ciphertext.", 502)
            val session = receiving ?: run {
                val encapsulationBytes = encapsulation
                    ?: throw ProtocolException("invalid_response", "The host sent no encapsulation.", 502)
                HpkeSession.recipient(
                    agreementKey,
                    peerAgreementKey ?: throw ProtocolException("invalid_response", "No peer key.", 502),
                    encapsulationBytes,
                    receivingInfoText?.toByteArray(Charsets.US_ASCII)
                        ?: throw ProtocolException("invalid_response", "No transcript.", 502),
                ).also { receiving = it }
            }
            val plaintext = session.open(SealedPacket(encapsulation, ciphertext))
            val frame = Json.parse(String(plaintext, Charsets.UTF_8)) as? JsonObject ?: return
            val kind = frame.string("kind") ?: return
            val id = frame.string("id") ?: return
            when (kind) {
                "event" -> onEvent(LinkEvent(id = id, status = frame.int("status") ?: 200, final = frame["final"]?.toString() == "true"))
                "response" -> {
                    val item = pending[id] ?: return
                    val index = frame.int("index") ?: 0
                    val status = frame.int("status") ?: 200
                    if (status != 200) {
                        val body = frame.string("data")?.let { String(Base64.getDecoder().decode(it), Charsets.UTF_8) }
                        // Keep the Bridge's stable code: enrollment needs to tell a refused
                        // code from a lost link, and every caller localizes by code.
                        val error = runCatching {
                            (Json.parse(body ?: "") as? JsonObject)?.objectValue("error")
                        }.getOrNull()
                        item.done.completeExceptionally(
                            ProtocolException(
                                error?.string("code") ?: "connection_failed",
                                error?.string("message") ?: body ?: "The Bridge refused this request.",
                                status,
                            ),
                        )
                        return
                    }
                    val chunk = frame.string("data")?.let { Base64.getDecoder().decode(it) } ?: ByteArray(0)
                    chunks.computeIfAbsent(id) { java.io.ByteArrayOutputStream() }.write(chunk)
                    send(buildJsonObject {
                        put("kind", JsonPrimitive("ack"))
                        put("id", JsonPrimitive(id))
                        put("index", JsonPrimitive(index))
                    })
                    if (frame["final"]?.toString() == "true") {
                        val bytes = chunks.remove(id)?.toByteArray() ?: ByteArray(0)
                        item.done.complete(bytes)
                    }
                }
            }
        } catch (error: Exception) {
            fail(error as? ProtocolException ?: ProtocolException("link_failed", "The link packet was rejected.", 502))
            socket?.cancel()
        }
    }

    private fun accept(bytes: ByteArray) {
        val signed = decodeSignedJson(String(bytes, Charsets.UTF_8))
        Signer.verify(signed, "link3-acceptance", host.publicKey)
        val value = signed.value as? JsonObject
            ?: throw ProtocolException("invalid_response", "The acceptance is not an object.", 502)
        val announced = HostIdentity.from(
            value.objectValue("host") ?: throw ProtocolException("host_changed", "The acceptance names no host.", 401),
        )
        if (announced.id != host.id || announced.publicKey != host.publicKey ||
            announced.certificateSHA256 != host.certificateSHA256
        ) {
            throw ProtocolException("host_changed", "The link belongs to another host.", 401)
        }
        if (value.int("version") != 3) throw ProtocolException("host_changed", "The link speaks another version.", 401)
        val acceptanceKey = value.string("agreementKey")?.let { Base64.getDecoder().decode(it) }
            ?: throw ProtocolException("invalid_response", "The acceptance has no agreement key.", 502)
        // The Mac digests the signed envelope, signature included, not the bare value.
        val expected = Identity.digest(signedBytes("link3-proposal", signedProposal.toJson()))
        if (value.string("proposalDigest") != expected) {
            throw ProtocolException("host_changed", "The acceptance answers another proposal.", 401)
        }
        val transcript = signedBytes("link3-transcript-client", signedProposal.toJson()) +
            signedBytes("link3-transcript-host", signed.toJson())
        val digest = Identity.digest(transcript)
        peerAgreementKey = acceptanceKey
        receivingInfoText = "cmux-link/3/$digest/host-client"
        sending = HpkeSession.client(
            agreementKey,
            acceptanceKey,
            info = "cmux-link/3/$digest/client-host".toByteArray(Charsets.US_ASCII),
        )
    }

    private fun proposalValue(): JsonObject = buildJsonObject {
        put("version", JsonPrimitive(3))
        put("hostID", JsonPrimitive(host.id))
        put("clientPublicKey", JsonPrimitive(Identity.publicKeyBase64(privateKey)))
        put("agreementKey", JsonPrimitive(Base64.getEncoder().encodeToString(HpkeSession.publicKey(agreementKey))))
        put("nonce", JsonPrimitive(proposalNonce))
        put("timestamp", JsonPrimitive(System.currentTimeMillis() / 1000))
    }

    /** True once a connection was admitted through the relay. */
    @Volatile var dialedViaRelay: Boolean = false

    private fun systemClient(): OkHttpClient = OkHttpClient.Builder()
        .followRedirects(false)
        .pingInterval(25, TimeUnit.SECONDS)
        .build()

    /** A relayed dial: system PKI, with the permit and join headers that admit this device. */
    private fun relayRequest(relay: RelayEndpoint): Request {
        val publicKey = Identity.publicKeyBase64(privateKey)
        val admission = relay.connect(host.id, publicKey, privateKey)
        return Request.Builder()
            .url(admission.url)
            .header("Sec-WebSocket-Protocol", "cmux-remote.v3")
            .apply { admission.headers.forEach { (name, value) -> header(name, value) } }
            .build()
    }

    private fun pinnedClient(): OkHttpClient {
        val trust = PinnedTrustManager(host.certificateSHA256)
        val context = SSLContext.getInstance("TLS").apply { init(null, arrayOf(trust), null) }
        return OkHttpClient.Builder()
            .sslSocketFactory(context.socketFactory, trust)
            .hostnameVerifier { _, session ->
                runCatching {
                    val chain = session.peerCertificates
                    chain.isNotEmpty() && chain.first() is X509Certificate &&
                        trust.matchesPinned(chain.first() as X509Certificate)
                }.getOrDefault(false)
            }
            .followRedirects(false)
            .pingInterval(25, TimeUnit.SECONDS)
            .build()
    }
}
