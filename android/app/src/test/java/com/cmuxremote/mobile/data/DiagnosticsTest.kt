package com.cmuxremote.mobile.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** The bounded, redacting in-memory log. Diagnostics is a singleton, so each test resets it. */
class DiagnosticsTest {
    @Before
    fun reset() {
        Diagnostics.clear()
    }

    @Test
    fun ringBufferKeepsAtMostFiveHundredEntriesNewestFirst() {
        repeat(550) { index -> Diagnostics.log(Diagnostics.Level.Info, "test", "m$index") }

        val entries = Diagnostics.entries()

        assertEquals(500, entries.size)
        assertEquals("m549", entries.first().message)
        assertEquals("m50", entries.last().message)
    }

    @Test
    fun longBase64LookingTokenIsRedacted() {
        val token = "A".repeat(40)

        Diagnostics.log(Diagnostics.Level.Warning, "auth", "token=$token done")

        val message = Diagnostics.entries().single().message
        assertEquals("token=[redacted] done", message)
        assertFalse(message.contains(token))
    }

    @Test
    fun longMessagesAreTruncated() {
        // Spaces break the secret pattern, so this tests truncation rather than redaction.
        val long = "word ".repeat(300)

        Diagnostics.log(Diagnostics.Level.Debug, "chat", long)

        val message = Diagnostics.entries().single().message
        assertEquals(512, message.length)
        assertEquals(long.take(512), message)
    }

    @Test
    fun reportStartsWithHeaderAndOneLinePerEntry() {
        Diagnostics.log(Diagnostics.Level.Info, "link", "connected")
        Diagnostics.log(Diagnostics.Level.Error, "dial", "failed")

        val lines = Diagnostics.report().lines()

        assertEquals(3, lines.size)
        assertTrue(lines[0].startsWith("cmux-remote "))
        assertTrue(lines[0].contains(" · Android "))
        assertTrue(
            lines[1].matches(Regex("""\[\d{2}:\d{2}:\d{2}\.\d{3}] \[ERROR] \[dial] failed""")),
        )
        assertTrue(
            lines[2].matches(Regex("""\[\d{2}:\d{2}:\d{2}\.\d{3}] \[INFO] \[link] connected""")),
        )
    }

    @Test
    fun clearEmptiesBufferAndLeavesOnlyTheHeader() {
        Diagnostics.log(Diagnostics.Level.Info, "test", "one")

        Diagnostics.clear()

        assertEquals(emptyList<Diagnostics.Entry>(), Diagnostics.entries())
        assertEquals(1, Diagnostics.report().lines().size)
    }
}
