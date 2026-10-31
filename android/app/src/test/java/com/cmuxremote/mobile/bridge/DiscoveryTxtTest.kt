package com.cmuxremote.mobile.bridge

import com.cmuxremote.mobile.protocol.Identity
import com.cmuxremote.mobile.protocol.Json
import com.cmuxremote.mobile.protocol.Signer
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The Bonjour TXT record is how a nearby Mac names itself; a bad record must not become a host. */
class DiscoveryTxtTest {
    private val seed = ByteArray(32) { it.toByte() }
    private val publicKey = Identity.publicKeyBase64(seed)
    private val identity = Identity.identityId(publicKey)
    private val certificate = "ab".repeat(32)

    private fun attributes(vararg overrides: Pair<String, String?>): Map<String, ByteArray> {
        val base = mapOf(
            "version" to "2",
            "hostID" to identity,
            "publicKey" to publicKey,
            "certificate" to certificate,
            "name" to "Studio",
        )
        return (base + overrides.filter { it.second != null }.associate { it.first to it.second!! })
            .mapValues { (_, value) -> value.toByteArray(Charsets.UTF_8) }
    }

    @Test
    fun parsesTheBridgesRecord() {
        val host = DiscoveryTxt.parse("cmux-remote-abc", attributes())
        assertNotNull(host)
        assertEquals(identity, host!!.id)
        assertEquals(publicKey, host.publicKey)
        assertEquals(certificate, host.certificateSHA256)
        assertEquals("Studio", host.name)
    }

    @Test
    fun fallsBackToTheServiceNameWhenNoNameIsPublished() {
        val host = DiscoveryTxt.parse("cmux-remote-abc", attributes("name" to ""))
        assertEquals("cmux-remote-abc", host?.name)
    }

    @Test
    fun rejectsAnotherProtocolVersion() {
        assertNull(DiscoveryTxt.parse("x", attributes("version" to "3")))
    }

    @Test
    fun rejectsAnIdentityWhoseHashDoesNotMatchItsKey() {
        val otherSeed = ByteArray(32) { (it + 1).toByte() }
        val otherID = Identity.identityId(Identity.publicKeyBase64(otherSeed))
        assertNull(DiscoveryTxt.parse("x", attributes("hostID" to otherID)))
    }

    @Test
    fun rejectsAMalformedCertificate() {
        assertNull(DiscoveryTxt.parse("x", attributes("certificate" to "not-hex")))
    }

    @Test
    fun keepsTheListBoundedAndOrdered() {
        val list = (0 until 100).map { index ->
            val key = ByteArray(32) { (it + index).toByte() }
            val pub = Identity.publicKeyBase64(key)
            DiscoveredBridge(
                host = com.cmuxremote.mobile.protocol.HostIdentity(
                    id = Identity.identityId(pub),
                    publicKey = pub,
                    certificateSHA256 = certificate,
                    name = "Mac $index",
                ),
                endpoint = com.cmuxremote.mobile.protocol.BridgeEndpoint("10.0.0.$index", 7799),
            )
        }
        val bounded = DiscoveryTxt.bounded(list)
        assertEquals(64, bounded.size)
        assertTrue(bounded.zipWithNext().all { (a, b) -> a.host.id <= b.host.id })
    }

    @Test
    fun pastedEnrollmentJsonIsAcceptedWithoutTheUrlScheme() {
        val value = buildJsonObject { put("host", JsonPrimitive("x")) }
        val signed = Signer.sign(value, "bootstrap", seed)
        val decoded = EnrollmentQr.decode(Json.text(signed.toJson()))
        assertEquals(value, decoded.value)
    }

    @Test(expected = com.cmuxremote.mobile.protocol.ProtocolException::class)
    fun plainTextIsNotAnEnrollment() {
        EnrollmentQr.decode("hello")
    }
}
