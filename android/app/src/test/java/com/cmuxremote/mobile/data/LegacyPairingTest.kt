package com.cmuxremote.mobile.data

import com.cmuxremote.mobile.protocol.ProtocolException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.util.Base64

/** The opt-in legacy code and its manual fields are validated before any network use. */
class LegacyPairingTest {
    private val fingerprint = "ab".repeat(32)

    @Test
    fun decodesTheLegacyLink() {
        val json = """{"host":"192.168.1.10","port":8443,"token":"${"t".repeat(32)}","certificateSHA256":"$fingerprint"}"""
        val payload = Base64.getUrlEncoder().withoutPadding()
            .encodeToString(json.toByteArray(Charsets.UTF_8))
        val pairing = LegacyPairingCodec.decode("cmux-remote://pair?v=1&payload=$payload")
        assertEquals("192.168.1.10", pairing?.host)
        assertEquals(8443, pairing?.port)
        assertEquals(fingerprint, pairing?.certificateSHA256)
    }

    @Test
    fun rejectsOtherLinks() {
        assertNull(LegacyPairingCodec.decode("cmux-remote://enroll?v=2&payload=x"))
        assertNull(LegacyPairingCodec.decode("cmux-remote://pair?v=2&payload=x"))
    }

    @Test
    fun requiresATokenAndAFingerprint() {
        for (pairing in listOf(
            LegacyPairing("host", 443, "short", fingerprint),
            LegacyPairing("host", 443, "t".repeat(32), "not-a-fingerprint"),
            LegacyPairing("", 443, "t".repeat(32), fingerprint),
            LegacyPairing("host", 0, "t".repeat(32), fingerprint),
        )) {
            try {
                pairing.validate()
                throw AssertionError("Expected invalid_pairing for $pairing")
            } catch (error: ProtocolException) {
                assertEquals("invalid_pairing", error.code)
            }
        }
    }
}
