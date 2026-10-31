package com.cmuxremote.mobile.protocol

import com.cmuxremote.mobile.bridge.BridgeClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** The request target signed by the proof must match the request line exactly. */
class RequestProofUriTest {
    @Test
    fun spaceInPathSegmentIsEncodedAndLeadingSlashIsKept() {
        val uri = BridgeClient.uri("/v2/sessions/a b/history", emptyMap())

        assertEquals("/v2/sessions/a%20b/history", uri)
        assertTrue(uri.startsWith("/"))
    }

    @Test
    fun queryParametersAreSortedByKey() {
        val uri = BridgeClient.uri("/v2/sessions/x/diff", mapOf("z" to "2", "a" to "1"))

        assertEquals("/v2/sessions/x/diff?a=1&z=2", uri)
    }

    @Test
    fun pathTraversalIsRejectedAsInvalidRoute() {
        try {
            BridgeClient.uri("/v2/sessions/../../etc/passwd", emptyMap())
            fail("Expected a ProtocolException")
        } catch (error: ProtocolException) {
            assertEquals("invalid_route", error.code)
        }
    }
}
