package com.cmuxremote.mobile.protocol

import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** An approved device keeps the relay permit the Bridge bound to its key, not the window's. */
class EnrollmentStatusTest {
    @Test
    fun readsTheApprovedRelayPermit() {
        val json = Json.parse(
            """
            {
              "hostID":"h","clientID":"c","requestID":"r","nonce":"n","state":"approved",
              "relay":{"origin":"https://relay.example","admission":{
                "value":{"version":3,"hostID":"h","origin":"https://relay.example","permitID":"p",
                         "kind":"approved","clientPublicKey":"key"},
                "signature":"AAAA"}}
            }
            """.trimIndent(),
        ) as JsonObject
        val status = EnrollmentStatus.from(json)
        assertEquals("approved", status.state)
        assertEquals("https://relay.example", status.relay?.origin)
        assertEquals("approved", status.relay?.permit?.string("kind"))
        assertEquals("key", status.relay?.permit?.string("clientPublicKey"))
    }

    @Test
    fun aLanOnlyApprovalHasNoRelayPermit() {
        val json = Json.parse(
            """{"hostID":"h","clientID":"c","requestID":"r","nonce":"n","state":"approved"}""",
        ) as JsonObject
        assertNull(EnrollmentStatus.from(json).relay)
    }
}
