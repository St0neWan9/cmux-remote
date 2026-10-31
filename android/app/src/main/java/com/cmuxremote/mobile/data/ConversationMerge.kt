package com.cmuxremote.mobile.data

/**
 * Joins a page from the Bridge with what the page already shows.
 *
 * Messages are identified by their id, never by position: a refresh that updates a
 * tool result in place replaces that row, and a page read earlier is inserted by
 * its sequence rather than appended. Timing anchors follow their first message id,
 * and images belong to one transcript generation.
 */
object ConversationMerge {
    fun messages(existing: List<ChatMessage>, incoming: List<ChatMessage>): List<ChatMessage> {
        if (incoming.isEmpty()) return existing
        if (existing.isEmpty()) return incoming.sortedBy { it.seq }
        val byId = LinkedHashMap<String, ChatMessage>(existing.size + incoming.size)
        existing.forEach { byId[it.id] = it }
        incoming.forEach { byId[it.id] = it }
        return byId.values.sortedBy { it.seq }
    }

    /** A newer turn replaces the anchor with the same first message; earlier pages keep theirs. */
    fun responses(existing: List<ResponseTiming>, incoming: List<ResponseTiming>): List<ResponseTiming> {
        if (incoming.isEmpty()) return existing
        val anchors = incoming.mapTo(HashSet()) { it.firstMessageID }
        return (existing.filterNot { it.firstMessageID in anchors } + incoming)
            .sortedBy { it.firstSeq }
    }

    /**
     * Images follow their generation. A replaced transcript invalidates every older
     * image, and an image whose message was updated is replaced by the new read.
     */
    fun images(
        existing: List<ImageReference>,
        incoming: List<ImageReference>,
        generation: String,
    ): List<ImageReference> {
        if (incoming.isEmpty() && existing.all { it.generation == generation }) return existing
        val updated = incoming.mapTo(HashSet()) { it.messageID }
        val kept = existing.filter { it.generation == generation && it.messageID !in updated }
        return kept + incoming
    }
}
