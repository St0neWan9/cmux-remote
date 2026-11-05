package com.cmuxremote.mobile.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

/** The same folding rule as the iPhone's `SessionRecencyTests`. */
class SessionRecencyTest {
    private val now = Instant.parse("2026-11-05T00:00:00Z")
    private fun session(id: String, hoursAgo: Long?, working: Boolean = false, waiting: Boolean = false) = SessionItem(
        id = id, title = id, agent = "Claude", age = "",
        updatedAt = hoursAgo?.let { now.minusSeconds(it * 3600) }, working = working, waiting = waiting,
    )

    @Test
    fun aConversationActiveWithinThreeDaysStaysInView() {
        val recency = SessionRecency(now)
        assertTrue(recency.isRecent(session("a", 71)))
        assertFalse(recency.isRecent(session("b", 73)))
        assertFalse("A conversation with no recorded activity is history", recency.isRecent(session("c", null)))
    }

    @Test
    fun aRunningOrWaitingConversationNeverFoldsWhateverItsAge() {
        val recency = SessionRecency(now)
        assertTrue(recency.isRecent(session("w", 500, working = true)))
        assertTrue(recency.isRecent(session("q", null, waiting = true)))
    }

    @Test
    fun aWorkspaceKeepsItsThreeNewestRowsEvenWhenAllAreOld() {
        val rows = (1..8).map { session("s$it", 100L + it) }
        val (shown, earlier) = SessionRecency(now).split(rows, SessionRecency.WORKSPACE_FLOOR)
        assertEquals(listOf("s1", "s2", "s3"), shown.map { it.id })
        assertEquals(5, earlier.size)
    }

    @Test
    fun recentRowsPastTheFloorStayAndOnlyOldOnesFold() {
        val rows = listOf(session("r1", 1), session("r2", 2), session("r3", 3), session("r4", 4), session("old1", 200), session("old2", null))
        val (shown, earlier) = SessionRecency(now).split(rows, SessionRecency.WORKSPACE_FLOOR)
        assertEquals(listOf("r1", "r2", "r3", "r4"), shown.map { it.id })
        assertEquals(listOf("old1", "old2"), earlier.map { it.id })
    }

    @Test
    fun aRunningConversationBelowOlderRowsIsStillShown() {
        val rows = (1..7).map { session("old$it", 100L + it) } + session("live", null, working = true)
        val (shown, earlier) = SessionRecency(now).split(rows, SessionRecency.TIME_FLOOR)
        assertEquals(listOf("old1", "old2", "old3", "old4", "old5", "old6", "live"), shown.map { it.id })
        assertEquals(listOf("old7"), earlier.map { it.id })
    }

    @Test
    fun aShortListFoldsNothing() {
        val (_, earlier) = SessionRecency(now).split(listOf(session("a", 900), session("b", 901)), SessionRecency.WORKSPACE_FLOOR)
        assertTrue(earlier.isEmpty())
    }
}
