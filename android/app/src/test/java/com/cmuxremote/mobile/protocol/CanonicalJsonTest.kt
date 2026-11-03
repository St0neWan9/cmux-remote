package com.cmuxremote.mobile.protocol

import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Vectors generated from the Swift reference implementation
 * (`IdentityCryptography.bytes` and `JSONEncoder(.sortedKeys, .withoutEscapingSlashes)`).
 * Any byte the Kotlin client signs differently is a signature the Bridge rejects.
 */
class CanonicalJsonTest {
    private val seed = ByteArray(32) { it.toByte() }
    private val publicKey = "A6EHv/POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg="
    private val identity = "56475aa75463474c0285df5dbf2bcab73da651358839e9b77481b2eab107708c"

    @Test
    fun identityMatchesSwift() {
        assertEquals(publicKey, Identity.publicKeyBase64(seed))
        assertEquals(identity, Identity.identityId(publicKey))
    }

    @Test
    fun requestProofBytesMatchSwift() {
        val proof = RequestProof(
            epoch = "11111111-1111-1111-1111-111111111111",
            hostID = "host-abc",
            clientID = identity,
            method = "POST",
            uri = "/v2/sessions/abc/send?b=2&a=1",
            bodySHA256 = Identity.digest("hello/世界".encodeToByteArray()),
            nonce = "22222222-2222-2222-2222-222222222222",
            timestamp = 1_800_000_000,
        )
        assertEquals(
            "636d75782d72656d6f74652f322f726571756573740a7b22626f6479534841323536223a2235386432633263343333343539306563626130653264373538363837663438643734663766626135333538626137643163666463366464313934323562623339222c22636c69656e744944223a2235363437356161373534363334373463303238356466356462663262636162373364613635313335383833396539623737343831623265616231303737303863222c2265706f6368223a2231313131313131312d313131312d313131312d313131312d313131313131313131313131222c22686f73744944223a22686f73742d616263222c226d6574686f64223a22504f5354222c226e6f6e6365223a2232323232323232322d323232322d323232322d323232322d323232323232323232323232222c2274696d657374616d70223a313830303030303030302c22757269223a222f76322f73657373696f6e732f6162632f73656e643f623d3226613d31227d",
            Identity.hex(signedBytes("request", proof.toJson())),
        )
        val signed = Signer.sign(proof.toJson(), "request", seed)
        Signer.verify(signed, "request", publicKey)
    }

    @Test
    fun enrollmentRequestBytesMatchSwift() {
        val request = EnrollmentRequest(
            hostID = "host-abc",
            windowID = "33333333-3333-3333-3333-333333333333",
            requestID = "44444444-4444-4444-4444-444444444444",
            clientID = identity,
            clientPublicKey = publicKey,
            clientName = "cmux Android",
            clientKind = "android",
            nonce = "55555555-5555-5555-5555-555555555555",
            scope = ClientScope.of(
                listOf("11111111-1111-1111-1111-111111111111"),
                listOf(ClientCapability.WorkspaceRead, ClientCapability.ConversationRead, ClientCapability.ConversationControl),
            ),
            expiresAt = 1_800_000_600,
        )
        assertTrue(
            Identity.hex(signedBytes("enrollment-request", request.toJson()))
                .startsWith("636d75782d72656d6f74652f322f656e726f6c6c6d656e742d726571756573740a7b22636c69656e744944223a"),
        )
        val signed = Signer.sign(request.toJson(), "enrollment-request", seed)
        Signer.verify(signed, "enrollment-request", publicKey)
        assertTrue(
            Identity.hex(signedBytes("enrollment-request", request.toJson()))
                .contains("226361706162696c6974696573223a5b22636f6e766572736174696f6e436f6e74726f6c222c22636f6e766572736174696f6e52656164222c22776f726b737061636552656164225d"),
        )
    }

    @Test
    fun nestedValuesAndUnicodeMatchSwift() {
        val value = buildJsonObject {
            put("b", JsonPrimitive("a/b"))
            put("a", JsonPrimitive("中文😀"))
            put("c", JsonPrimitive(42))
            put("nested", buildJsonObject {
                put("z", JsonPrimitive(true))
                put("y", kotlinx.serialization.json.JsonNull)
            })
        }
        assertEquals(
            "636d75782d72656d6f74652f322f746573740a7b2261223a22e4b8ade69687f09f9880222c2262223a22612f62222c2263223a34322c226e6573746564223a7b2279223a6e756c6c2c227a223a747275657d7d",
            Identity.hex(signedBytes("test", value)),
        )
    }

    @Test
    fun emptyBodyDigestMatchesSwift() {
        assertEquals("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", Identity.digest(ByteArray(0)))
    }

    @Test
    fun signatureVerifiesAndRejectsTampering() {
        val signed = Signer.sign(buildJsonObject { put("a", JsonPrimitive("b")) }, "test", seed)
        Signer.verify(signed, "test", publicKey)
        val tampered = SignedJson(buildJsonObject { put("a", JsonPrimitive("c")) }, signed.signature)
        assertFalse(runCatching { Signer.verify(tampered, "test", publicKey) }.isSuccess)
        assertFalse(runCatching { Signer.verify(signed, "other", publicKey) }.isSuccess)
    }

    @Test
    fun signedGrantRoundTripsThroughValidation() {
        val hostKey = ByteArray(32) { (it * 7).toByte() }
        val host = HostIdentity(
            id = Identity.identityId(Identity.publicKeyBase64(hostKey)),
            publicKey = Identity.publicKeyBase64(hostKey),
            certificateSHA256 = "a".repeat(64),
            name = "Studio",
        )
        val grant = EnrollmentGrant(
            hostID = host.id,
            clientID = identity,
            requestID = "44444444-4444-4444-4444-444444444444",
            nonce = "55555555-5555-5555-5555-555555555555",
            scope = ClientScope.of(listOf("11111111-1111-1111-1111-111111111111"), listOf(ClientCapability.WorkspaceRead)),
            issuedAt = 1_800_000_100,
        )
        val grantJson = buildJsonObject {
            put("hostID", JsonPrimitive(grant.hostID))
            put("clientID", JsonPrimitive(grant.clientID))
            put("requestID", JsonPrimitive(grant.requestID))
            put("nonce", JsonPrimitive(grant.nonce))
            put("scope", grant.scope.toJson())
            put("issuedAt", JsonPrimitive(grant.issuedAt))
        }
        val signed = Signer.sign(grantJson, "grant", hostKey)
        val connection = AuthorizedConnection(
            host = host,
            endpoint = BridgeEndpoint("127.0.0.1", 7740),
            privateKey = seed,
            clientID = identity,
            scope = grant.scope,
            grantSignature = signed.signature,
            grant = grant,
        )
        connection.validate()
        assertArrayEquals(seed, AuthorizedConnection.from(connection.toJson()).privateKey)
    }
}
