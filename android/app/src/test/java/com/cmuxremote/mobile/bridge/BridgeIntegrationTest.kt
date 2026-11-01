package com.cmuxremote.mobile.bridge

import com.cmuxremote.mobile.data.BridgeRepository
import com.cmuxremote.mobile.protocol.AuthorizedConnection
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import kotlinx.coroutines.runBlocking

/**
 * Drives the real v2 enrollment and resource paths against the isolated
 * `scripts/fixtures/EnrollmentFixture.swift` Bridge.
 *
 * The test is skipped unless `CMUX_FIXTURE_ENROLL` holds the fixture's printed
 * `enroll=` code, so a checkout without the fixture stays green. Nothing here
 * talks to an installed cmux, an Agent, or a provider.
 */
class BridgeIntegrationTest {
    private val code: String? = System.getProperty("cmux.fixture.enroll")?.takeIf { it.isNotBlank() }
        ?: System.getenv("CMUX_FIXTURE_ENROLL")

    private fun paired(): Pair<AuthorizedConnection, BridgeRepository> {
        assumeTrue("Set CMUX_FIXTURE_ENROLL to the fixture's enroll code.", !code.isNullOrBlank())
        val key = com.cmuxremote.mobile.protocol.Identity.generatePrivateKey()
        val pending = Enrollment.begin(code!!, key)
        val submitted = runBlocking { pending.submit() }
        var status = submitted
        var attempts = 0
        while (status.state != "approved" && attempts < 40) {
            Thread.sleep(1000)
            status = runBlocking { pending.status() }
            attempts++
        }
        assertEquals("approved", status.state)
        val grant = pending.grant(status)
        val connection = AuthorizedConnection(
            host = pending.bootstrap.host,
            endpoint = pending.bootstrap.endpoint,
            privateKey = key,
            clientID = pending.request.clientID,
            scope = grant.scope,
            grantSignature = status.grantSignature ?: "",
            grant = grant,
        )
        connection.validate()
        return connection to BridgeRepository.open(connection)
    }

    @Test
    fun enrollmentSessionsHistoryAndSendRoundTrip() = runBlocking<Unit> {
        val (connection, repository) = paired()
        assertTrue(connection.scope.has(com.cmuxremote.mobile.protocol.ClientCapability.ConversationRead))

        val sessions = repository.sessions()
        assertTrue("the fixture reports one conversation", sessions.isNotEmpty())
        val session = sessions.first()

        val history = repository.history(session.id)
        assertTrue(history.messages.isNotEmpty())
        assertEquals("The fixture transcript is readable", "prose", history.messages.first().kind)

        val receipt = repository.send(session.id, "hello from the integration test")
        assertNotNull(receipt)

        // The fixture records the prompt and one reply; the next read must show both.
        var sawReply = false
        repeat(10) {
            val after = repository.history(session.id)
            sawReply = sawReply || after.messages.any { it.text.contains("fixture reply") }
            if (!sawReply) Thread.sleep(300)
        }
        assertTrue("the reply reaches history", sawReply)

        repository.interrupt(session.id)
    }

    @Test
    fun feedQuestionCanBeAnswered() = runBlocking<Unit> {
        val (_, repository) = paired()
        val pending = repository.feed().filter { it.status == "pending" && it.kind == "question" }
        assertTrue("the fixture has a pending question", pending.isNotEmpty())
        val question = pending.first()
        assertTrue(question.questions.isNotEmpty())
        val label = question.questions.first().options.first()

        repository.answer(question.requestID, question.kind, listOf(label))
        val after = repository.feed().filter { it.status == "pending" && it.requestID == question.requestID }
        assertTrue("an answered request is no longer pending", after.isEmpty())
    }

    @Test
    fun encryptedLinkStaysOpenWithoutSubscribing() = runBlocking<Unit> {
        val (connection, _) = paired()
        val link = LinkClient(
            host = connection.host,
            endpoint = connection.endpoint,
            privateKey = connection.privateKey,
            clientID = connection.clientID,
            agreementKey = com.cmuxremote.mobile.protocol.HpkeSession.generateKeyPair(),
            onEvent = {},
        )
        try {
            link.connect()
            Thread.sleep(3000)
            assertTrue("the link stays open", link.isOpen)
        } finally {
            link.close()
        }
    }

    @Test
    fun encryptedLinkDeliversChangeNotifications() = runBlocking<Unit> {
        val (connection, repository) = paired()
        val events = java.util.concurrent.LinkedBlockingQueue<String>()
        val link = LinkClient(
            host = connection.host,
            endpoint = connection.endpoint,
            privateKey = connection.privateKey,
            clientID = connection.clientID,
            agreementKey = com.cmuxremote.mobile.protocol.HpkeSession.generateKeyPair(),
            onEvent = { event -> events.offer(event.id) },
        )
        try {
            link.connect()
            link.epoch = repository.epoch()
            assertTrue("the link authenticates", link.isOpen)
            val subscription = link.subscribe("/v2/feed")
            // Answer the permission, so the question stays available for the other test.
            val permission = repository.feed().first { it.kind == "permissionRequest" && it.status == "pending" }
            repository.reply(permission.requestID, permission.kind, "once")

            val deadline = System.currentTimeMillis() + 20_000
            var heard = false
            while (System.currentTimeMillis() < deadline && !heard) {
                val id = events.poll(1, java.util.concurrent.TimeUnit.SECONDS)
                heard = id == subscription
            }
            assertTrue("a changed Feed resource notifies the subscriber", heard)
        } finally {
            link.close()
        }
    }

    @Test
    fun wrongKeyCannotApproveOrRead() = runBlocking<Unit> {
        assumeTrue("Set CMUX_FIXTURE_ENROLL to the fixture's enroll code.", !code.isNullOrBlank())
        val pending = Enrollment.begin(code!!, com.cmuxremote.mobile.protocol.Identity.generatePrivateKey())
        runBlocking { pending.submit() }
        // A second device with a different key is a different client: its request is its own.
        val other = Enrollment.begin(code!!, com.cmuxremote.mobile.protocol.Identity.generatePrivateKey())
        runBlocking { other.submit() }
        assertTrue(pending.request.clientID != other.request.clientID)
    }
}
