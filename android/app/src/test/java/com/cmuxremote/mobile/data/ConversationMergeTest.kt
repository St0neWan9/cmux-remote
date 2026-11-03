package com.cmuxremote.mobile.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

/**
 * The page on screen and the newest read are joined by id, not by position: a refresh
 * updates a row in place, an earlier page joins above it, and a replaced transcript is
 * not mixed with the old one.
 */
class ConversationMergeTest {
    private fun message(id: String, seq: Int, text: String = id) =
        ChatMessage(id = id, seq = seq, role = "agent", kind = "prose", text = text)

    @Test
    fun aRefreshedRowReplacesTheStoredCopyInPlace() {
        val merged = ConversationMerge.messages(
            existing = listOf(message("a", 1), message("b", 2, "running")),
            incoming = listOf(message("b", 2, "succeeded")),
        )
        assertEquals(listOf("a", "b"), merged.map { it.id })
        assertEquals("succeeded", merged.last().text)
    }

    @Test
    fun anEarlierPageJoinsAboveTheNewestBySequence() {
        val merged = ConversationMerge.messages(
            existing = listOf(message("c", 30), message("d", 40)),
            incoming = listOf(message("b", 20), message("c", 30)),
        )
        assertEquals(listOf("b", "c", "d"), merged.map { it.id })
    }

    @Test
    fun responsesAreKeyedByTheirFirstMessage() {
        val first = ResponseTiming("m1", "m2", Instant.EPOCH, Instant.EPOCH, 1.0, true, true, firstSeq = 10)
        val stale = first.copy(durationSeconds = 9.0)
        val earlier = ResponseTiming("m0", "m0", Instant.EPOCH, Instant.EPOCH, 2.0, true, true, firstSeq = 1)
        val merged = ConversationMerge.responses(listOf(stale), listOf(first, earlier))
        assertEquals(listOf("m0", "m1"), merged.map { it.firstMessageID })
        assertEquals(1.0, merged.last().durationSeconds)
    }

    @Test
    fun imagesFromAnotherGenerationAreDropped() {
        val old = ImageReference("i1", "m1", "old", "a.jpg")
        val current = ImageReference("i2", "m2", "new", "b.jpg")
        val updated = ImageReference("i3", "m2", "new", "b-2.jpg")
        val merged = ConversationMerge.images(listOf(old, current), listOf(updated), "new")
        assertEquals(listOf("i3"), merged.map { it.id })
        assertTrue(merged.none { it.generation != "new" })
    }

    @Test
    fun anEmptyReadKeepsWhatIsOnScreen() {
        val existing = listOf(message("a", 1))
        assertEquals(existing, ConversationMerge.messages(existing, emptyList()))
        assertEquals(existing.map { it.id }, ConversationMerge.images(existing.map { ImageReference(it.id, it.id, "g", "") }, emptyList(), "g").map { it.id })
    }
}
