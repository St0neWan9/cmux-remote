package com.cmuxremote.mobile.bridge

import com.cmuxremote.mobile.protocol.EnrollmentBootstrap
import com.cmuxremote.mobile.protocol.Json
import com.cmuxremote.mobile.protocol.ProtocolException
import com.cmuxremote.mobile.protocol.Signer
import com.cmuxremote.mobile.protocol.decodeSignedJson
import com.cmuxremote.mobile.protocol.objectValue
import com.cmuxremote.mobile.protocol.string
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonObject
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.Base64
import java.util.concurrent.TimeUnit

/**
 * Reads a relay's host directory. The relay is not trusted: every entry is
 * verified exactly like a scanned code, and a forged entry only drops itself.
 */
object RelayDirectory {
    private const val MAX_BYTES = 1_048_576
    private const val MAX_ENTRIES = 64
    private const val MAX_ENTRY_BYTES = 8_192

    private val client = OkHttpClient.Builder()
        .followRedirects(false)
        .connectTimeout(8, TimeUnit.SECONDS)
        .readTimeout(20, TimeUnit.SECONDS)
        .build()

    suspend fun hosts(origin: String, now: Long = System.currentTimeMillis() / 1000): List<EnrollmentBootstrap> =
        withContext(Dispatchers.IO) {
            val canonical = RelayEndpoint.canonicalOrigin(origin)
            val request = Request.Builder().url(canonical + "/v3/directory").get().build()
            val data = try {
                client.newCall(request).execute().use { response ->
                    if (response.code != 200) {
                        throw ProtocolException("relay_unavailable", "The relay directory is unavailable.", 502)
                    }
                    val length = response.body?.contentLength() ?: 0
                    if (length > MAX_BYTES) {
                        throw ProtocolException("relay_unavailable", "The relay directory is too large.", 502)
                    }
                    response.body?.bytes() ?: ByteArray(0)
                }
            } catch (error: ProtocolException) {
                throw error
            } catch (error: Exception) {
                throw ProtocolException("relay_unavailable", "The relay directory is unavailable.", 502)
            }
            if (data.size > MAX_BYTES) throw ProtocolException("relay_unavailable", "The relay directory is too large.", 502)
            decode(data, canonical, now)
        }

    /** Parses and verifies what the relay returned; malformed or forged entries are skipped. */
    fun decode(data: ByteArray, origin: String, now: Long = System.currentTimeMillis() / 1000): List<EnrollmentBootstrap> {
        val root = runCatching { Json.parse(String(data, Charsets.UTF_8)) as? JsonObject }.getOrNull()
            ?: throw ProtocolException("relay_unavailable", "The relay directory is unavailable.", 502)
        // The directory is `{"hosts":["<base64 signed bootstrap>", ...]}`.
        val list = (root["hosts"] as? kotlinx.serialization.json.JsonArray)
            ?.mapNotNull { (it as? kotlinx.serialization.json.JsonPrimitive)?.takeIf { primitive -> primitive.isString }?.content }
            ?: throw ProtocolException("relay_unavailable", "The relay directory is unavailable.", 502)
        if (list.size > MAX_ENTRIES) throw ProtocolException("relay_unavailable", "The relay directory is too large.", 502)

        var latest = LinkedHashMap<String, EnrollmentBootstrap>()
        for (value in list) {
            val bytes = runCatching { Base64.getDecoder().decode(value) }.getOrNull() ?: continue
            if (bytes.size > MAX_ENTRY_BYTES) continue
            val signed = runCatching { decodeSignedJson(String(bytes, Charsets.UTF_8)) }.getOrNull() ?: continue
            val valueJson = signed.value as? JsonObject ?: continue
            val hostJson = valueJson.objectValue("host") ?: continue
            val publicKey = hostJson.string("publicKey") ?: continue
            if (runCatching { Signer.verify(signed, "bootstrap", publicKey) }.isFailure) continue
            val bootstrap = runCatching { EnrollmentBootstrap.from(valueJson) }.getOrNull() ?: continue
            if (bootstrap.endpoint.relay?.origin != origin) continue
            if (runCatching { bootstrap.validate(now) }.isFailure) continue
            val existing = latest[bootstrap.host.id]
            if (existing == null || existing.expiresAt <= bootstrap.expiresAt) latest[bootstrap.host.id] = bootstrap
        }
        return latest.values.sortedBy { it.host.name.lowercase() }
    }
}
