package com.cmuxremote.mobile.bridge

import com.cmuxremote.mobile.protocol.Identity
import com.cmuxremote.mobile.protocol.Json
import com.cmuxremote.mobile.protocol.Signer
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Base64

/** A relay is untrusted: only entries the host really signed, for this relay, and still in window are listed. */
class RelayDirectoryTest {
    private val origin = "https://relay.example.com"
    private val seed = ByteArray(32) { it.toByte() }
    private val publicKey = Identity.publicKeyBase64(seed)
    private val identity = Identity.identityId(publicKey)
    private val now = 1_800_000_000L

    private fun bootstrap(
        name: String = "Studio",
        expiresAt: Long = now + 300,
        relayOrigin: String = origin,
        signerSeed: ByteArray = seed,
        hostID: String = identity,
        publicKeyValue: String = publicKey,
    ): String {
        val value = buildJsonObject {
            put("version", JsonPrimitive(2))
            put("expiresAt", JsonPrimitive(expiresAt))
            put("windowID", JsonPrimitive("W-1"))
            put("workspaces", kotlinx.serialization.json.JsonArray(listOf(JsonPrimitive("ws-1"))))
            put("host", buildJsonObject {
                put("id", JsonPrimitive(hostID))
                put("publicKey", JsonPrimitive(publicKeyValue))
                put("certificateSHA256", JsonPrimitive("ab".repeat(32)))
                put("name", JsonPrimitive(name))
            })
            put("endpoint", buildJsonObject {
                put("host", JsonPrimitive("10.0.0.2"))
                put("port", JsonPrimitive(7799))
                put("relay", buildJsonObject {
                    put("origin", JsonPrimitive(relayOrigin))
                    put("admission", buildJsonObject {
                        put("value", buildJsonObject {
                            put("version", JsonPrimitive(3))
                            put("kind", JsonPrimitive("enrollment"))
                            put("hostID", JsonPrimitive(hostID))
                            put("origin", JsonPrimitive(relayOrigin))
                            put("permitID", JsonPrimitive("p1"))
                            put("expiresAt", JsonPrimitive(now + 300))
                        })
                        put("signature", JsonPrimitive("AA=="))
                    })
                })
            })
        }
        val signed = Signer.sign(value, "bootstrap", signerSeed)
        return Base64.getEncoder().encodeToString(Json.text(signed.toJson()).encodeToByteArray())
    }

    private fun directory(vararg entries: String): ByteArray =
        Json.text(buildJsonObject {
            put("hosts", kotlinx.serialization.json.JsonArray(entries.map { JsonPrimitive(it) }))
        }).encodeToByteArray()

    @Test
    fun listsAVerifiedBootstrapForThisRelay() {
        val hosts = RelayDirectory.decode(directory(bootstrap()), origin, now)
        assertEquals(1, hosts.size)
        assertEquals(identity, hosts[0].host.id)
        assertEquals(origin, hosts[0].endpoint.relay?.origin)
    }

    @Test
    fun skipsAnEntryFromAnotherRelay() {
        assertTrue(RelayDirectory.decode(directory(bootstrap(relayOrigin = "https://other.example")), origin, now).isEmpty())
    }

    @Test
    fun skipsAnExpiredWindow() {
        assertTrue(RelayDirectory.decode(directory(bootstrap(expiresAt = now - 1)), origin, now).isEmpty())
    }

    @Test
    fun skipsAForgedSignature() {
        val other = ByteArray(32) { (it + 9).toByte() }
        assertTrue(RelayDirectory.decode(directory(bootstrap(signerSeed = other)), origin, now).isEmpty())
    }

    @Test
    fun keepsTheLongestWindowForOneHost() {
        val later = bootstrap(expiresAt = now + 500)
        val earlier = bootstrap(expiresAt = now + 100)
        val hosts = RelayDirectory.decode(directory(earlier, later), origin, now)
        assertEquals(1, hosts.size)
        assertEquals(now + 500, hosts[0].expiresAt)
    }

    @Test(expected = com.cmuxremote.mobile.protocol.ProtocolException::class)
    fun rejectsADirectoryWithoutHosts() {
        RelayDirectory.decode("{}".encodeToByteArray(), origin, now)
    }
}
