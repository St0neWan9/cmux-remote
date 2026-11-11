package com.cmuxremote.mobile.ui

/**
 * How far the focused composer's field may grow before it scrolls inside itself, as the iPhone derives it.
 *
 * The field starts at one line and grows a line at a time. Its limit is half the height left above the keyboard,
 * less the action row and the margins, in whole lines. It used to be a third of that height with no floor, which a
 * tall keyboard or a larger font brought down to a single line: a draft longer than a line then scrolled inside a
 * one-line field, its first line pushed out of sight above a strip of padding that read as an empty line.
 */
internal object ComposerSizing {
    /** The field's line height, fixed so the limit in lines is also a limit in height. */
    const val LINE_HEIGHT_SP = 22f
    /** Never fewer: a draft of a few lines is always readable whole. */
    const val MIN_LINES = 3
    /** Never more: on a tablet half the height above the keyboard would make the field half the screen. */
    const val MAX_LINES = 10
    /** Below this visible height (split screen, a landscape phone) the bar keeps its single row. */
    const val COMPACT_BELOW_DP = 240f

    /** Lines the field may show, from the height visible above the keyboard and the reader's font scale. */
    fun maxLines(visibleDp: Float, fontScale: Float): Int {
        val line = LINE_HEIGHT_SP * fontScale.coerceAtLeast(0.5f)
        return ((visibleDp * 0.5f - 120f) / line).toInt().coerceIn(MIN_LINES, MAX_LINES)
    }

    fun compact(visibleDp: Float): Boolean = visibleDp < COMPACT_BELOW_DP
}
