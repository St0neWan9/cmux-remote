package com.cmuxremote.mobile.data

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** The tail prompt must disappear once the Mac records it, and never before. */
class OutgoingPromptMatcherTest {
    private fun user(id: String, seq: Int, text: String) =
        ChatMessage(id = id, seq = seq, role = "user", kind = "prose", text = text)

    private fun assistant(id: String, seq: Int) =
        ChatMessage(id = id, seq = seq, role = "assistant", kind = "prose", text = "reply")

    @Test
    fun aRecordedPromptClearsEvenWhenWhitespaceDiffers() {
        val messages = listOf(user("u2", 8, "ship   the\n change"))
        assertTrue(
            OutgoingPromptMatcher.recorded(
                text = "ship the change",
                afterSeq = 7,
                generation = "g1",
                knownUserIDs = emptySet(),
                historyGeneration = "g1",
                messages = messages,
            ),
        )
    }

    @Test
    fun aMessageThatExistedAtSendTimeDoesNotClearTheTail() {
        val messages = listOf(user("u1", 3, "earlier prompt"))
        assertFalse(
            OutgoingPromptMatcher.recorded(
                text = "earlier prompt",
                afterSeq = 7,
                generation = "g1",
                knownUserIDs = setOf("u1"),
                historyGeneration = "g1",
                messages = messages,
            ),
        )
    }

    @Test
    fun aRewrittenPromptInTheSameHistoryStillClears() {
        // The agent appends an image placeholder, so the text no longer matches.
        val messages = listOf(user("u2", 9, "look at this\n[image 1]"))
        assertTrue(
            OutgoingPromptMatcher.recorded(
                text = "look at this",
                afterSeq = 7,
                generation = "g1",
                knownUserIDs = emptySet(),
                historyGeneration = "g1",
                messages = messages,
            ),
        )
    }

    @Test
    fun aChangedHistoryIsOnlyTrustedOnText() {
        val messages = listOf(user("u9", 2, "another conversation's prompt"))
        assertFalse(
            OutgoingPromptMatcher.recorded(
                text = "look at this",
                afterSeq = 7,
                generation = "g1",
                knownUserIDs = emptySet(),
                historyGeneration = "g2",
                messages = messages,
            ),
        )
    }

    @Test
    fun aNewUserMessageAfterTheSendClearsAWrappedPrompt() {
        val messages = listOf(
            assistant("a1", 8),
            user("u2", 9, "<pasted_content id=\"abc\">\nlook at this\n</pasted_content>"),
        )
        assertTrue(
            OutgoingPromptMatcher.recorded(
                text = "look at this",
                afterSeq = 7,
                generation = "g1",
                knownUserIDs = emptySet(),
                historyGeneration = "g1",
                messages = messages,
            ),
        )
    }

    @Test
    fun aReplyAloneDoesNotClearTheTail() {
        val messages = listOf(assistant("a1", 8))
        assertFalse(
            OutgoingPromptMatcher.recorded(
                text = "still waiting",
                afterSeq = 7,
                generation = "g1",
                knownUserIDs = emptySet(),
                historyGeneration = "g1",
                messages = messages,
            ),
        )
    }
}
