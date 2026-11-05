package com.cmuxremote.mobile.model

import java.time.Duration
import java.time.Instant

/**
 * Which conversations a list shows at once and which it folds under "earlier".
 *
 * A Mac keeps every conversation it ever ran, and most of them are history: the list opened on dozens of rows
 * the reader had no reason to see. A conversation stays in view while it is running, waiting on the reader or
 * active within the recent window; the rest fold, but every list keeps at least a few of its newest rows so a
 * group never collapses to a bare heading. The rule matches the iPhone's `SessionRecency`.
 */
class SessionRecency(private val now: Instant = Instant.now()) {
    fun isRecent(session: SessionItem): Boolean {
        if (session.working || session.waiting) return true
        val updated = session.updatedAt ?: return false
        return Duration.between(updated, now) < WINDOW
    }

    /**
     * Splits rows already in display order into what is shown and what folds. The newest [floor] rows are
     * always shown; past them a row is shown only when it is recent, so a running conversation reported without
     * a time is never folded away.
     */
    fun split(rows: List<SessionItem>, floor: Int): Pair<List<SessionItem>, List<SessionItem>> {
        val shown = mutableListOf<SessionItem>()
        val earlier = mutableListOf<SessionItem>()
        rows.forEachIndexed { index, row -> if (index < floor || isRecent(row)) shown += row else earlier += row }
        return shown to earlier
    }

    companion object {
        val WINDOW: Duration = Duration.ofDays(3)
        const val WORKSPACE_FLOOR = 3
        const val TIME_FLOOR = 6
    }
}
