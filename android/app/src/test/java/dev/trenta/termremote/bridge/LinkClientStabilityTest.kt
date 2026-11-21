package dev.trenta.termremote.bridge

import dev.trenta.termremote.protocol.AuthorizedConnection
import dev.trenta.termremote.protocol.BridgeEndpoint
import dev.trenta.termremote.protocol.ClientScope
import dev.trenta.termremote.protocol.EnrollmentGrant
import dev.trenta.termremote.protocol.HostIdentity
import dev.trenta.termremote.protocol.HpkeSession
import dev.trenta.termremote.protocol.Identity
import dev.trenta.termremote.protocol.ProtocolException
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Behavioral guards for the encrypted link lifecycle: closed links fail fast
 * instead of stalling requests for 30s, and LiveUpdates recovers instead of
 * deadlocking when a dial or existing link fails.
 */
class LinkClientStabilityTest {
    private fun fixtureConnection(): AuthorizedConnection {
        val hostKey = Identity.generatePrivateKey()
        val clientKey = Identity.generatePrivateKey()
        val host = HostIdentity(
            id = "host-stability",
            name = "Test Mac",
            publicKey = Identity.publicKeyBase64(hostKey),
            certificateSHA256 = "0".repeat(64),
        )
        val scope = ClientScope(emptyList(), emptyList())
        return AuthorizedConnection(
            host = host,
            endpoint = BridgeEndpoint(host = "127.0.0.1", port = 1),
            privateKey = clientKey,
            clientID = "client-stability",
            scope = scope,
            grantSignature = "",
            grant = EnrollmentGrant(
                hostID = host.id,
                clientID = "client-stability",
                requestID = "req-1",
                nonce = "nonce-1",
                scope = scope,
                issuedAt = 1_700_000_000L,
            ),
        )
    }

    @Test
    fun requestOnUnopenedLinkFailsImmediatelyWithLinkFailed() = runBlocking {
        val connection = fixtureConnection()
        val link = LinkClient(
            host = connection.host,
            endpoint = connection.endpoint,
            privateKey = connection.privateKey,
            clientID = connection.clientID,
            agreementKey = HpkeSession.generateKeyPair(),
            onEvent = {},
        )
        val started = System.nanoTime()
        val thrown = runCatching {
            withTimeout(2_000) { link.request("GET", "/v2/sessions", null, null) }
        }.exceptionOrNull()
        val elapsedMs = (System.nanoTime() - started) / 1_000_000
        assertTrue("expected ProtocolException, got $thrown", thrown is ProtocolException)
        assertEquals("link_failed", (thrown as ProtocolException).code)
        assertTrue("failed fast (${elapsedMs}ms)", elapsedMs < 1_000)
        assertFalse(link.isOpen)
    }

    @Test
    fun closeUnblocksFailureWaiterImmediately() = runBlocking {
        val connection = fixtureConnection()
        val link = LinkClient(
            host = connection.host,
            endpoint = connection.endpoint,
            privateKey = connection.privateKey,
            clientID = connection.clientID,
            agreementKey = HpkeSession.generateKeyPair(),
            onEvent = {},
        )
        link.close()
        withTimeout(1_000) {
            link.failure()
        }
        assertFalse(link.isOpen)
    }

    @Test
    fun liveUpdatesDetachesDeadExistingLinkAndContinuesSupervising() = runBlocking {
        val connection = fixtureConnection()
        val deadExisting = LinkClient(
            host = connection.host,
            endpoint = connection.endpoint,
            privateKey = connection.privateKey,
            clientID = connection.clientID,
            agreementKey = HpkeSession.generateKeyPair(),
            onEvent = {},
        )
        deadExisting.close()
        val closedLinks = java.util.concurrent.CopyOnWriteArrayList<LinkClient>()
        val updates = LiveUpdates(
            connection = connection,
            scope = this,
            onChanged = {},
            epoch = { "epoch-1" },
            existing = deadExisting,
            onLinkClosed = { closedLinks += it },
        )
        updates.watch(listOf("/v2/sessions", "/v2/sessions/s1/history"))
        updates.start()
        // Allow the supervisor to observe the dead existing link, detach it, and attempt a redial.
        withTimeout(3_000) {
            while (closedLinks.none { it === deadExisting }) {
                kotlinx.coroutines.delay(25)
            }
        }
        assertTrue("dead existing link was detached", closedLinks.any { it === deadExisting })
        updates.stop()
    }
}
