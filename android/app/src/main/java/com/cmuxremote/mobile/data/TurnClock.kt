package com.cmuxremote.mobile.data

import java.time.Duration
import java.time.Instant

/**
 * When the turn on screen is running and where its timer counts from, decided as the iPhone decides it.
 *
 * The page used to wait for the Mac's session list to report the session working. That list is read every few
 * seconds and a cmux-tui session reports working from its rendered screen, later still: after a send the bubble's
 * "sent" line went away once the transcript recorded the prompt, and no running time took its place. The phone knows
 * a turn started the moment its send leaves, so the turn it started runs from the tap until the transcript closes it.
 */
object TurnClock {
    /** How long the Mac may list the session idle after the prompt was recorded before the phone's turn ends. */
    val abandoned: Duration = Duration.ofSeconds(60)

    /**
     * Whether the turn this phone started is still running, as far as the phone can tell before the Mac says so.
     * While the prompt waits to be recorded the transcript's current turn is still the one before it.
     */
    fun sentTurnRunning(sentAt: Instant?, outgoingPending: Boolean, outgoingUnsettled: Boolean, turnCompleted: Boolean): Boolean {
        if (sentAt == null) return false
        return if (outgoingPending) !outgoingUnsettled else !turnCompleted
    }

    fun active(stopRequested: Boolean, sentTurnRunning: Boolean, working: Boolean, turnCompleted: Boolean): Boolean =
        !stopRequested && (sentTurnRunning || (working && !turnCompleted))

    fun since(active: Boolean, sentTurnRunning: Boolean, sentAt: Instant?, turnStartedAt: Instant?): Instant? =
        if (!active) null else if (sentTurnRunning) sentAt else turnStartedAt

    /**
     * Whether a read leaves the phone's own turn standing. Once the transcript recorded the prompt its own turn
     * takes over, and a closed turn ends the phone's; an agent that went away without closing its turn is ended by
     * the Mac listing the session idle a minute after the tap.
     */
    fun keepsSentTurn(sentAt: Instant?, outgoingPending: Boolean, turnCompleted: Boolean, working: Boolean, now: Instant): Boolean {
        if (sentAt == null || outgoingPending) return sentAt != null
        if (turnCompleted) return false
        return working || Duration.between(sentAt, now) <= abandoned
    }

    /**
     * The row the running label tops: the first message of the reply in progress. A prompt not recorded yet has no
     * reply above it, and before the first reply there is none either; the label then has a row of its own.
     */
    fun liveAnchor(running: Boolean, outgoingPending: Boolean, responses: List<ResponseTiming>): String? {
        if (!running || outgoingPending) return null
        return responses.lastOrNull()?.takeIf { !it.completed }?.firstMessageID
    }
}
