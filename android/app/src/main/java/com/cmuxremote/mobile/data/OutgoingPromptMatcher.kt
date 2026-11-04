package com.cmuxremote.mobile.data

/**
 * Mirrors the iPhone's `OutgoingPromptMatcher`: a prompt sent from the phone is
 * drawn at the tail of the conversation until the Mac records it.
 */
object OutgoingPromptMatcher {
    /**
     * Whether [messages] now carries the prompt sent as [text] after [afterSeq].
     *
     * Text is compared with whitespace collapsed, because the Mac records the
     * prompt rather than the draft. A re-written prompt (image placeholders, a
     * paste summary) is still this phone's prompt when a new user message
     * appears in the same history; a changed history is only trusted on text,
     * since its old messages all look new.
     */
    fun recorded(
        text: String,
        afterSeq: Int?,
        generation: String?,
        knownUserIDs: Set<String>,
        historyGeneration: String,
        messages: List<ChatMessage>,
    ): Boolean {
        val users = messages.filter { it.kind == "prose" && it.role == "user" }
        fun recordedAfter(message: ChatMessage): Boolean {
            // A message that already existed at send time is not the prompt.
            if (message.id in knownUserIDs) return false
            if (generation != historyGeneration || afterSeq == null) return true
            return message.seq > afterSeq
        }
        val wanted = normalized(text)
        if (wanted.isNotEmpty() && users.any { recordedAfter(it) && normalized(it.text).contains(wanted) }) {
            return true
        }
        return generation == historyGeneration && users.any { recordedAfter(it) }
    }

    fun normalized(text: String): String =
        text.trim().split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ")
}
