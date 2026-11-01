package com.cmuxremote.mobile.protocol

import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import org.junit.Assert.assertEquals
import org.junit.Test

/** The routing hint is host-signed and names the same host and device as the saved grant. */
class RelayHintTest {
    private val seed = ByteArray(32) { it.toByte() }
    private val publicKey = Identity.publicKeyBase64(seed)
    private val hint = buildJsonObject {
        put("hostID", JsonPrimitive("host"))
        put("clientID", JsonPrimitive("client"))
        put("epoch", JsonPrimitive("epoch-1"))
        put("relay", buildJsonObject {
            put("origin", JsonPrimitive("https://relay.example"))
            put("admission", buildJsonObject {
                put("value", buildJsonObject {
                    put("version", JsonPrimitive(3))
                    put("kind", JsonPrimitive("approved"))
                })
                put("signature", JsonPrimitive("AAAA"))
            })
        })
    }

    @Test
    fun aSignedHintVerifiesAndParses() {
        val signed = Signer.sign(hint, "relay3-hint", seed)
        Signer.verify(signed, "relay3-hint", publicKey)
        val parsed = RelayHint.from(signed.value as kotlinx.serialization.json.JsonObject)
        assertEquals("host", parsed.hostID)
        assertEquals("client", parsed.clientID)
        assertEquals("epoch-1", parsed.epoch)
        assertEquals("https://relay.example", parsed.relay?.origin)
        assertEquals("approved", parsed.relay?.permit?.string("kind"))
    }

    @Test(expected = ProtocolException::class)
    fun aTamperedHintFailsVerification() {
        val signed = Signer.sign(hint, "relay3-hint", seed)
        val tampered = signed.copy(value = buildJsonObject {
            put("hostID", JsonPrimitive("other"))
            put("clientID", JsonPrimitive("client"))
            put("epoch", JsonPrimitive("epoch-1"))
        })
        Signer.verify(tampered, "relay3-hint", publicKey)
    }
}
