package com.cmuxremote.mobile.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

/** The running turn starts at the tap and keeps that start until the transcript closes it, as on the iPhone. */
class TurnClockTest {
    private val tapped = Instant.parse("2026-11-11T10:00:00Z")
    private val recordedStart = Instant.parse("2026-11-11T10:00:04Z")

    private fun running(sentAt: Instant?, pending: Boolean, unsettled: Boolean = false, working: Boolean, completed: Boolean, stop: Boolean = false): Pair<Boolean, Instant?> {
        val sent = TurnClock.sentTurnRunning(sentAt, pending, unsettled, completed)
        val active = TurnClock.active(stop, sent, working, completed)
        return active to TurnClock.since(active, sent, sentAt, recordedStart)
    }

    @Test
    fun aPromptWaitingForTheTranscriptRunsFromTheTapOnAnIdleSession() {
        // The Mac still lists the session idle and the transcript's current turn is the finished one before it.
        val (active, since) = running(tapped, pending = true, working = false, completed = true)
        assertTrue(active)
        assertEquals(tapped, since)
    }

    @Test
    fun theTimeKeepsItsStartWhenTheTranscriptRecordsThePrompt() {
        val (active, since) = running(tapped, pending = false, working = false, completed = false)
        assertTrue(active)
        assertEquals("The running time restarted from the recorded prompt", tapped, since)
    }

    @Test
    fun aClosedTurnEndsThePhonesTurn() {
        assertFalse(running(tapped, pending = false, working = true, completed = true).first)
        assertFalse(TurnClock.keepsSentTurn(tapped, outgoingPending = false, turnCompleted = true, working = true, now = tapped.plusSeconds(5)))
        // Still waiting to be recorded: the transcript's closed turn is the previous one, so the phone's turn stays.
        assertTrue(TurnClock.keepsSentTurn(tapped, outgoingPending = true, turnCompleted = true, working = false, now = tapped.plusSeconds(5)))
    }

    @Test
    fun anUnconfirmedSendOrAStopShowsNoRunningTurn() {
        assertFalse(running(tapped, pending = true, unsettled = true, working = false, completed = true).first)
        assertFalse(running(tapped, pending = true, working = true, completed = false, stop = true).first)
    }

    @Test
    fun anAgentThatLeftItsTurnOpenIsEndedByTheMacListingItIdle() {
        assertTrue(TurnClock.keepsSentTurn(tapped, outgoingPending = false, turnCompleted = false, working = false, now = tapped.plusSeconds(30)))
        assertFalse(TurnClock.keepsSentTurn(tapped, outgoingPending = false, turnCompleted = false, working = false, now = tapped.plusSeconds(61)))
        assertTrue(TurnClock.keepsSentTurn(tapped, outgoingPending = false, turnCompleted = false, working = true, now = tapped.plusSeconds(600)))
    }

    @Test
    fun withoutASendTheMacsReportDecidesAndTheTranscriptGivesTheStart() {
        val (active, since) = running(null, pending = false, working = true, completed = false)
        assertTrue(active)
        assertEquals(recordedStart, since)
        assertFalse(running(null, pending = false, working = false, completed = false).first)
    }

    @Test
    fun theLabelTopsTheReplyInProgressOrHasItsOwnRow() {
        val done = ResponseTiming("a1", "a2", null, null, 3.0, true, completed = true)
        val open = ResponseTiming("b1", "b1", null, null, null, false, completed = false)
        assertEquals("b1", TurnClock.liveAnchor(running = true, outgoingPending = false, responses = listOf(done, open)))
        // Before the first reply, and while the prompt is still on its way, the label has a row of its own.
        assertNull(TurnClock.liveAnchor(running = true, outgoingPending = false, responses = listOf(done)))
        assertNull(TurnClock.liveAnchor(running = true, outgoingPending = true, responses = listOf(done, open)))
        assertNull(TurnClock.liveAnchor(running = false, outgoingPending = false, responses = listOf(done, open)))
    }
}
