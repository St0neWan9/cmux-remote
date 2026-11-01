package com.cmuxremote.mobile.data

import org.junit.Assert.assertEquals
import org.junit.Test

/** A decision mode the Mac cannot deliver must never become a button. */
class FeedDecisionPolicyTest {
    private fun permission(
        available: List<String>? = null,
        source: String? = null,
        capabilities: String? = null,
    ) = FeedItem(
        requestID = "r1",
        kind = "permissionRequest",
        status = "pending",
        title = "",
        questions = emptyList(),
        availableModes = available,
        source = source,
        toolInputCapabilities = capabilities,
    )

    @Test
    fun declaredModesWin() {
        assertEquals(listOf("once", "deny"), FeedDecisionPolicy.permissionModes(permission(available = listOf("once", "deny"))))
        assertEquals(
            listOf("autoAccept", "manual"),
            FeedDecisionPolicy.planModes(
                FeedItem("r2", "exitPlan", "pending", "", emptyList(), availableModes = listOf("autoAccept", "manual")),
            ),
        )
    }

    @Test
    fun anUnknownSourceOnlyGetsBoundedDecisions() {
        assertEquals(listOf("once", "deny"), FeedDecisionPolicy.permissionModes(permission(source = "other")))
    }

    @Test
    fun claudeNeverGetsBypass() {
        assertEquals(listOf("once", "always", "all", "deny"), FeedDecisionPolicy.permissionModes(permission(source = "claude")))
    }

    @Test
    fun codexUsesItsDeclaredDecisions() {
        val modes = FeedDecisionPolicy.permissionModes(
            permission(
                source = "codex",
                capabilities = """{"available_decisions":[{"accept":{}},{"acceptForSession":{}}]}""",
            ),
        )
        assertEquals(listOf("once", "always", "deny"), modes)
    }

    @Test
    fun codexWithoutCapabilitiesCannotBypass() {
        assertEquals(
            listOf("once", "always", "all", "deny"),
            FeedDecisionPolicy.permissionModes(permission(source = "codex")),
        )
    }

    @Test
    fun noAvailablePlanModesMeansAll() {
        assertEquals(
            listOf("ultraplan", "bypassPermissions", "autoAccept", "manual", "deny"),
            FeedDecisionPolicy.planModes(FeedItem("r3", "exitPlan", "pending", "", emptyList())),
        )
    }
}
