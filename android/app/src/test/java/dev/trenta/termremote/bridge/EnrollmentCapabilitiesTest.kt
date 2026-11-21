package dev.trenta.termremote.bridge

import dev.trenta.termremote.protocol.BridgeEndpoint
import dev.trenta.termremote.protocol.ClientCapability
import dev.trenta.termremote.protocol.EnrollmentBootstrap
import dev.trenta.termremote.protocol.HostIdentity
import dev.trenta.termremote.protocol.Identity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** An older Bridge rejects the whole request over one unknown capability; the fallback asks for the rest. */
class EnrollmentCapabilitiesTest {
    @Test
    fun theFallbackDropsOnlyConversationStart() {
        assertTrue(AndroidCapabilities.contains(ClientCapability.ConversationStart))
        assertFalse(AndroidCapabilitiesBeforeStart.contains(ClientCapability.ConversationStart))
        assertEquals(
            AndroidCapabilities.size - 1,
            AndroidCapabilitiesBeforeStart.size,
        )
        assertTrue(
            AndroidCapabilitiesBeforeStart.containsAll(
                AndroidCapabilities.filterNot { it == ClientCapability.ConversationStart },
            ),
        )
    }

    @Test
    fun enrollmentDefaultsToTermRemoteAndroidClientName() {
        val hostPrivate = Identity.generatePrivateKey()
        val hostPublic = Identity.publicKeyBase64(hostPrivate)
        val bootstrap = EnrollmentBootstrap(
            host = HostIdentity(
                id = Identity.identityId(hostPublic),
                publicKey = hostPublic,
                certificateSHA256 = "a".repeat(64),
                name = "Mac",
            ),
            endpoint = BridgeEndpoint("127.0.0.1", 8443),
            workspaces = listOf("ws-1"),
            windowID = "win-1",
            expiresAt = 2_000_000_000L,
            version = 2,
        )
        val pending = Enrollment.fromBootstrap(
            bootstrap = bootstrap,
            privateKey = Identity.generatePrivateKey(),
            now = 1_999_999_800L,
        )
        assertEquals("Term Remote Android", pending.request.clientName)
        assertEquals("android", pending.request.clientKind)
    }
}
