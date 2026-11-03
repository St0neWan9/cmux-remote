package com.cmuxremote.mobile.ui

import org.junit.Assert.assertEquals
import org.junit.Test

/** The phone shows the reader's own words, not the terminal's paste wrapper. */
class ConversationPromptTest {
    @Test
    fun removesThePastedContentWrapper() {
        val text = "\n\n<pasted_content id=\"919e\">\n第一行\n\n第二行\n</pasted_content id=\"919e\">\n"
        assertEquals("第一行\n\n第二行", displayedPrompt(text))
    }

    @Test
    fun keepsOrdinaryAngleBrackets() {
        assertEquals("what is <pasted_content>?", displayedPrompt("what is <pasted_content>?"))
    }

    @Test
    fun leavesPlainTextUntouched() {
        assertEquals("hello\nworld", displayedPrompt("hello\nworld"))
    }
}
