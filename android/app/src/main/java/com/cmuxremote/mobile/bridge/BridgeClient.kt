package com.cmuxremote.mobile.bridge

import com.cmuxremote.mobile.data.Diagnostics
import com.cmuxremote.mobile.protocol.HostAnnouncement
import com.cmuxremote.mobile.protocol.Identity
import com.cmuxremote.mobile.protocol.Json
import com.cmuxremote.mobile.protocol.ProtocolException
import com.cmuxremote.mobile.protocol.RequestProof
import com.cmuxremote.mobile.protocol.Signer
import com.cmuxremote.mobile.protocol.SignedJson
import com.cmuxremote.mobile.protocol.decodeSignedJson
import com.cmuxremote.mobile.protocol.nonNullString
import com.cmuxremote.mobile.protocol.string
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.URLEncoder
import java.util.UUID

/** One authenticated HTTPS conversation with a paired Bridge. */
class BridgeClient(
    private val http: PinnedHttpClient,
    private val host: com.cmuxremote.mobile.protocol.HostIdentity,
    private val privateKey: ByteArray,
    private val clientID: String,
) {
    private var epoch: String? = null
    /** Set when the Bridge is reachable only through its relay. */
    @Volatile private var link: LinkClient? = null

    fun useLink(client: LinkClient) { link = client; epoch = null }

    fun clearLink() { link = null; epoch = null }

    val overRelay: Boolean get() = link != null

    /** The runtime epoch this client is currently signing under. */
    suspend fun currentEpoch(): String {
        epoch?.let { return it }
        return announcement().epoch
    }

    /** Reads the host's signed runtime epoch; every request proof binds it. */
    suspend fun announcement(): HostAnnouncement {
        val signed = signedRequest("GET", "/v2/identity", emptyMap(), null, null)
        Signer.verify(signed, "host", host.publicKey)
        val value = HostAnnouncement.from(signed.value as JsonObject)
        if (value.version != 2 || value.host.id != host.id || value.host.publicKey != host.publicKey ||
            value.host.certificateSHA256 != host.certificateSHA256
        ) {
            throw ProtocolException("host_changed", "The host identity changed. Pair again explicitly.")
        }
        epoch = value.epoch
        return value
    }

    /** Performs an authorized `GET`/`POST` and returns the decoded JSON body. */
    suspend fun call(method: String, path: String, query: Map<String, String> = emptyMap(), body: ByteArray? = null): kotlinx.serialization.json.JsonElement {
        val started = System.nanoTime()
        try {
            val cached = epoch ?: run { announcement(); epoch!! }
            val value = try {
                perform(method, path, query, body, cached)
            } catch (error: ProtocolException) {
                // A restarted Bridge has a new epoch while the link stays up. The proof is
                // checked before any route acts, so a rejected request did nothing; retry once.
                if (error.code == "invalid_proof" && epoch == cached) {
                    epoch = null
                    val fresh = announcement().epoch
                    perform(method, path, query, body, fresh)
                } else {
                    throw error
                }
            }
            Diagnostics.log(Diagnostics.Level.Debug, "request", "$method ${route(path)} ${elapsedMillis(started)}ms")
            return value
        } catch (error: ProtocolException) {
            // The route and the stable code are enough to diagnose; never the proof or body.
            Diagnostics.log(Diagnostics.Level.Warning, "request", "$method ${route(path)} failed: ${error.code} ${elapsedMillis(started)}ms")
            throw error
        }
    }

    private suspend fun perform(
        method: String,
        path: String,
        query: Map<String, String>,
        body: ByteArray?,
        currentEpoch: String,
    ): kotlinx.serialization.json.JsonElement {
        val uri = uri(path, query)
        val proof = RequestProof(
            epoch = currentEpoch,
            hostID = host.id,
            clientID = clientID,
            method = method,
            uri = uri,
            bodySHA256 = Identity.digest(body ?: ByteArray(0)),
            nonce = UUID.randomUUID().toString(),
            timestamp = System.currentTimeMillis() / 1000,
        )
        val header = "CmuxV2 " + Identity.base64(Json.bytes(Signer.sign(proof.toJson(), "request", privateKey).toJson()))
        val response = link?.request(method, uri, header, body) ?: exchange(method, uri, header, body)
        return Json.parse(String(response, Charsets.UTF_8))
    }

    /** Fetches a bounded binary resource such as a recorded image preview. */
    suspend fun bytes(path: String, query: Map<String, String>, limit: Int): ByteArray {
        val started = System.nanoTime()
        return try {
            val currentEpoch = epoch ?: run { announcement(); epoch!! }
            val uri = uri(path, query)
            val proof = RequestProof(
                epoch = currentEpoch,
                hostID = host.id,
                clientID = clientID,
                method = "GET",
                uri = uri,
                bodySHA256 = Identity.digest(ByteArray(0)),
                nonce = UUID.randomUUID().toString(),
                timestamp = System.currentTimeMillis() / 1000,
            )
            val header = "CmuxV2 " + Identity.base64(Json.bytes(Signer.sign(proof.toJson(), "request", privateKey).toJson()))
            val data = link?.request("GET", uri, header, null) ?: exchange("GET", uri, header, null, limit)
            Diagnostics.log(Diagnostics.Level.Debug, "request", "GET ${route(path)} ${data.size}B ${elapsedMillis(started)}ms")
            data
        } catch (error: ProtocolException) {
            Diagnostics.log(Diagnostics.Level.Warning, "request", "GET ${route(path)} failed: ${error.code} ${elapsedMillis(started)}ms")
            throw error
        }
    }

    private suspend fun signedRequest(
        method: String,
        path: String,
        query: Map<String, String>,
        body: ByteArray?,
        authorization: String?,
    ): SignedJson {
        val uri = uri(path, query)
        val response = exchange(method, uri, authorization, body)
        return decodeSignedJson(String(response, Charsets.UTF_8))
    }

    private suspend fun exchange(method: String, uri: String, authorization: String?, body: ByteArray?, limit: Int = Json.MAX_BYTES): ByteArray = withContext(Dispatchers.IO) {
        val url = http.baseUrl + uri
        val builder = Request.Builder().url(url)
        if (authorization != null) builder.header("Authorization", authorization)
        val media = "application/json".toMediaType()
        when (method) {
            "GET" -> builder.get()
            "POST" -> builder.post((body ?: ByteArray(0)).toRequestBody(media))
            else -> throw ProtocolException("invalid_route", "Unsupported method.")
        }
        http.newCall(builder.build()).execute().use { response ->
            val length = response.body?.contentLength() ?: 0
            if (length > limit) throw ProtocolException("response_too_large", "The response exceeds the read limit.", 502)
            val data = response.body?.bytes() ?: ByteArray(0)
            if (data.size > limit) throw ProtocolException("response_too_large", "The response exceeds the read limit.", 502)
            if (response.code != 200) throw decodeError(response.code, data)
            data
        }
    }

    private fun decodeError(status: Int, data: ByteArray): ProtocolException {
        val code = runCatching {
            (Json.parse(String(data, Charsets.UTF_8)) as? JsonObject)
                ?.get("error")?.let { it as? JsonObject }
                ?.string("code")
        }.getOrNull()
        val message = runCatching {
            (Json.parse(String(data, Charsets.UTF_8)) as? JsonObject)
                ?.get("error")?.let { it as? JsonObject }
                ?.string("message")
        }.getOrNull()
        return ProtocolException(code ?: "connection_failed", message ?: "The Bridge could not complete the request.", status)
    }

    companion object {
        /**
         * The exact request target the proof signs: encoded path plus sorted query.
         *
         * Both the signature and the request line come from this one string, so the
         * two never disagree about escaping.
         */
        fun uri(path: String, query: Map<String, String>): String {
            if (!path.startsWith("/v2/") || path.contains("..")) {
                throw ProtocolException("invalid_route", "Invalid resource path.")
            }
            val suffix = if (query.isEmpty()) "" else query.toSortedMap().entries.joinToString("&", prefix = "?") { (key, value) ->
                encode(key) + "=" + encode(value)
            }
            return encodePath(path) + suffix
        }

        private fun encode(value: String): String =
            URLEncoder.encode(value, "UTF-8").replace("+", "%20").replace("%7E", "~")

        private fun encodePath(path: String): String =
            path.split("/").joinToString("/") { segment ->
                URLEncoder.encode(segment, "UTF-8")
                    .replace("+", "%20")
                    .replace("%40", "@")
                    .replace("%3A", ":")
                    .replace("%2C", ",")
                    .replace("%7E", "~")
            }
    }
}

private fun elapsedMillis(started: Long): Long = (System.nanoTime() - started) / 1_000_000

/** A path with opaque ids removed, so a route can be logged without an identifier. */
private fun route(path: String): String =
    path.split('/').joinToString("/") { segment ->
        if (segment.length >= 16 && segment.all { it.isLetterOrDigit() || it == '-' || it == '_' }) ":id" else segment
    }

/** Unused import guard for the JSON primitive helper referenced by tests. */
@Suppress("unused")
private val keepImport: JsonPrimitive? = null

@Suppress("unused")
private val keepHelper: String? = null

@Suppress("unused")
private fun unusedNonNull(value: JsonObject): String? = value.nonNullString("x")
