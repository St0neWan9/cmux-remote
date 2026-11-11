package com.cmuxremote.mobile.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** The focused field grows a line at a time up to a limit taken from the height above the keyboard. */
class ComposerSizingTest {
    @Test
    fun aTallKeyboardOrALargeFontStillLeavesThreeLines() {
        // The old third-of-the-height rule gave one line here, and the draft scrolled inside it.
        assertEquals(3, ComposerSizing.maxLines(visibleDp = 360f, fontScale = 1f))
        assertEquals(3, ComposerSizing.maxLines(visibleDp = 400f, fontScale = 1.3f))
    }

    @Test
    fun aPhoneAboveItsKeyboardGrowsToHalfItsHeight() {
        assertEquals(5, ComposerSizing.maxLines(visibleDp = 480f, fontScale = 1f))
    }

    @Test
    fun aTabletStopsAtTheFixedLimit() {
        assertEquals(ComposerSizing.MAX_LINES, ComposerSizing.maxLines(visibleDp = 1280f, fontScale = 1f))
        assertEquals(ComposerSizing.MAX_LINES, ComposerSizing.maxLines(visibleDp = 820f, fontScale = 1f))
    }

    @Test
    fun aShortWindowKeepsTheSingleRowBar() {
        assertTrue(ComposerSizing.compact(200f))
        assertFalse(ComposerSizing.compact(300f))
    }
}
