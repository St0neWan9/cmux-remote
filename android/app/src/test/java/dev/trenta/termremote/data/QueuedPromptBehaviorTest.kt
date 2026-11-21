package dev.trenta.termremote.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class QueuedPromptBehaviorTest {
    @Test
    fun outgoingPromptClearsOnceBridgeReportsItQueued() {
        val recorded = OutgoingPromptMatcher.recorded(
            text = "Check CI status too",
            afterSeq = 10,
            generation = "gen-1",
            knownUserIDs = setOf("u1"),
            historyGeneration = "gen-1",
            messages = listOf(ChatMessage(id = "u1", seq = 10, role = "user", kind = "prose", text = "First")),
            queuedPrompts = listOf(QueuedPromptInfo(id = "op-1", text = "Check CI status too")),
        )
        assertTrue(recorded)
    }

    @Test
    fun turnClockStaysActiveWhenPromptsAreQueuedOrAntigravityIsWorking() {
        assertTrue(
            TurnClock.active(
                stopRequested = false,
                sentTurnRunning = false,
                working = false,
                turnCompleted = true,
                hasQueuedPrompts = true,
            ),
        )
        assertTrue(
            TurnClock.active(
                stopRequested = false,
                sentTurnRunning = false,
                working = true,
                turnCompleted = true,
                trustWorkingWhenCompleted = true,
            ),
        )
        assertFalse(
            TurnClock.active(
                stopRequested = false,
                sentTurnRunning = false,
                working = true,
                turnCompleted = true,
                trustWorkingWhenCompleted = false,
            ),
        )
        val started = Instant.ofEpochSecond(1_700_000_000L)
        assertNull(
            TurnClock.since(
                active = true,
                sentTurnRunning = false,
                sentAt = null,
                turnStartedAt = started,
                turnCompleted = true,
            ),
        )
        assertEquals(
            started,
            TurnClock.since(
                active = true,
                sentTurnRunning = false,
                sentAt = null,
                turnStartedAt = started,
                turnCompleted = false,
            ),
        )
    }
}
