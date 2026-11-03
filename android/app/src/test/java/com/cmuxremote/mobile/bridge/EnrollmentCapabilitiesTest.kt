package com.cmuxremote.mobile.bridge

import com.cmuxremote.mobile.protocol.ClientCapability
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
}
