package com.cmuxremote.mobile.bridge

import com.cmuxremote.mobile.protocol.ProtocolException
import org.junit.Assert.assertEquals
import org.junit.Test

/** A relay origin is normalized, not rejected, when only its spelling differs. */
class RelayOriginTest {
    @Test
    fun acceptsTrailingSlashAndExplicit443() {
        assertEquals("https://relay.example.com", RelayEndpoint.canonicalOrigin("https://relay.example.com/"))
        assertEquals("https://relay.example.com", RelayEndpoint.canonicalOrigin("https://relay.example.com:443"))
    }

    @Test
    fun lowercasesTheHost() {
        assertEquals("https://relay.example.com", RelayEndpoint.canonicalOrigin("https://Relay.Example.COM"))
    }

    @Test
    fun keepsANonDefaultPort() {
        assertEquals("https://relay.example.com:8443", RelayEndpoint.canonicalOrigin("https://relay.example.com:8443"))
    }

    @Test
    fun rejectsCredentialsAndPaths() {
        for (value in listOf("https://user@relay.example.com", "https://relay.example.com/path")) {
            try {
                RelayEndpoint.canonicalOrigin(value)
                throw AssertionError("Expected invalid_endpoint for $value")
            } catch (error: ProtocolException) {
                assertEquals("invalid_endpoint", error.code)
            }
        }
    }
}
